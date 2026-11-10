"""Check the compiled furnace effect, including projection-space continuity."""
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import sys
import unittest

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from animation_atlas import validate_animation_archive
from preview_furnace_wave import FurnaceWave


class FurnaceWaveArtTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.archive = ROOT / "mod/anim/nw_furnace_wave.zip"
        cls.animation = FurnaceWave(cls.archive)
        cls.manifest = json.loads((ROOT / "assets_src/disassembler_wave_v2_complete_20261110/manifest.json").read_text(encoding="utf8"))

    @classmethod
    @lru_cache(maxsize=20)
    def canvas(cls, clip, frame):
        image, offset = cls.animation.render_frame(clip, frame)
        canvas = Image.new("RGBA", (1400, 1400))
        canvas.alpha_composite(image, (round(700 + offset[0]), round(700 + offset[1])))
        return np.array(canvas)

    @classmethod
    def radius(cls, clip, frame):
        alpha = cls.canvas(clip, frame)[:, :, 3]
        yy, xx = np.nonzero(alpha >= 32)
        return float(np.hypot(xx - 700, yy - 700).max()) if len(xx) else 0

    def test_selected_painting_and_supported_atlases(self):
        source = ROOT / self.manifest["source"]
        self.assertEqual(self.manifest["selected_candidate"], 2)
        self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), self.manifest["source_sha256"])
        self.assertLessEqual(validate_animation_archive(self.archive)["atlas_count"], 2)
        self.assertEqual(hashlib.sha256(self.archive.read_bytes()).hexdigest(), self.manifest["archive_sha256"])

    def test_growth_footprint_and_empty_endpoints(self):
        self.assertEqual(self.radius("grow", 0), 0)
        radii = [self.radius("grow", index) for index in (15, 30, 45, 59)]
        self.assertEqual(radii, sorted(radii))
        self.assertGreater(radii[-1], 560)
        self.assertLess(radii[-1], 610)
        self.assertEqual(self.radius("release", 17), 0)

    def test_grow_loop_release_share_registered_pose(self):
        base = self.canvas("loop", 0).astype(float)
        for clip, frame in (("grow", 59), ("release", 0)):
            other = self.canvas(clip, frame).astype(float)
            # The same painted pieces are registered identically at seams;
            # decoder subpixel rounding may differ by a few edge samples.
            self.assertLess(np.abs(base - other).mean(), .6, (clip, frame))

    def test_loop_changes_locally_without_expanding_boundary(self):
        base = self.canvas("loop", 0)
        moved = self.canvas("loop", 15)
        self.assertGreater(np.abs(base.astype(float) - moved.astype(float)).mean(), .3)
        self.assertLess(abs(self.radius("loop", 15) - self.radius("loop", 0)), 25)

    def test_release_fades_in_place_instead_of_shrinking_radius(self):
        begin = self.radius("release", 0)
        middle = self.radius("release", 8)
        self.assertGreater(middle, begin * .9)
        self.assertLess(middle, begin * 1.05)
        self.assertLess(self.canvas("release", 8)[:, :, 3].sum(),
                        self.canvas("release", 0)[:, :, 3].sum() * .85)


if __name__ == "__main__":
    unittest.main()
