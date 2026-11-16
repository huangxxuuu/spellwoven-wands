"""End-to-end coordinator recovery tests; all remote boundaries are fake."""
from contextlib import ExitStack, contextmanager
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import release
import release_verify


class AllReleaseTests(unittest.TestCase):
    version = '1.0.1'

    def fixture(self, root):
        config = dict(repository='owner/repo', branch='main', export_directory='dist/export',
                      app_id=322330, publishedfileid='123')
        for name, text in {
            'mod/modinfo.lua': 'version = "1.0.0"\nlocal release_date = "2026-01-01"\n',
            'README.md': '当前测试版为 **1.0.0**\nhttps://github.com/owner/repo/releases/tag/v1.0.1',
            'site/dist/updates.html': '<article data-release-version="1.0.1">approved</article>',
            'public.txt': 'Approved public notes\n',
            'commit.txt': 'Release v1.0.1\n\nComplete changes and verification boundaries.\n',
        }.items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')
        (root / 'tools').mkdir()
        release.save(root / 'tools/release_config.json', config)
        return config

    def argv(self):
        return ['--mode', 'all', '--version', self.version, '--audience', 'public',
                '--notes-approved', '--notes-file', str(self.root / 'public.txt'),
                '--commit-file', str(self.root / 'commit.txt')]

    def freeze(self, root, config):
        directory = root / 'dist/releases' / self.version
        directory.mkdir(parents=True)
        (directory / 'notes.txt').write_bytes((root / 'public.txt').read_bytes())
        state = dict(version=self.version, audience='public', config=config,
                     approved_notes_sha256=release.digest(directory / 'notes.txt'), steps={})
        release.save(directory / 'state.json', state)
        return directory, state

    @contextmanager
    def fake_boundaries(self, root):
        # Authentication is replaced before entry: tests never inspect credentials.
        with ExitStack() as stack:
            stack.enter_context(patch.object(release, 'ROOT', root))
            stack.enter_context(patch.object(release, 'github_auth', return_value=release.nullcontext()))
            stack.enter_context(patch.object(release, 'run', side_effect=AssertionError('unexpected external command')))
            stack.enter_context(patch.object(release, 'gh_json', return_value={'visibility': 'PUBLIC'}))
            yield stack

    def test_all_prepares_commits_publishes_verifies_under_one_lock(self):
        with tempfile.TemporaryDirectory() as folder:
            self.root = root = Path(folder)
            config = self.fixture(root)
            events = []
            original_lock = release.release_lock

            def stage(name):
                self.assertTrue((root / 'dist/.release.lock').is_file())
                events.append(name)

            def prepare(*args, **kwargs):
                stage('prepare')
                self.assertTrue(kwargs['notes_approved'])
                return self.freeze(root, config)

            def commit(directory, state):
                stage('commit')
                state['steps']['commit'] = 'abc'

            def publish(directory, state, args):
                stage('publish')
                self.assertEqual(state['steps']['commit'], 'abc')
                state['steps']['github_release'] = True

            def verify(directory, state, gh):
                stage('verify')
                self.assertTrue(state['steps']['github_release'])
                return {'github': 'published', 'pages': '1.0.1'}

            with self.fake_boundaries(root), \
                 patch.object(release, 'release_lock', wraps=original_lock) as lock, \
                 patch.object(release, 'prepare', side_effect=prepare), \
                 patch.object(release, 'commit_release', side_effect=commit), \
                 patch.object(release, 'publish', side_effect=publish), \
                 patch.object(release_verify, 'verify_remote', side_effect=verify):
                result = release.main(self.argv())
            self.assertEqual(events, ['prepare', 'commit', 'publish', 'verify'])
            lock.assert_called_once_with(root)
            self.assertEqual(result, dict(mode='all', version=self.version, resume=False))
            frozen = release.read_json(root / 'dist/releases/1.0.1/state.json')
            self.assertEqual(frozen['steps']['verified']['pages'], self.version)
            self.assertFalse((root / 'dist/.release.lock').exists())

    def test_preflight_rejections_do_not_authenticate_or_change_version(self):
        for invalid in ('approval', 'readme', 'updates', 'steamcmd'):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as folder:
                self.root = root = Path(folder)
                self.fixture(root)
                argv = self.argv()
                if invalid == 'approval':
                    argv.remove('--notes-approved')
                elif invalid == 'readme':
                    (root / 'README.md').write_text('https://github.com/owner/repo/releases/tag/v1.0.0')
                elif invalid == 'updates':
                    (root / 'site/dist/updates.html').write_text(
                        '<i data-release-version="1.0.0"></i><i data-release-version="1.0.1"></i>')
                else:
                    argv += ['--steam-backend', 'steamcmd']
                with self.fake_boundaries(root), \
                     patch.object(release, 'github_auth', side_effect=AssertionError('authentication too early')), \
                     patch.object(release, 'prepare', side_effect=AssertionError('preparation too early')):
                    with self.assertRaises(release.ReleaseError):
                        release.main(argv)
                self.assertEqual(release.current_version(root), '1.0.0')
                self.assertFalse((root / 'dist/releases/1.0.1/state.json').exists())

    def test_failure_stops_later_stages_and_frozen_resume_skips_preparation(self):
        for failed in ('prepare', 'commit', 'publish', 'verify'):
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as folder:
                self.root = root = Path(folder)
                config = self.fixture(root)
                calls = []

                def action(name):
                    def execute(*args, **kwargs):
                        calls.append(name)
                        if name == failed:
                            raise release.ReleaseError('injected ' + name)
                        if name == 'prepare':
                            return self.freeze(root, config)
                        if name == 'verify':
                            return {'ok': True}
                    return execute

                with self.fake_boundaries(root), ExitStack() as stack:
                    for name, owner, attr in [('prepare', release, 'prepare'), ('commit', release, 'commit_release'),
                                              ('publish', release, 'publish'), ('verify', release_verify, 'verify_remote')]:
                        stack.enter_context(patch.object(owner, attr, side_effect=action(name)))
                    with self.assertRaisesRegex(release.ReleaseError, 'injected ' + failed) as error:
                        release.main(self.argv())
                    order = ['prepare', 'commit', 'publish', 'verify']
                    self.assertEqual(calls, order[:order.index(failed) + 1])
                    if failed == 'prepare':
                        self.assertIn('No frozen state', str(error.exception))
                        continue
                    self.assertIn('--resume 1.0.1', str(error.exception))
                    state_path = root / 'dist/releases/1.0.1/state.json'
                    before = release.read_json(state_path)
                    self.assertNotIn('verified', before['steps'])
                    # Later workspace notes are irrelevant; frozen approval survives recovery.
                    (root / 'public.txt').unlink()
                    failed = None
                    calls.clear()
                    result = release.main(['--mode', 'all', '--resume', self.version, '--audience', 'public'])
                    self.assertEqual(calls, ['commit', 'publish', 'verify'])
                    self.assertTrue(result['resume'])
                    after = release.read_json(state_path)
                    self.assertEqual(after['approved_notes_sha256'], before['approved_notes_sha256'])
                    self.assertEqual(after['steps']['verified'], {'ok': True})

    def test_all_uses_real_prepare_and_local_git_commit_with_fake_remote_services(self):
        with tempfile.TemporaryDirectory() as folder:
            self.root = root = Path(folder)
            config = self.fixture(root)
            checkout = root / config['export_directory']
            checkout.mkdir(parents=True)

            def local_git(*args):
                return subprocess.run(['git', *args], cwd=checkout, check=True, capture_output=True,
                                      text=True, encoding='utf-8').stdout.strip()

            local_git('init', '-b', 'main')
            for key, value in [('user.name', 'Offline Release Test'), ('user.email', 'test@example.invalid'),
                               ('commit.gpgsign', 'false'), ('core.autocrlf', 'false'),
                               ('core.hooksPath', str(root / 'no-hooks'))]:
                local_git('config', key, value)
            local_git('remote', 'add', 'origin', 'https://github.com/owner/repo.git')
            paths = ['mod/modinfo.lua', 'README.md', 'site/dist/updates.html', '.gitignore']
            (root / '.gitignore').write_text('/dist/\n/site/public/\n/.nw_public_export\n')

            def export():
                for name in paths:
                    target = checkout / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(root / name, target)
                release.save(checkout / '.nw_public_export', {'workspace': str(root), 'files': paths})

            export()
            local_git('add', '--all')
            local_git('commit', '-m', 'base')
            base = local_git('rev-parse', 'HEAD')
            local_git('update-ref', 'refs/remotes/origin/main', base)
            original_run = release.run
            commands = []

            def command(argv, cwd=None, **kwargs):
                argv = [str(a) for a in argv]
                commands.append(argv)
                if argv[0] == 'git' and argv[1] not in ('fetch', 'push'):
                    return original_run(argv, cwd, **kwargs)
                if argv[0] == 'gh':
                    # A missing draft exercises creation, then fake upload/edit succeed.
                    return subprocess.CompletedProcess(argv, 1 if argv[1:3] == ['release', 'view'] else 0, '', '')
                if len(argv) > 1 and argv[1] == 'tools/export_public_source.py':
                    export()
                if len(argv) > 1 and argv[1] == 'tools/build_package.py':
                    (checkout / 'dist').mkdir(exist_ok=True)
                    (checkout / 'dist/nw_weave_dev-1.0.1.zip').write_bytes(b'offline package')
                if len(argv) > 1 and argv[1] == 'site/build_catalog.py' and cwd == checkout:
                    (checkout / 'site/public').mkdir(parents=True, exist_ok=True)
                    (checkout / 'site/public/index.html').write_text('offline guide')
                allowed = argv[0] == 'git' or (argv[0] == sys.executable and argv[1] in {
                    'site/build_catalog.py', 'tools/export_public_source.py', 'tools/run_tests.py',
                    'tools/quiet_check.py', 'tools/build_package.py', 'tools/run_python_tests.py'})
                self.assertTrue(allowed, 'unexpected command: ' + repr(argv))
                return subprocess.CompletedProcess(argv, 0, '', '')

            def verify(directory, state, gh):
                self.assertTrue(state['steps']['github_release'])
                self.assertEqual(local_git('rev-parse', 'HEAD'), state['steps']['commit'])
                return {'offline_remote_evidence': True}

            with self.fake_boundaries(root), patch.object(release, 'run', side_effect=command), \
                 patch.object(release, 'gh_json', return_value={'visibility': 'PUBLIC', 'build_type': 'workflow'}), \
                 patch.object(release, 'native_upload', return_value=True) as steam, \
                 patch.object(release, 'pages_deploy', return_value=42) as pages, \
                 patch.object(release_verify, 'verify_remote', side_effect=verify):
                release.main(self.argv())
            self.assertEqual(local_git('rev-list', '--count', 'HEAD'), '2')
            self.assertEqual(local_git('log', '-1', '--format=%B'), (root / 'commit.txt').read_text().strip())
            self.assertEqual(local_git('status', '--porcelain'), '')
            self.assertEqual(release.current_version(checkout), self.version)
            state = release.read_json(root / 'dist/releases/1.0.1/state.json')
            self.assertEqual(set(state['steps']), {'commit', 'push', 'github_draft', 'steam', 'pages',
                                                   'github_release', 'verified'})
            self.assertTrue(any(c[1:] == ['tools/run_python_tests.py'] for c in commands))
            steam.assert_called_once()
            pages.assert_called_once()


