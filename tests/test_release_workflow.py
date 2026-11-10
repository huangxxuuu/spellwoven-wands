"""Review/freeze/commit/publish boundaries; no external writes or real credentials."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import release


class WorkflowTests(unittest.TestCase):
    def test_prepare_freezes_approved_notes_without_workshop_presentation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            checkout = root / 'dist/export'
            (root / 'mod').mkdir()
            (root / 'mod/modinfo.lua').write_text('version = "1.0.0"\nlocal release_date = "2026-01-01"\n')
            (root / 'README.md').write_text('README')
            (checkout / 'mod').mkdir(parents=True)
            (checkout / 'site/public').mkdir(parents=True)
            (checkout / 'site/public/index.html').write_text('guide')
            (checkout / 'dist').mkdir()
            (checkout / 'dist/nw_weave_dev-1.0.1.zip').write_bytes(b'package')
            release.save(checkout / '.nw_public_export', {'workspace': str(root), 'files': ['mod/modinfo.lua']})
            config = dict(repository='owner/repo', branch='main', export_directory='dist/export',
                          app_id=322330, publishedfileid='123', preview='MISSING.png',
                          description='MISSING.txt', workshop_languages={'schinese': {'description': 'MISSING.txt'}})
            commands = []
            def command(argv, *args, **kwargs):
                commands.append(argv)
                self.assertFalse(any('steam_workshop' in str(a) for a in argv))
                if argv[1] == 'tools/export_public_source.py':
                    (checkout / 'mod/modinfo.lua').write_bytes((root / 'mod/modinfo.lua').read_bytes())
            def git(path, *args):
                return '' if args[0] in ('status', 'fetch') else 'base'
            with patch.object(release, 'run', side_effect=command), patch.object(release, 'git', side_effect=git), \
                 patch.object(release, 'validate_checkout'):
                with self.assertRaises(release.ReleaseError):
                    release.prepare(root, config, '1.0.1', 'public', 'preserve', 'brief', 'Release v1.0.1\n\nFull detail')
                self.assertEqual(release.current_version(root), '1.0.0')
                self.assertEqual(commands, [])
                directory, state = release.prepare(root, config, '1.0.1', 'public', 'preserve',
                                                    'Approved summary', 'Release v1.0.1\n\nFull detail', True)
            self.assertEqual(state['approved_notes_sha256'], release.digest(directory / 'notes.txt'))
            self.assertEqual((directory / 'commit.txt').read_text(), 'Release v1.0.1\n\nFull detail')
            self.assertFalse(state['steps'])
            for name in ('preview.png', 'description.txt', 'workshop-localizations.json'):
                self.assertFalse((directory / name).exists())

    def test_real_local_commit_preserves_full_record_and_is_resumable(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            checkout = directory / 'checkout'
            checkout.mkdir()
            def git(*args):
                return subprocess.run(['git', *args], cwd=checkout, check=True, capture_output=True,
                                      text=True, encoding='utf-8').stdout.strip()
            git('init', '-b', 'main')
            git('config', 'user.name', 'Release Test')
            git('config', 'user.email', 'release@example.invalid')
            git('config', 'commit.gpgsign', 'false')
            git('config', 'core.autocrlf', 'false')
            git('remote', 'add', 'origin', 'https://github.com/owner/repo.git')
            (checkout / 'code.txt').write_text('old')
            git('add', '--all'); git('commit', '-m', 'base')
            base = git('rev-parse', 'HEAD')
            (checkout / 'code.txt').write_text('new')
            (directory / 'content').mkdir()
            (directory / 'notes.txt').write_text('Approved public summary')
            full = 'Release v1.0.1\n\n完整改动：模板复用、运行时上限与跨世界同步。\n验证：离线测试通过。\n'
            (directory / 'commit.txt').write_text(full, encoding='utf-8')
            state = dict(release_kind='code', version='1.0.1', steam_visibility='preserve',
                         approved_notes_sha256=release.digest(directory / 'notes.txt'),
                         config={'repository': 'owner/repo', 'branch': 'main'}, checkout=str(checkout),
                         source_hashes=release.hashes(checkout, ['code.txt']),
                         artifact_hashes=release.hashes(directory, ['notes.txt', 'commit.txt']),
                         base_commit=base, steps={})
            release.commit_release(directory, state)
            self.assertEqual(git('log', '-1', '--format=%B'), full.strip())
            first = state['steps']['commit']
            release.commit_release(directory, state)
            self.assertEqual(first, state['steps']['commit'])
            self.assertEqual(git('rev-list', '--count', 'HEAD'), '2')
            self.assertEqual(git('status', '--porcelain'), '')
            (directory / 'notes.txt').write_text('Unapproved change')
            with self.assertRaises(release.ReleaseError):
                release.commit_release(directory, state)
            self.assertEqual(git('rev-parse', 'HEAD'), first)

    def test_pages_retry_never_uploads_metadata_or_repeats_completed_content(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            state = dict(version='1.0.1', audience='public', steam_visibility='preserve', checkout=folder,
                         config={'repository': 'owner/repo', 'branch': 'main', 'publishedfileid': '123',
                                 'workshop_languages': {'english': {}}},
                         steps={'commit': 'abc', 'push': True, 'github_draft': True})
            args = SimpleNamespace(steam_backend='native', steamcmd=None, steam_api_dll=None)
            commands = []
            def command(argv, **kwargs):
                commands.append(argv)
                self.assertFalse(any('metadata' in str(a) or 'preview' in str(a) for a in argv))
                return subprocess.CompletedProcess(argv, 0)
            with patch.object(release, 'validate_release'), patch.object(release, 'git', return_value='abc'), \
                 patch.object(release, 'gh_json', side_effect=lambda *a: {'visibility': 'PUBLIC', 'build_type': 'workflow'}), \
                 patch.object(release, 'run', side_effect=command), \
                 patch.object(release, 'native_upload', return_value=True) as upload, \
                 patch.object(release, 'pages_deploy', side_effect=[release.ReleaseError('server failure'), 42]):
                with self.assertRaises(release.ReleaseError):
                    release.publish(directory, state, args)
                self.assertNotIn('github_release', state['steps'])
                release.publish(directory, state, args)
            upload.assert_called_once()
            self.assertTrue(state['steps']['github_release'])
            self.assertNotIn('steam_metadata', state['steps'])

    def test_auth_fallback_is_in_memory_and_removed_on_failure(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(release.subprocess, 'run', side_effect=[
            subprocess.CompletedProcess([], 1),
            subprocess.CompletedProcess([], 0, 'username=test\npassword=TEST_ONLY\n'),
        ]):
            with self.assertRaisesRegex(RuntimeError, 'stop'):
                with release.github_auth():
                    self.assertEqual(os.environ['GH_TOKEN'], 'TEST_ONLY')
                    raise RuntimeError('stop')
            self.assertNotIn('GH_TOKEN', os.environ)


if __name__ == '__main__':
    unittest.main()
