"""Check the shipped head's actual animated geometry and painted silhouette."""
import sys
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from native_animation import NativeAnimation, read_animation, read_build, texture


class BeamHeadAssets(unittest.TestCase):
    def test_rotating_head_breathes_without_exceeding_beam_diameter(self):
        material = NativeAnimation.__new__(NativeAnimation)
        with zipfile.ZipFile(ROOT / "mod/anim/nw_end_beam.zip") as archive:
            material.clips = read_animation(archive.read("anim.bin"))
            material.build = read_build(archive.read("build.bin"))
            material.atlases = [texture(archive.read(p)) for p in material.build["atlases"]]
        material.cache = {}
        poses = material.clip("head")["frames"]
        heights, turns = [], []
        # Authored white-core location within the original 369x252 cutout,
        # mapped into the shipped 132x90 symbol (not the visual bbox centre).
        px, py = (506-329)*132/369-66, (489-354)*90/252-45
        for index, pose in enumerate(poses):
            image, _ = material.render_frame("head", index)
            box = image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
            heights.append(box[3]-box[1])
            _, _, _, a, b, c, d, tx, ty, _ = pose["elements"][0]
            turns.append(b)
            self.assertAlmostEqual(a*px+c*py+tx, 0, places=4)
            self.assertAlmostEqual(b*px+d*py+ty, 0, places=4)
        self.assertLessEqual(max(heights), 91, "rotation must not widen the head beyond the 90-unit beam diameter")
        self.assertLess(min(heights), .86*max(heights), "the breathing movement must survive compilation")
        self.assertGreater(max(turns), .2)
        self.assertLess(min(turns), -.2)


if __name__ == "__main__":
    unittest.main()
