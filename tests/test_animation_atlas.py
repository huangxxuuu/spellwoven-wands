"""Regression coverage for compiler-successful but unsampleable atlas pages."""
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from animation_atlas import AnimationAtlasError, validate_animation_archive


def fixture(path, pages, samplers):
    def text(value):
        value = value.encode('utf8')
        return struct.pack('<I', len(value)) + value
    data = struct.pack('<4sIII', b'BILD', 6, 1, 1) + text('fixture') + struct.pack('<I', pages)
    data += b''.join(text(f'atlas-{i}.tex') for i in range(pages))
    data += struct.pack('<II', 1, 1)
    data += struct.pack('<IIffffII', 0, 1, 0, 0, 20, 20, 0, len(samplers))
    data += struct.pack('<I', len(samplers))
    data += b''.join(struct.pack('<ffffff', 0, 0, 0, .5, .5, value) for value in samplers)
    data += struct.pack('<I', 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('anim.bin', b'ANIM')
        archive.writestr('build.bin', data)
        for i in range(pages):
            # One real 1x1 RGBA mip, rather than a magic-only texture stub.
            texture = struct.pack('<4sIHHHI', b'KTEX', (4 << 4) | (1 << 13), 1, 1, 4, 4)
            archive.writestr(f'atlas-{i}.tex', texture + bytes((255, 255, 255, 255)))


class AnimationAtlasTests(unittest.TestCase):
    def test_single_and_two_page_builds(self):
        with tempfile.TemporaryDirectory() as tmp:
            for pages in (1, 2):
                path = Path(tmp) / f'valid-{pages}.zip'
                fixture(path, pages, list(range(pages)))
                result = validate_animation_archive(path)
                self.assertEqual(result['atlas_count'], pages)
                self.assertEqual(result['vertex_count'], pages)

    def test_unsupported_page_reproduces_regression(self):
        with tempfile.TemporaryDirectory() as tmp:
            for pages in (3, 4):
                path = Path(tmp) / f'unsafe-{pages}.zip'
                fixture(path, pages, [0, pages-1])
                with self.assertRaisesRegex(AnimationAtlasError, 'atlas pages exceed the supported 2'):
                    validate_animation_archive(path)

    def test_invalid_vertex_sampler(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad-sampler.zip'
            for sampler in (-1, .5, 2, float('nan'), float('inf')):
                fixture(path, 2, [0, sampler])
                with self.assertRaisesRegex(AnimationAtlasError, 'outside declared integer pages'):
                    validate_animation_archive(path)

    def test_native_build_reuse_needs_no_local_textures(self):
        path = ROOT / 'mod/anim/nw_electric_arc.zip'
        self.assertTrue(validate_animation_archive(path)['animation_only'])
        self.assertEqual(validate_animation_archive(ROOT / 'mod/anim/nw_objects.zip')['atlas_count'], 1)

    def test_invalid_texture_header_or_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad-texture.zip'
            for mutation, message in ((lambda data: b'bad!' + data[4:], 'invalid KTEX header'),
                                      (lambda data: data[:-1], 'payload length mismatch'),
                                      (lambda data: data[:12], 'truncated KTEX mip table')):
                fixture(path, 1, [0])
                with zipfile.ZipFile(path) as archive:
                    entries = {name: archive.read(name) for name in archive.namelist()}
                entries['atlas-0.tex'] = mutation(entries['atlas-0.tex'])
                with zipfile.ZipFile(path, 'w') as archive:
                    for name, data in entries.items():
                        archive.writestr(name, data)
                with self.assertRaisesRegex(AnimationAtlasError, message):
                    validate_animation_archive(path)

    def test_preserved_broken_field_package(self):
        path = ROOT / 'test_reports/nw_field_stages_unsafe_four_pages.zip'
        if not path.exists():
            self.skipTest('local reproduction artifact is not part of the source distribution')
        with self.assertRaisesRegex(AnimationAtlasError, '4 atlas pages exceed'):
            validate_animation_archive(path)

    def test_install_rejects_before_writing_owned_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            workspace = Path(tmp) / 'workspace'
            scripts = workspace / 'tools'
            scripts.mkdir(parents=True)
            for name in ('install_mod.py', 'animation_atlas.py'):
                shutil.copy2(ROOT / 'tools' / name, scripts / name)
            fixture(workspace / 'mod/anim/unsafe.zip', 4, [2])
            (workspace / 'mod/modinfo.lua').write_text('version = "new"')
            game = Path(tmp) / 'game'
            installed = game / 'mods/nw_weave_dev'
            installed.mkdir(parents=True)
            (installed / '.nw_workspace').write_text(str(workspace.resolve()))
            (installed / 'modinfo.lua').write_text('keep existing installation')
            result = subprocess.run([sys.executable, str(scripts / 'install_mod.py'), '--game', str(game)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('4 atlas pages exceed', result.stderr)
            self.assertEqual((installed / 'modinfo.lua').read_text(), 'keep existing installation')
            self.assertFalse((installed / 'anim').exists())


if __name__ == '__main__':
    unittest.main()
