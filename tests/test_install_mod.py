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
