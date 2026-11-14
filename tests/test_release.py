"""Offline release regression tests. No real uploads, pushes or account changes."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release', ROOT / 'tools/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_workshop_images_keep_plain_notes_and_convert_captions(self):
        plain = '1.0.2\n- 施法方向\n'
        self.assertEqual(release.workshop_changenote(plain), plain)
        notes = plain + '\n![向导](https://images.steamusercontent.com/ugc/123/ABC/)\n'
        expected = plain + '\n向导\n[img]https://images.steamusercontent.com/ugc/123/ABC/[/img]\n'
        self.assertEqual(release.workshop_changenote(notes), expected)
        config = dict(app_id=322330, publishedfileid='3834454416', title='织法之杖')
        self.assertIn('[img]', release.make_vdf(config, Path('/tmp/release'), notes))
        self.assertNotIn('![', release.make_vdf(config, Path('/tmp/release'), notes))

    def test_version_progression(self):
        self.assertEqual(release.next_version('0.25.5'), '0.25.6')
        self.assertEqual(release.next_version('0.25.5', bump='minor'), '0.26.0')
        for invalid in ['0.25.5', '0.24.9', '../bad', '01.26.0']:
            with self.assertRaises(release.ReleaseError):
                release.next_version('0.25.5', explicit=invalid)

    def test_version_only_updates_current_fields(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'mod').mkdir()
            (root / 'mod/modinfo.lua').write_text('version = "0.25.5"\nlocal release_date = "2026-01-01"\n-- old 0.25.5\n', encoding='utf-8')
            (root / 'README.md').write_text('当前测试版为 **0.25.5**。历史 0.25.5。', encoding='utf-8')
            release.update_version(root, '0.25.6')
            self.assertEqual(release.current_version(root), '0.25.6')
            self.assertIn(f'local release_date = "{release.date.today().isoformat()}"',
                          (root / 'mod/modinfo.lua').read_text(encoding='utf-8'))
            self.assertIn('历史 0.25.5', (root / 'README.md').read_text(encoding='utf-8'))
            self.assertIn('-- old 0.25.5', (root / 'mod/modinfo.lua').read_text(encoding='utf-8'))

    def test_code_vdf_never_contains_presentation_fields(self):
        config = dict(app_id=322330, publishedfileid='3834454416', title='title', preview='cover', description='intro')
        text = release.make_vdf(config, Path('/tmp/release'), 'notes')
        for field in ('previewfile', 'title', 'description', 'visibility'):
            self.assertNotIn(f'"{field}"', text)
        self.assertIn('"publishedfileid" "3834454416"', text)
        self.assertIn('"changenote" "notes"', text)
        config['publishedfileid'] = '0'
        with self.assertRaises(release.ReleaseError):
            release.make_vdf(config, Path('/tmp'), 'notes')

    def test_private_mode_rejects_exposure(self):
        release.check_audience('private', 'preserve', {'visibility': 'PRIVATE'})
        for audience, steam, repository in [('private', 'public', 'PRIVATE'), ('private', 'preserve', 'PUBLIC'),
                                             ('public', 'preserve', 'PRIVATE')]:
            with self.assertRaises(release.ReleaseError):
                release.check_audience(audience, steam, {'visibility': repository})

    def test_localized_release_does_not_overwrite_english_with_default_vdf_text(self):
        config = dict(app_id=322330, publishedfileid='3834454416', title='织法之杖',
                      workshop_languages={'schinese': {}, 'english': {}})
        text = release.make_vdf(config, Path('/tmp/release'), 'notes')
        self.assertNotIn('"description"', text)
        self.assertNotIn('"title"', text)
        self.assertNotIn('"visibility"', text)

    def test_unapproved_or_uncommitted_release_cannot_start(self):
        with patch.object(release, 'github_auth', side_effect=AssertionError('connected before approval')), \
             patch.object(release, 'release_lock', return_value=release.nullcontext()):
            with self.assertRaises(release.ReleaseError):
                release.main(['--mode', 'prepare', '--bump', 'patch'])
            with self.assertRaises(release.ReleaseError):
                release.main(['--mode', 'publish', '--bump', 'patch'])
        with patch.object(release, 'validate_release'), \
             patch.object(release, 'gh_json', side_effect=AssertionError('published before commit')):
            with self.assertRaises(release.ReleaseError):
                release.publish(Path('/tmp'), {'steps': {}}, None)

    def test_default_plan_never_runs_commands_or_changes_files(self):
        with patch.object(release, 'run', side_effect=AssertionError('plan executed a command')), \
             patch.object(release, 'prepare', side_effect=AssertionError('plan mutated files')):
            release.main([])

    def test_concurrent_publish_is_blocked_and_lock_is_released(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            with release.release_lock(root):
                with self.assertRaises(release.ReleaseError):
                    with release.release_lock(root):
                        self.fail('second publisher acquired lock')
            self.assertFalse((root / 'dist/.release.lock').exists())

    def test_export_prunes_only_owned_obsolete_files(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'tools').mkdir()
            for name in ('.gitignore', '.gitattributes', 'AGENTS.md', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.txt', 'release.ps1'):
                (root / name).touch()
            (root / '.rgignore').write_text('/assets_src/\n', encoding='utf-8')
            script = root / 'tools/export_public_source.py'
            script.write_text((ROOT / 'tools/export_public_source.py').read_text(encoding='utf-8'), encoding='utf-8')
            art = root / 'assets_src/example'
            art.mkdir(parents=True)
            for name in ('prompt.txt', 'usage.json', 'image.png', 'run.log', 'run.stdout.json', 'run.stderr.txt'):
                (art / name).write_text('fixture')
            dest = root / 'dist/export'
            dest.mkdir(parents=True)
            (dest / 'obsolete.txt').write_text('old')
            (dest / 'unmanaged.txt').write_text('keep')
            release.save(dest / '.nw_public_export', {'workspace': str(root), 'files': ['obsolete.txt']})
            import sys
            subprocess.run([sys.executable, str(script), '--output', str(dest), '--prune'], check=True, capture_output=True)
            self.assertFalse((dest / 'obsolete.txt').exists())
            self.assertTrue((dest / 'unmanaged.txt').exists())
            self.assertEqual((dest / '.rgignore').read_text(encoding='utf-8'), '/assets_src/\n')
            for name in ('prompt.txt', 'usage.json', 'image.png'):
                self.assertTrue((dest / 'assets_src/example' / name).is_file())
            for name in ('run.log', 'run.stdout.json', 'run.stderr.txt'):
                self.assertFalse((dest / 'assets_src/example' / name).exists())
                self.assertTrue((art / name).is_file(), 'Local generation logs must be retained')
            outside = root / 'keep.txt'
            outside.write_text('keep')
            release.save(dest / '.nw_public_export', {'workspace': str(root), 'files': ['../../keep.txt']})
            result = subprocess.run([sys.executable, str(script), '--output', str(dest), '--prune'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(outside.exists())

    def test_snapshot_detects_tamper_and_path_escape(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'file').write_text('original')
            before = release.hashes(root, ['file'])
            (root / 'file').write_text('tampered')
            with self.assertRaises(release.ReleaseError):
                release.verify_hashes(root, before)
            with self.assertRaises(release.ReleaseError):
                release.hashes(root, ['../outside'])

    def test_steam_requires_new_success_for_exact_item(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            exe = root / 'steamcmd.exe'
            exe.touch()
            (root / 'logs').mkdir()
            log = root / 'logs/workshop_log.txt'
            old = 'Upload finished for workshop item 3834454416 : OK\n'
            log.write_text(old)
            (root / 'description.txt').write_text('description')
            (root / 'notes.txt').write_text('notes')
            config = dict(app_id=322330, publishedfileid='3834454416', title='title')
            with patch.object(release, 'run'):
                with self.assertRaises(release.ReleaseError):
                    release.steam_upload(str(exe), 'login', root, config, 'preserve')
            def upload(*args, **kwargs):
                with log.open('a') as stream:
                    stream.write(old)
            with patch.object(release, 'run', side_effect=upload):
                release.steam_upload(str(exe), 'login', root, config, 'preserve')

    def test_pages_workflow_never_deploys_on_push_or_private_repo(self):
        text = (ROOT / '.github/workflows/pages.yml').read_text(encoding='utf-8')
        deploy = text.split('  deploy:\n')[1].split('    needs:')[0]
        self.assertIn("github.event_name == 'workflow_dispatch'", deploy)
        self.assertIn('inputs.deploy_public', deploy)
        self.assertIn('!github.event.repository.private', deploy)

    def test_pages_waits_for_new_dispatch_not_previous_success(self):
        responses = [
            {'sha': 'abc'},
            [{'databaseId': 10}],
            [{'databaseId': 10, 'status': 'completed', 'conclusion': 'success'}],
            [{'databaseId': 11, 'status': 'completed', 'conclusion': 'success'}],
        ]
        with patch.object(release, 'gh_json', side_effect=responses), patch.object(release, 'run'), \
             patch.object(release.time, 'sleep'):
            self.assertEqual(release.pages_deploy({'repository': 'owner/repo', 'branch': 'main'}, 'abc'), 11)

    def test_pages_refuses_to_deploy_a_different_commit(self):
        with patch.object(release, 'gh_json', return_value={'sha': 'different'}), \
             patch.object(release, 'run', side_effect=AssertionError('wrong version dispatched')):
            with self.assertRaises(release.ReleaseError):
                release.pages_deploy({'repository': 'owner/repo', 'branch': 'main'}, 'abc')

    def test_resume_skips_completed_steam_and_stays_private(self):
        with tempfile.TemporaryDirectory() as d:
            directory = Path(d)
            checkout = directory / 'source'
            checkout.mkdir()
            (directory / 'content').mkdir()
            exe = directory / 'steamcmd.exe'
            exe.touch()
            config = dict(repository='owner/repo', branch='main', publishedfileid='123')
            (directory / 'notes.txt').write_text('approved notes', encoding='utf-8')
            state = dict(release_kind='code', approved_notes_sha256=release.digest(directory / 'notes.txt'),
                         config=config, checkout=str(checkout), version='1.2.3', audience='private',
                         steam_visibility='preserve', source_hashes={}, artifact_hashes={},
                         steps=dict(commit='abc', push=True, github_draft=True, steam=True))
            args = type('Args', (), dict(steamcmd=str(exe), steam_user='login'))()
            commands = []
            def command(argv, **kwargs):
                commands.append(argv)
                return subprocess.CompletedProcess(argv, 0)
            def fake_git(path, *argv):
                return '' if argv[0] == 'ls-files' else 'abc'
            with patch.object(release, 'validate_checkout'), patch.object(release, 'git', side_effect=fake_git), \
                 patch.object(release, 'gh_json', return_value={'visibility': 'PRIVATE'}), \
                 patch.object(release, 'run', side_effect=command), \
                 patch.object(release, 'steam_upload', side_effect=AssertionError('duplicate upload')), \
                 patch.object(release, 'pages_deploy', side_effect=AssertionError('private website leaked')):
                release.publish(directory, state, args)
            self.assertTrue(state['steps']['github_release'])
            self.assertIn('--prerelease=true', commands[-1])
            self.assertIn('Private mode', json.loads((directory / 'state.json').read_text())['steps']['pages'])


if __name__ == '__main__':
    unittest.main()
