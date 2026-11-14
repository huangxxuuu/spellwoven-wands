"""Check the rolling cloud's visual contract against production source/art."""
from pathlib import Path
import sys
from lupa.lua51 import LuaRuntime
import unittest
import zipfile

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from animation_atlas import validate_animation_archive
from build_field_stages import build_bank
from native_animation import GAME, read_animation, read_build
from storm_stage_art import pose, STRIKE_PIXELS, local_light, PERIOD

BODIES = {"storm_back", "storm_crown", "storm_left", "storm_right"}


def body_layers(layers):
    return [part for part in layers if part is not None and part[0] in BODIES]


def live_names():
    return ["storm_cloud_"+phase+("" if variant==1 else "_"+str(variant))
            for variant in (1, 2, 3) for phase in ("idle", "warning", "pulse")]


def rendered_parts(bank, parts, size=(380, 240), origin=(190, 460)):
    image = Image.new("RGBA", size)
    for part in parts:
        source = bank.images[f"{part.get('name')}_{part.get('frame')}"]
        a, b, c, d, x, y = [float(part.get("m_"+k)) for k in ("a", "b", "c", "d", "tx", "ty")]
        x += origin[0]
        y += origin[1]
        det = a*d-b*c
        transform = (d/det, -c/det, (-d*x+c*y)/det+source.width/2,
                     -b/det, a/det, (b*x-a*y)/det+source.height/2)
        image.alpha_composite(source.transform(size, Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC))
    return image


