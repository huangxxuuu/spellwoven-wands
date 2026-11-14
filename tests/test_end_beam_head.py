"""Verify shipped head layering and the twelve actual painted star frames."""
import hashlib
import sys
import unittest
import zipfile
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from animation_atlas import validate_animation_archive
from native_animation import NativeAnimation, read_animation, read_build, texture
from build_end_beam import prepare_art
from build_end_beam_head import load_compiled


class EndBeamHead(unittest.TestCase):
    def test_twelve_independent_stars_and_four_synchronous_connector_clips(self):
        archive_path = ROOT / "mod/anim/nw_end_beam_head.zip"
        validate_animation_archive(archive_path)
        material = NativeAnimation.__new__(NativeAnimation)
        with zipfile.ZipFile(archive_path) as archive:
            material.clips = read_animation(archive.read("anim.bin"))
            material.build = read_build(archive.read("build.bin"))
            material.atlases = [texture(archive.read(p)) for p in material.build["atlases"]]
        material.cache = {}
        poses = material.clip("head")["frames"]
        self.assertEqual(len(poses), 12)
        star_matrices, star_symbols, star_pixels = set(), set(), set()
        for pose in poses:
            self.assertEqual(len(pose["elements"]), 1)
            star = pose["elements"][0]
            name = material.build["names"][star[0]]
            self.assertTrue(name.startswith("star_"))
            star_symbols.add(star[0])
            star_matrices.add(star[3:9])
            star_pixels.add(hashlib.sha256(material.symbol(star[0])[0].tobytes()).digest())
        self.assertEqual(len(star_symbols), 12)
        self.assertEqual(len(star_pixels), 12, "twelve paintings, not one sprite repeated")
        self.assertEqual(len(star_matrices), 1, "do not double the rotation already painted into the star poses")
        self.assertAlmostEqual(next(iter(star_matrices))[0],1.12,places=6)
        for piece in range(4):
            clip = material.clip(f"connector_{piece}")
            self.assertEqual(clip["fps"],30)
            self.assertEqual(len(clip["frames"]),16)
            for pose in clip["frames"]:
                self.assertEqual(len(pose["elements"]),1)
                self.assertEqual(pose["elements"][0][3:9],(1,0,0,1,0,0), "connector does not turn with the star")

    def test_registered_frames_do_not_capture_neighbouring_sheet_cells(self):
        folder = ROOT / "assets_src/art_v1/runtime/nw_end_beam_head"
        for index in range(12):
            image = Image.open(folder / f"star_{index}.png").convert("RGBA")
            bbox = image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
            self.assertIsNotNone(bbox)
            self.assertGreaterEqual(min(bbox[:2]), 6)
            self.assertLessEqual(max(bbox[2:]), 90)

    def test_all_64_entrances_match_beam_and_taper_stays_broad(self):
        band,_ = prepare_art()
        compiled_beam, compiled_head = load_compiled("nw_end_beam"),load_compiled("nw_end_beam_head")
        def height(image,x):
            ys=[y for y in range(image.height) if image.getpixel((x,y))[3]>128]
            return max(ys)-min(ys)+1
        for piece in range(4):
            for index in range(16):
                connector=Image.open(ROOT/f"assets_src/art_v1/runtime/nw_end_beam_head/connector_{piece}_{index}.png").convert("RGBA")
                beam=Image.open(ROOT/f"assets_src/art_v1/runtime/nw_end_beam/beam_{piece}_{index}.png").convert("RGBA")
                self.assertEqual(connector.crop((0,0,1,64)).tobytes(),beam.crop((167,0,168,64)).tobytes(),
                                 f"exact unshifted RGBA entrance: slice {piece}, frame {index}")
                shifted=ImageChops.offset(band,round(index*band.width/16),0)
                end_x=((piece+1)*168-1+round(79*168/300))%band.width
                ratio=height(connector,79)/height(shifted,end_x)
                self.assertGreaterEqual(ratio,.80)
                self.assertLessEqual(ratio,.90)
                white=[y for y in range(64) if min(connector.getpixel((79,y))[:3])>=210 and connector.getpixel((79,y))[3]>=192]
                self.assertLessEqual(abs((min(white)+max(white)+1)/2-32),1)
                # Separate BC3 atlas blocks may quantize edge colours slightly;
                # their opaque core and silhouette must still meet to one pixel.
                bi,_=compiled_beam.render_frame(f"beam_{piece}",index)
                ci,_=compiled_head.render_frame(f"connector_{piece}",index)
                def profile(im,x):
                    ys=[y for y in range(64) if im.getpixel((x,y))[3]>128]
                    core=[y for y in range(64) if min(im.getpixel((x,y))[:3])>=210 and im.getpixel((x,y))[3]>=192]
                    return min(ys),max(ys),(min(core)+max(core))/2
                for a,b in zip(profile(bi,bi.width-1),profile(ci,0)):
                    self.assertLessEqual(abs(a-b),1,f"compiled seam {piece}/{index}")


if __name__ == "__main__":
    unittest.main()
