"""Check painted-frame registration, hold timing, and compiled ground footprint."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build_furnace_wave import CLIPS, OUT, build_bank, timeline_mapping
from animation_atlas import validate_animation_archive
from preview_furnace_wave import FurnaceWave


class PaintedFramePipelineTest(unittest.TestCase):
    def test_cumulative_hold_timing(self):
        for count, ticks in CLIPS.values():
            mapping = timeline_mapping(count, ticks)
            self.assertEqual(len(mapping), ticks)
            self.assertEqual(set(mapping), set(range(count)))
            self.assertEqual(mapping, sorted(mapping))
            holds = [mapping.count(i) for i in range(count)]
            self.assertLessEqual(max(holds) - min(holds), 1)

    def test_registration_and_identity_elements(self):
        # Deliberately off-centre drawings detect accidental fit-to-pose crops.
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            (source / "frames").mkdir()
            for clip, (count, _) in CLIPS.items():
                for index in range(count):
                    image = Image.new("RGBA", (512, 512))
                    if (clip, index) not in (("grow", 0), ("release", 11)):
                        ImageDraw.Draw(image).rectangle((310, 200, 460, 330), fill=(190, 120, 240, 220))
                    image.save(source / "frames" / f"{clip}_{index:03}.png")
            bank = build_bank(source)
            manifest = bank.save_sources()
            self.assertEqual(len(manifest["sources"]), 60)
            self.assertEqual(len(bank.build.findall("Symbol/Frame")), 60)
            for row in manifest["sources"]:
                self.assertEqual(hashlib.sha256(Path(row["path"]).read_bytes()).hexdigest(), row["sha256"])
                if row["alpha_bounds"]:
                    self.assertGreater(row["geometry_center"][0], 300)
            for clip in bank.animations:
                self.assertEqual(len(clip), CLIPS[clip.attrib["name"]][1])
                for frame in clip:
                    self.assertEqual(len(frame), 1)
                    element = frame[0]
                    self.assertEqual([float(element.get(key)) for key in ("m_a", "m_b", "m_c", "m_d", "m_tx", "m_ty")],
                                     [1, 0, 0, 1, 0, 0])
            endpoint = source / "frames/grow_000.png"
            Image.new("RGBA", (512, 512), (0, 0, 0, 255)).save(endpoint)
            with self.assertRaisesRegex(ValueError, "endpoint must be fully transparent"):
                build_bank(source)


class FurnaceWaveArtTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        manifest_path = OUT / "manifest.json"
        if not manifest_path.exists():
            raise unittest.SkipTest("60 painted source frames have not been delivered and compiled yet")
        cls.manifest = json.loads(manifest_path.read_text(encoding="utf8"))
        if "archive_sha256" not in cls.manifest:
            raise unittest.SkipTest("painted sources have not been compiled yet")
        cls.archive = ROOT / "mod/anim/nw_furnace_wave.zip"
        cls.animation = FurnaceWave(cls.archive)

    @classmethod
    def radius(cls, clip, frame):
        image, offset = cls.animation.render_frame(clip, frame)
        yy, xx = np.nonzero(np.array(image.getchannel("A")) >= 32)
        return float(np.hypot(xx + offset[0], yy + offset[1]).max()) if len(xx) else 0

    def test_sources_and_supported_atlases(self):
        self.assertEqual(len(self.manifest["sources"]), 60)
        self.assertEqual([sum(row["clip"] == name for row in self.manifest["sources"]) for name in CLIPS], [24, 24, 12])
        for row in self.manifest["sources"]:
            self.assertEqual(hashlib.sha256(Path(row["path"]).read_bytes()).hexdigest(), row["sha256"])
        self.assertLessEqual(validate_animation_archive(self.archive, max_pages=2)["atlas_count"], 2)
        self.assertEqual(hashlib.sha256(self.archive.read_bytes()).hexdigest(), self.manifest["archive_sha256"])

    def test_empty_endpoints_and_gameplay_radius(self):
        for clip, index in (("grow", 0), ("release", 17)):
            image, _ = self.animation.render_frame(clip, index)
            self.assertIsNone(image.getchannel("A").getbbox())
        # Approximately four world units (150 animation units each), allowing
        # hand-painted irregular edges. Geometry calibration remains explicit.
        radii = [self.radius("loop", index) for index in range(60)]
        self.assertGreater(min(radii), 540)
        self.assertLess(max(radii), 660)

    def test_compiled_timing_and_no_dynamic_transform(self):
        for clip in self.animation.clips:
            name = clip["name"]
            self.assertEqual((clip["fps"], len(clip["frames"])), (30, CLIPS[name][1]))
            expected = self.manifest["clips"][name]["timeline_to_build"]
            for tick, frame in enumerate(clip["frames"]):
                self.assertEqual(len(frame["elements"]), 1)
                element = frame["elements"][0]
                self.assertEqual(element[1], expected[tick])
                self.assertEqual(element[3:9], (1, 0, 0, 1, 0, 0))


if __name__ == "__main__":
    unittest.main()