@unittest.skipUnless((GAME / "data/anim/shock_fx.zip").exists(), "Native DST artwork is required")
class StormAnimationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bank = build_bank()
        cls.clips = {clip.get("name"): clip for clip in cls.bank.animations}

    def test_body_pose_matches_across_gameplay_boundaries(self):
        # Real .8 / 1.6 / 2.4 strikes and the 2.55 expiry, plus loop wrap.
        for left, lt, right, rt in (("spawn", 1, "warning", 0),
                                   ("warning", 1, "pulse", 0),
                                   ("pulse", 1, "idle", 0),
                                   ("idle", .3/.8, "warning", 0),
                                   ("pulse", .15/.2, "end", 0),
                                   ("idle", 1, "idle", 0)):
            for variant in (1, 2, 3):
                before = body_layers(pose(self.bank, left, lt, variant=variant))
                after = body_layers(pose(self.bank, right, rt, variant=variant))
                self.assertEqual(len(before), len(after))
                for a, b in zip(before, after):
                    self.assertEqual(a[0], b[0])
                    for va, vb in zip(a[1:], b[1:]):
                        self.assertAlmostEqual(va, vb, places=6, msg=f"{left} -> {right}")
        for variant in (1, 2):
            self.assertEqual(body_layers(pose(self.bank, "warning", 0, variant=variant)),
                             body_layers(pose(self.bank, "warning", 0, variant=variant+1)),
                             "changing the discharge route must not reset the cloud pose")

    def test_all_live_clips_roll_and_cover_the_attack_origin(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + lua.globals().package.path
        runtime_origin = lua.eval('require("nw/field_stages").storm_strike_pixels')
        self.assertEqual(runtime_origin, STRIKE_PIXELS, "cloud art and attack endpoint heights drifted")
        for name in live_names():
            clip = self.clips[name]
            transforms = []
            for frame in clip:
                bodies = [part for part in frame if part.get("name") in BODIES]
                transforms.append(tuple((p.get("m_tx"), p.get("m_ty")) for p in bodies))
                # The runtime origin in cloud coordinates: no visible free-
                # floating attack endpoint, even as the foreground rolls.
                image = rendered_parts(self.bank, bodies)
                alpha = image.getchannel("A")
                self.assertGreaterEqual(min(alpha.getpixel((x, y))
                                            for x in range(187, 194)
                                            for y in range(460-runtime_origin-3, 460-runtime_origin+4)), 245)
            self.assertEqual(len(set(transforms)), len(transforms), name+" freezes between frames")

    def test_lightning_has_both_foreground_occlusion_and_visible_flicker(self):
        fractions = []
        for name in live_names():
            for frame in self.clips[name]:
                for i, part in enumerate(frame):
                    if not part.get("name").startswith("storm_inner_arc_"):
                        continue
                    arc = rendered_parts(self.bank, [part]).getchannel("A")
                    front = rendered_parts(self.bank, [p for p in frame[i+1:] if p.get("name") in BODIES]).getchannel("A")
                    total = sum(arc.getdata())
                    if total:
                        visible = sum(a*(1-f/255) for a, f in zip(arc.getdata(), front.getdata()))
                        fractions.append(visible/total)
        self.assertTrue(fractions)
        self.assertTrue(any(.01 < ratio < .95 for ratio in fractions), "internal arcs never peek through rolling cloud gaps")
        self.assertTrue(any(ratio < .1 for ratio in fractions), "cloud layers never hide the internal lightning")

    def test_light_travels_between_cloud_cavities_and_repeats_without_a_jump(self):
        # Fixed spatial probes isolate light movement from the moving artwork.
        # Uniformly scaling the whole cloud's brightness cannot pass this.
        probes = ((-55, -350), (0, -375), (55, -350))
        signatures = []
        for variant in (1, 2, 3):
            proportions = []
            signature = []
            for index in range(24):
                clock = index/30
                levels = [local_light(clock, x, y, variant) for x, y in probes]
                signature.extend(round(value, 5) for value in levels)
                for (x, y), value in zip(probes, levels):
                    self.assertAlmostEqual(value, local_light(clock+PERIOD, x, y, variant), places=6)
                total = sum(levels)
                if total > .2:
                    proportions.append([value/total for value in levels])
            self.assertTrue(proportions)
            self.assertGreater(max(max(p[i] for p in proportions)-min(p[i] for p in proportions)
                                   for i in range(3)), .2,
                               "the internal light only strobes uniformly instead of crossing cavities")
            signatures.append(tuple(signature))
        self.assertEqual(len(set(signatures)), 3, "all three discharges reuse the same light route")

    def test_painted_transmission_is_visible_and_returns_to_dark(self):
        # Measure the final composited light, including the foreground's actual
        # occlusion, rather than accepting lights hidden behind opaque bodies.
        signatures = []
        for variant in (1, 2, 3):
            suffix = "" if variant==1 else "_"+str(variant)
            energies = []
            signature = []
            for phase in ("warning", "pulse", "idle"):
                for frame in self.clips["storm_cloud_"+phase+suffix]:
                    painted = rendered_parts(self.bank, [p for p in frame
                        if not p.get("name").startswith("storm_inner_arc_")]).convert("RGB")
                    dark = rendered_parts(self.bank, [p for p in frame if p.get("name") in BODIES]).convert("RGB")
                    difference = ImageChops.subtract(painted, dark).convert("L")
                    energy = sum(value*count for value, count in enumerate(difference.histogram()))
                    energies.append(energy)
                    # Coarse light maps retain spatial differences while being
                    # insensitive to tiny antialiasing changes at ink edges.
                    signature.append(difference.resize((19, 12), Image.Resampling.BOX).tobytes())
            self.assertGreater(max(energies), 10000, "painted internal transmission is not visible")
            self.assertLess(min(energies), max(energies)*.05, "cloud never recovers its dark silhouette")
            signatures.append(tuple(signature))
        self.assertEqual(len(set(signatures)), 3, "three runtime variants render identical illumination")

    def test_compiled_bank_preserves_cloud_layers_and_shader_atlas_limit(self):
        path = ROOT / "mod/anim/nw_field_stages.zip"
        info = validate_animation_archive(path)
        self.assertLessEqual(info["atlas_count"], 2)
        with zipfile.ZipFile(path) as archive:
            build = read_build(archive.read("build.bin"))
            clips = {c["name"]: c for c in read_animation(archive.read("anim.bin"))}
        for name in ["storm_cloud_spawn", "storm_cloud_end"]+live_names():
            self.assertEqual(len(self.clips[name]), len(clips[name]["frames"]))
            for source, compiled in zip(self.clips[name], clips[name]["frames"]):
                expected = [part.get("name") for part in source]
                ordered = sorted(compiled["elements"], key=lambda p: p[-1], reverse=True)
                self.assertEqual(expected, [build["names"][part[0]] for part in ordered],
                                 "compiler reordered repeated cloud symbols or internal lightning")
                for part, native in zip(source, ordered):
                    for attribute, value in zip(("a", "b", "c", "d", "tx", "ty"), native[3:9]):
                        self.assertAlmostEqual(float(part.get("m_"+attribute)), value, delta=.0001)


if __name__ == "__main__":
    unittest.main()
