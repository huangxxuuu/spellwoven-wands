"""Exercise KTEX alpha conversion with known stored RGBA and BC3 pixels."""
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from native_animation import NativeAnimation, texture


def ktex(width, height, pixels, fmt=4):
    return (b'KTEX' + struct.pack('<I', (1 << 13) | (fmt << 4))
            + struct.pack('<HHHI', width, height, 0, len(pixels)) + pixels)


class TextureAlpha(unittest.TestCase):
    def test_default_preserves_stored_rgb_and_vertical_flip(self):
        data = ktex(1, 2, bytes((64, 32, 16, 128, 20, 40, 60, 255)))
        self.assertEqual(list(texture(data).getdata()),
                         [(20, 40, 60, 255), (64, 32, 16, 128)])
        self.assertEqual(list(texture(data, unpremultiply=True).getdata()),
                         [(20, 40, 60, 255), (127, 63, 31, 128)])

    def test_unpremultiply_composites_alpha_once(self):
        data = ktex(1, 1, bytes((128, 128, 128, 128)))
        background = Image.new('RGBA', (1, 1), (0, 0, 0, 255))
        self.assertEqual(Image.alpha_composite(background, texture(data)).getpixel((0, 0)),
                         (64, 64, 64, 255))
        self.assertEqual(Image.alpha_composite(
            background, texture(data, unpremultiply=True)).getpixel((0, 0)),
            (128, 128, 128, 255))

    def test_bc3_conversion_clamps_compression_error_and_handles_zero_alpha(self):
        # DXT5 block: alpha endpoints 128/0, pixel 1 selects alpha 0;
        # all RGB pixels select the white RGB565 endpoint. Compression can
        # produce RGB > alpha, so unpremultiplication must saturate safely.
        block = bytes((128, 0)) + (1 << 3).to_bytes(6, 'little')
        block += struct.pack('<HHI', 0xffff, 0, 0)
        data = ktex(4, 4, block, fmt=2)
        stored = texture(data)
        straight = texture(data, unpremultiply=True)
        self.assertEqual(stored.getpixel((0, 3)), (255, 255, 255, 128))
        self.assertEqual(straight.getpixel((0, 3)), (255, 255, 255, 128))
        self.assertEqual(straight.getpixel((1, 3))[3], 0)
        self.assertEqual(straight.getchannel('A').tobytes(), stored.getchannel('A').tobytes())

    def test_native_animation_forwards_explicit_option_without_changing_default(self):
        with tempfile.TemporaryDirectory() as folder:
            game = Path(folder)
            (game / 'data/anim').mkdir(parents=True)
            with zipfile.ZipFile(game / 'data/anim/sample.zip', 'w') as archive:
                archive.writestr('anim.bin', b'anim')
                archive.writestr('build.bin', b'build')
                archive.writestr('atlas.tex', ktex(1, 1, bytes((128, 128, 128, 128))))
            with patch('native_animation.read_animation', return_value=[]), patch(
                    'native_animation.read_build', return_value={'atlases': ['atlas.tex']}):
                default = NativeAnimation('sample', game=game)
                straight = NativeAnimation('sample', game=game, unpremultiply=True)
            self.assertEqual(default.atlases[0].getpixel((0, 0)), (128, 128, 128, 128))
            self.assertEqual(straight.atlases[0].getpixel((0, 0)), (255, 255, 255, 128))


if __name__ == '__main__':
    unittest.main()
