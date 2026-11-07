"""Check the elemental atlas contract and preserve animation pivots."""
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_elemental_flight as elemental


class ElementalAssetTests(unittest.TestCase):
    def test_changing_silhouette_keeps_pivot_and_scale(self):
        poses = []
        for offset in (10, 70):
            image = Image.new("RGBA", (100, 100))
            draw = ImageDraw.Draw(image)
            draw.rectangle((offset, 38, offset + 16, 61), fill=(30, 80, 220, 255))
            draw.rectangle((48, 48, 51, 51), fill=(255, 255, 255, 255))
            poses.append(image)
        normalized, _ = elemental.normalize_group(poses, 96)
        marker_centres, blue_centres = [], []
        for image in normalized:
            white = [(x, y) for y in range(image.height) for x in range(image.width)
                     if all(c > 215 for c in image.getpixel((x, y)))]
            blue = [(x, y) for y in range(image.height) for x in range(image.width)
                    if (lambda c: c[0] < 70 and 50 < c[1] < 130 and c[2] > 180 and c[3] > 200)(image.getpixel((x, y)))]
            self.assertTrue(white)
            self.assertTrue(blue)
            marker_centres.append(tuple(sum(p[i] for p in white) / len(white) for i in (0, 1)))
            blue_centres.append(sum(p[0] for p in blue) / len(blue))
        self.assertEqual(marker_centres[0], marker_centres[1])
        self.assertGreater(blue_centres[1] - blue_centres[0], 40,
                           "Moving artwork must not be recentered by per-frame cropping")

    def test_authored_pivot_is_not_the_grid_centre(self):
        image = Image.new("RGBA", (100, 100))
        draw = ImageDraw.Draw(image)
        draw.rectangle((48, 73, 51, 76), fill=(255, 255, 255, 255))
        draw.rectangle((20, 65, 35, 80), fill=(20, 40, 80, 255))
        normalized, _ = elemental.normalize_group([image], 96, (.5, .75))
        white = [(x, y) for y in range(96) for x in range(96)
                 if all(c > 215 for c in normalized[0].getpixel((x, y)))]
        self.assertTrue(white)
        self.assertAlmostEqual(sum(p[0] for p in white) / len(white), 47.5, delta=1)
        self.assertAlmostEqual(sum(p[1] for p in white) / len(white), 47.5, delta=1)

    def test_complete_directional_bank_and_rotated_bounds(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            elemental_source, basic_source, special_source = (
                source / name for name in ("elemental", "basic", "special"))
            for folder in (elemental_source, basic_source, special_source):
                folder.mkdir()
            expected_sources = {}
            for element in elemental.DISPLAY_SIZES:
                if element in ("fire", "frost"):
                    folder = elemental_source
                elif element in ("arrow", "heavy", "scatter"):
                    folder = basic_source
                else:
                    folder = special_source
                atlas = Image.new("RGBA", (300, 400))
                draw = ImageDraw.Draw(atlas)
                for index in range(12):
                    x, y = (index % 3) * 100 + 50, (index // 3) * 100 + 50
                    draw.rectangle((x - 20, y - 15, x + 20, y + 15), fill=(255, 150, 50, 255))
                path = folder / f"{element}-atlas.png"
                atlas.save(path)
                if element in elemental.HEAD_OVERRIDES:
                    atlas.save(folder / elemental.HEAD_OVERRIDES[element]["file"])
                expected_sources[element] = str(path)
            build, animations, images, manifest = elemental.make_bank(
                elemental_source, basic_source, special_source)
            self.assertEqual(len(animations), 2784)
            self.assertEqual(len(build), 19 * 3 * 6 + 6)
            self.assertEqual(len(images), 348)
            clips = {clip.get("name"): clip for clip in animations}
            for element in elemental.DISPLAY_SIZES:
                self.assertEqual(manifest["sources"][element]["path"], expected_sources[element])
                for group in ("head", "tail", "hit"):
                    for direction in range(elemental.directions_for(element)):
                        name = elemental.clip_name(element, group, direction)
                        clip = clips[name]
                        self.assertEqual(clip.get("framerate"), "30")
                        expected_frames = 12 if element == "tri_electric" and group == "head" else 6
                        self.assertEqual(len(clip), expected_frames)
                        self.assertEqual(manifest["sources"][element]["groups"][group]["frames"], expected_frames)
                        self.assertEqual(manifest["sources"][element]["groups"][group]["period"], expected_frames / 30)
                        for pose in clip:
                            part = pose[0]
                            image = images[part.get("name")]
                            a, b, c, d = (float(part.get("m_" + key)) for key in "abcd")
                            for x in (-image.width / 2, image.width / 2):
                                for y in (-image.height / 2, image.height / 2):
                                    self.assertLessEqual(abs(a * x + c * y), float(pose.get("w")) / 2)
                                    self.assertLessEqual(abs(b * x + d * y), float(pose.get("h")) / 2)
                    if group != "head":
                        self.assertGreater(images[f"{element}_{group}_0"].getchannel("A").getextrema()[1],
                                           images[f"{element}_{group}_5"].getchannel("A").getextrema()[1])
            elemental.prepare(build, animations, images, manifest, source / "prepared")
            self.assertTrue((source / "prepared/animation.xml").exists())
            self.assertTrue((source / "prepared/manifest.json").exists())

    @unittest.skipUnless(all((elemental.source_folder(name)
                             / f"{name}-atlas.png").exists() for name in elemental.DISPLAY_SIZES),
                         "Generated atlases are not present yet")
    def test_project_atlases_have_transparent_complete_frames(self):
        _, animations, images, _ = elemental.make_bank()
        self.assertEqual(len(animations), 2784)
        for name, image in images.items():
            alpha = image.getchannel("A")
            self.assertEqual(alpha.getextrema()[0], 0, name)
            self.assertGreater(alpha.getextrema()[1], 20, name)
            bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
            self.assertTrue(bbox, name)
            self.assertGreater(bbox[0], 0, name)
            self.assertGreater(bbox[1], 0, name)
            self.assertLess(bbox[2], image.width, name)
            self.assertLess(bbox[3], image.height, name)


if __name__ == "__main__":
    unittest.main()
