"""Keep main-mod updates away from a client's already loaded asset tables."""
import contextlib
import io
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import install_mod


class InstallModTests(unittest.TestCase):
    def prepare(self, root):
        workspace = root / 'workspace'
        source = workspace / 'mod'
        (source / 'anim').mkdir(parents=True)
        (source / 'modinfo.lua').write_text('version = "new"')
        with zipfile.ZipFile(source / 'anim/flight.zip', 'w') as archive:
            archive.writestr('anim.bin', b'ANIMnew')
        game = root / 'game'
        target = game / 'mods/nw_weave_dev'
        target.mkdir(parents=True)
        (target / '.nw_workspace').write_text(str(workspace))
        (target / 'modinfo.lua').write_text('version = "old"')
        return workspace, game, target

    def test_live_client_defers_before_any_destination_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            (target / 'anim').mkdir()
            old_archive = target / 'anim/flight.zip'
            old_archive.write_bytes(b'keep the loaded archive')
            with patch.object(install_mod, 'ROOT', workspace), \
                 patch.object(install_mod, 'running_game_processes', return_value=['dontstarve_steam_x64.exe (PID 123)']):
                with self.assertRaisesRegex(SystemExit, 'installation deferred.*PID 123'):
                    install_mod.install(game)
                with self.assertRaisesRegex(SystemExit, 'installation deferred.*PID 123'):
                    install_mod.install(game, ['anim/flight.zip'])
            self.assertEqual((target / 'modinfo.lua').read_text(), 'version = "old"')
            self.assertEqual(old_archive.read_bytes(), b'keep the loaded archive')
            self.assertFalse(list(target.rglob('.nw_install_*')))

    def test_offline_install_and_identical_resources_are_not_rewritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            with patch.object(install_mod, 'ROOT', workspace), \
                 patch.object(install_mod, 'running_game_processes', return_value=[]), \
                 contextlib.redirect_stdout(io.StringIO()):
                install_mod.install(game)
                archive = target / 'anim/flight.zip'
                modified = archive.stat().st_mtime_ns
                self.assertEqual((target / 'modinfo.lua').read_text(), 'version = "new"')
                with patch.object(install_mod, 'copy_atomic', side_effect=AssertionError('identical file rewritten')), \
                     patch.object(install_mod, 'running_game_processes', side_effect=AssertionError('nothing to install')):
                    install_mod.install(game)
                self.assertEqual(archive.stat().st_mtime_ns, modified)

    def test_interrupted_copy_preserves_previous_resource(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source, target = root / 'new.zip', root / 'installed.zip'
            source.write_bytes(b'new package')
            target.write_bytes(b'previous package')
            with patch.object(shutil, 'copy2', side_effect=OSError('interrupted copy')):
                with self.assertRaisesRegex(OSError, 'interrupted'):
                    install_mod.copy_atomic(source, target)
            self.assertEqual(target.read_bytes(), b'previous package')
            self.assertFalse(list(root.glob('.nw_install_*')))

    def test_selected_install_only_copies_and_verifies_selected_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            retired = target / 'anim/nw_ground_cards_0.zip'
            retired.parent.mkdir()
            retired.write_bytes(b'keep retired file in selected mode')
            # Unselected invalid archives must not expand the validation scope.
            (workspace / 'mod/anim/unselected.zip').write_bytes(b'not yet reviewed')
            output = io.StringIO()
            with patch.object(install_mod, 'ROOT', workspace), \
                 patch.object(install_mod, 'running_game_processes', return_value=[]), \
                 patch.object(install_mod, 'digest', wraps=install_mod.digest) as digests, \
                 contextlib.redirect_stdout(output):
                install_mod.install(game, ['anim/flight.zip', 'anim\\flight.zip'])
                self.assertTrue(all(call.args[0].name == 'flight.zip' for call in digests.call_args_list))
                with patch.object(install_mod, 'copy_atomic', side_effect=AssertionError('identical selected file rewritten')):
                    install_mod.install(game, ['anim/flight.zip'])
            self.assertEqual((target / 'modinfo.lua').read_text(), 'version = "old"')
            self.assertTrue((target / 'anim/flight.zip').is_file())
            self.assertFalse((target / 'anim/unselected.zip').exists())
            self.assertEqual(retired.read_bytes(), b'keep retired file in selected mode')
            self.assertIn('selected 1 files; verified 1 files', output.getvalue())
            self.assertIn('removed 0 retired files', output.getvalue())

    def test_selected_paths_are_all_validated_before_any_write(self):
        invalid = ['../outside.lua', 'anim/../../outside.lua', '/absolute.lua',
                   'C:\\absolute.lua', 'C:relative.lua', '\\\\server\\share\\file.lua',
                   'missing.lua', 'anim', '']
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            marker_before = (target / '.nw_workspace').read_bytes()
            for name in invalid:
                with self.subTest(name=name), patch.object(install_mod, 'ROOT', workspace), \
                     patch.object(install_mod, 'copy_atomic', side_effect=AssertionError('invalid plan wrote a file')):
                    with self.assertRaises(SystemExit):
                        install_mod.install(game, ['modinfo.lua', name])
                self.assertEqual((target / 'modinfo.lua').read_text(), 'version = "old"')
                self.assertEqual((target / '.nw_workspace').read_bytes(), marker_before)
                self.assertEqual(sorted(p.name for p in target.iterdir()), ['.nw_workspace', 'modinfo.lua'])

    def test_selected_symlink_escapes_are_rejected_before_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            workspace, game, target = self.prepare(root)
            outside = root / 'outside'
            outside.mkdir()
            (outside / 'flight.zip').write_bytes(b'keep external file')
            source_link = workspace / 'mod/escape.lua'
            try:
                source_link.symlink_to(outside / 'flight.zip')
                (target / 'anim').symlink_to(outside, target_is_directory=True)
            except OSError as error:
                self.skipTest(f'symlinks unavailable: {error}')
            for name in ['escape.lua', 'anim/flight.zip']:
                with self.subTest(name=name), patch.object(install_mod, 'ROOT', workspace), \
                     patch.object(install_mod, 'copy_atomic', side_effect=AssertionError('redirected plan wrote a file')):
                    with self.assertRaisesRegex(SystemExit, 'redirected'):
                        install_mod.install(game, ['modinfo.lua', name])
            self.assertEqual((target / 'modinfo.lua').read_text(), 'version = "old"')
            self.assertEqual((outside / 'flight.zip').read_bytes(), b'keep external file')

    def test_selected_invalid_archive_is_rejected_before_any_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            (workspace / 'mod/anim/flight.zip').write_bytes(b'bad archive')
            with patch.object(install_mod, 'ROOT', workspace), \
                 patch.object(install_mod, 'copy_atomic', side_effect=AssertionError('invalid archive wrote a file')):
                with self.assertRaises(zipfile.BadZipFile):
                    install_mod.install(game, ['modinfo.lua', 'anim/flight.zip'])
            self.assertEqual((target / 'modinfo.lua').read_text(), 'version = "old"')

    def test_cli_accepts_repeated_file_arguments(self):
        with patch.object(sys, 'argv', ['install_mod.py', '--game', 'example',
                                       '--file', 'anim/flight.zip', '--file', 'modinfo.lua']), \
             patch.object(install_mod, 'install') as install:
            install_mod.main()
        install.assert_called_once_with(Path('example'), ['anim/flight.zip', 'modinfo.lua'])

    def test_selected_install_still_requires_workspace_ownership(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            (target / '.nw_workspace').write_text('another workspace')
            with patch.object(install_mod, 'ROOT', workspace), \
                 patch.object(install_mod, 'copy_atomic', side_effect=AssertionError('unowned installation changed')):
                with self.assertRaisesRegex(SystemExit, 'not owned'):
                    install_mod.install(game, ['anim/flight.zip'])
            self.assertEqual((target / 'modinfo.lua').read_text(), 'version = "old"')

    def test_retired_assets_are_removed_but_unrelated_files_remain(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            retired=target/'images/inventoryimages/nw_wands_9.tex'
            retired.parent.mkdir(parents=True)
            retired.write_bytes(b'old combinations')
            keep=retired.with_name('unrelated.tex');keep.write_bytes(b'keep')
            with patch.object(install_mod, 'ROOT', workspace), \
                 patch.object(install_mod, 'running_game_processes', return_value=[]), \
                 contextlib.redirect_stdout(io.StringIO()):
                install_mod.install(game)
            self.assertFalse(retired.exists())
            self.assertEqual(keep.read_bytes(),b'keep')

    def test_retirement_only_also_requires_game_to_be_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace, game, target = self.prepare(Path(tmp))
            shutil.copytree(workspace/'mod',target,dirs_exist_ok=True)
            retired=target/'anim/nw_ground_cards_0.zip';retired.write_bytes(b'loaded')
            with patch.object(install_mod, 'ROOT', workspace), \
                 patch.object(install_mod, 'running_game_processes', return_value=['live client']):
                with self.assertRaisesRegex(SystemExit,'installation deferred'):
                    install_mod.install(game)
            self.assertEqual(retired.read_bytes(),b'loaded')

    def test_process_scan_recognizes_client_and_dedicated_server(self):
        rows = ('"dontstarve_steam_x64.exe","123","Console","1","12,345 K"\n'
                '"dontstarve_dedicated_server_nullrenderer_x64.exe","456","Console","1","10,000 K"\n'
                '"unrelated.exe","789","Console","1","1 K"\n')
        result = type('Result', (), {'stdout': rows})()
        with patch.object(install_mod.os, 'name', 'nt'), \
             patch.object(install_mod.subprocess, 'run', return_value=result):
            self.assertEqual(install_mod.running_game_processes(),
                             ['dontstarve_steam_x64.exe (PID 123)',
                              'dontstarve_dedicated_server_nullrenderer_x64.exe (PID 456)'])


if __name__ == '__main__':
    unittest.main()