class PersistentBoundaryTests(unittest.TestCase):
    config = {'repository': 'owner/repo', 'branch': 'main'}
    successful_jobs = {'jobs': [{'name': 'deploy', 'status': 'completed', 'conclusion': 'success'}]}

    def test_publish_failure_never_marks_failed_or_later_stages_complete(self):
        order = ['push', 'github_draft', 'steam', 'pages', 'github_release']
        for failed in order:
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder)
                for name in ('notes.txt', 'spellwoven-wands-1.0.1.zip', 'field-guide-1.0.1.zip'):
                    (directory / name).write_bytes(b'offline artifact')
                state = dict(version='1.0.1', audience='public', steam_visibility='preserve',
                             checkout=folder, config=dict(self.config, publishedfileid='123'),
                             steps={'commit': 'abc'})
                release.save(directory / 'state.json', state)
                calls = []

                def stage(name):
                    calls.append(name)
                    if name == failed:
                        raise release.ReleaseError('injected ' + name)
                    return True

                def git(path, *args):
                    if args[0] == 'push':
                        stage('push')
                    return 'abc'

                def command(argv, *args, **kwargs):
                    if argv[:3] == ['gh', 'release', 'view']:
                        return subprocess.CompletedProcess(argv, 1, '', '')
                    if argv[:3] == ['gh', 'release', 'create']:
                        stage('github_draft')
                    elif argv[:3] == ['gh', 'release', 'edit']:
                        stage('github_release')
                    elif argv[:3] not in (['git', 'rev-parse', '--verify'], ['gh', 'release', 'upload']):
                        self.fail('unexpected external command: ' + repr(argv))
                    return subprocess.CompletedProcess(argv, 0, '', '')

                args = SimpleNamespace(steam_backend='native', steamcmd=None, steam_api_dll=None)
                with patch.object(release, 'validate_release'), patch.object(release, 'git', side_effect=git), \
                     patch.object(release, 'gh_json', return_value={'visibility': 'PUBLIC', 'build_type': 'workflow'}), \
                     patch.object(release, 'run', side_effect=command), \
                     patch.object(release, 'native_upload', side_effect=lambda *a: stage('steam')), \
                     patch.object(release, 'pages_deploy', side_effect=lambda *a, **kw: stage('pages')):
                    with self.assertRaisesRegex(release.ReleaseError, 'injected ' + failed):
                        release.publish(directory, state, args)
                index = order.index(failed)
                self.assertEqual(calls, order[:index + 1])
                self.assertEqual(set(release.read_json(directory / 'state.json')['steps']),
                                 {'commit', *order[:index]})

    def test_pages_resume_waits_for_recorded_run_and_ignores_other_success(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            state = {'pending': {'pages': {'commit': 'abc', 'prior_ids': [10], 'run_id': 11}}}
            release.save(path, state)
            responses = [[{'databaseId': 12, 'status': 'completed', 'conclusion': 'success'},
                          {'databaseId': 11, 'status': 'in_progress', 'conclusion': None}],
                         [{'databaseId': 11, 'status': 'completed', 'conclusion': 'success'}],
                         self.successful_jobs]
            with patch.object(release, 'gh_json', side_effect=responses) as remote, \
                 patch.object(release, 'run', side_effect=AssertionError('duplicate dispatch')), \
                 patch.object(release.time, 'sleep'):
                self.assertEqual(release.pages_deploy(self.config, 'abc', journal=state, state_path=path), 11)
            self.assertEqual(release.read_json(path)['pending']['pages']['run_id'], 11)
            # Main may have advanced while this dispatch was running. Recovery only
            # observes the recorded workflow and deploy job, never branch HEAD.
            self.assertFalse(any('/commits/' in str(call) for call in remote.call_args_list))
            self.assertEqual(remote.call_args.args,
                             ('api', 'repos/owner/repo/actions/runs/11/jobs?per_page=100'))

    def test_pages_timeout_preserves_dispatch_before_command_and_retry_does_not_dispatch(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            state = {}

            def dispatch(*args, **kwargs):
                pending = release.read_json(path)['pending']['pages']
                self.assertEqual(pending['commit'], 'abc')
                self.assertEqual(pending['prior_ids'], [10])
                self.assertIsNone(pending['run_id'])
                self.assertRegex(pending['release_id'], r'^[0-9a-f]{32}$')
                self.assertIn('release_id=' + pending['release_id'], args[0])

            with patch.object(release, 'gh_json', side_effect=[{'sha': 'abc'}, [{'databaseId': 10}]]), \
                 patch.object(release, 'run', side_effect=dispatch) as command:
                with self.assertRaisesRegex(release.ReleaseError, 'timeout'):
                    release.pages_deploy(self.config, 'abc', deadline_seconds=0, journal=state, state_path=path)
            command.assert_called_once()
            resumed = release.read_json(path)
            title = 'Field guide ' + resumed['pending']['pages']['release_id']
            with patch.object(release, 'gh_json', side_effect=[
                    [{'databaseId': 11, 'displayTitle': title, 'status': 'completed', 'conclusion': 'success'}],
                    self.successful_jobs]), \
                 patch.object(release, 'run', side_effect=AssertionError('duplicate dispatch')):
                self.assertEqual(release.pages_deploy(self.config, 'abc', journal=resumed, state_path=path), 11)

    def test_pages_known_failure_clears_pending_and_allows_new_dispatch(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            state = {'pending': {'pages': {'commit': 'abc', 'prior_ids': [10], 'run_id': 11}}}
            with patch.object(release, 'gh_json', side_effect=[
                    [{'databaseId': 11, 'status': 'completed', 'conclusion': 'failure'}]]), \
                 patch.object(release, 'run', side_effect=AssertionError('duplicate dispatch')):
                with self.assertRaisesRegex(release.ReleaseError, 'failed'):
                    release.pages_deploy(self.config, 'abc', journal=state, state_path=path)
            self.assertNotIn('pages', release.read_json(path)['pending'])
            def response(*args):
                if args[0] == 'api':
                    return self.successful_jobs if '/jobs?' in args[1] else {'sha': 'abc'}
                if args[-1] == 'databaseId':
                    return [{'databaseId': 11}]
                return [{'databaseId': 12, 'displayTitle': 'Field guide ' + state['pending']['pages']['release_id'],
                         'status': 'completed', 'conclusion': 'success'}]

            with patch.object(release, 'gh_json', side_effect=response), \
                 patch.object(release, 'run') as dispatch:
                self.assertEqual(release.pages_deploy(self.config, 'abc', journal=state, state_path=path), 12)
            dispatch.assert_called_once()

    def test_pages_ignores_same_commit_dispatch_without_its_unique_release_id(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'state.json'
            state = {}
            polls = []

            def response(*args):
                if args[0] == 'api':
                    if '/jobs?' in args[1]:
                        self.assertIn('/runs/12/', args[1])
                        return self.successful_jobs
                    return {'sha': 'abc'}
                if args[-1] == 'databaseId':
                    return [{'databaseId': 10}]
                polls.append(True)
                other = {'databaseId': 11, 'displayTitle': 'Field guide somebody-else',
                         'status': 'completed', 'conclusion': 'success'}
                if len(polls) == 1:
                    return [other]
                return [other, {'databaseId': 12,
                               'displayTitle': 'Field guide ' + state['pending']['pages']['release_id'],
                               'status': 'completed', 'conclusion': 'success'}]

            with patch.object(release, 'gh_json', side_effect=response), patch.object(release, 'run') as dispatch, \
                 patch.object(release.time, 'sleep'):
                self.assertEqual(release.pages_deploy(self.config, 'abc', journal=state, state_path=path), 12)
            self.assertEqual(len(polls), 2)
            self.assertEqual(release.read_json(path)['pending']['pages']['run_id'], 12)
            dispatch.assert_called_once()

    def test_pages_success_with_skipped_or_missing_deploy_job_is_rejected(self):
        for jobs in ([{'name': 'deploy', 'status': 'completed', 'conclusion': 'skipped'}],
                     [{'name': 'build', 'status': 'completed', 'conclusion': 'success'}]):
            with self.subTest(jobs=jobs), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'state.json'
                state = {'pending': {'pages': {'commit': 'abc', 'prior_ids': [], 'run_id': 11}}}
                release.save(path, state)
                with patch.object(release, 'gh_json', side_effect=[
                        [{'databaseId': 11, 'status': 'completed', 'conclusion': 'success'}], {'jobs': jobs}]), \
                     patch.object(release, 'run', side_effect=AssertionError('duplicate dispatch')):
                    with self.assertRaises(release.ReleaseError):
                        release.pages_deploy(self.config, 'abc', journal=state, state_path=path)

    def test_native_receipt_reused_only_for_matching_confirmed_frozen_upload(self):
        for mismatch in (None, 'artifact_hashes', 'approved_notes_sha256', 'version', 'item_id', 'complete', 'result'):
            with self.subTest(mismatch=mismatch), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder)
                (directory / 'notes.txt').write_text('approved')
                (directory / 'content').mkdir()
                (directory / 'content/modinfo.lua').write_text('version = "1.0.1"')
                state = dict(version='1.0.1', config={'publishedfileid': '123'},
                             approved_notes_sha256=release.digest(directory / 'notes.txt'),
                             artifact_hashes=release.hashes(directory, ['notes.txt', 'content/modinfo.lua']))
                release.save(directory / 'state.json', state)
                receipt = dict(complete=True, result='OK', version=state['version'], item_id=123,
                               artifact_hashes=state['artifact_hashes'],
                               approved_notes_sha256=state['approved_notes_sha256'])
                if mismatch:
                    receipt[mismatch] = {'notes.txt': 'wrong'} if mismatch == 'artifact_hashes' else 'wrong'
                release.save(directory / 'steam-api-upload-001.json', receipt)
                with patch.object(release, 'run') as command:
                    self.assertTrue(release.native_upload(directory))
                self.assertEqual(command.call_count, int(mismatch is not None))
                if mismatch:
                    self.assertIn('steam_workshop_upload.py', str(command.call_args.args[0][1]))


if __name__ == '__main__':
    unittest.main()
