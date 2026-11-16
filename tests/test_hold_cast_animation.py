"""Check the shipped player pose binary; no rendering or mirrored art fixture."""
import io
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from native_animation import NativeAnimation, read_animation

GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


def engine_hash(name):
    value = 0
    for character in name.lower():
        value = (value * 65599 + ord(character)) & 0xFFFFFFFF
    return value


def tail_dictionary(data, clips):
    # ANIM v4 uses length-prefixed names, 13-byte clip headers, 24-byte
    # frame headers and 40-byte elements; the name dictionary follows them.
    offset = 24
    for clip in clips:
        offset += 4 + len(clip["name"].encode("utf8")) + 13
        for frame in clip["frames"]:
            offset += 24 + 4 * len(frame["events"]) + 40 * len(frame["elements"])
    reader = io.BytesIO(data[offset:])

    def integer():
        return struct.unpack("<I", reader.read(4))[0]

    names = {}
    for _ in range(integer()):
        key = integer()
        name = reader.read(integer()).decode("utf8")
        if key in names:
            raise AssertionError(f"duplicate hash dictionary entry: {key}")
        names[key] = name
    if reader.read():
        raise AssertionError("unparsed bytes after the animation hash dictionary")
    return names


class HoldCastAnimationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with ZipFile(ROOT / "mod/anim/nw_hold_cast.zip") as archive:
            cls.files = archive.namelist()
            cls.data = archive.read("anim.bin")
        cls.clips = read_animation(cls.data)
        cls.names = tail_dictionary(cls.data, cls.clips)
        cls.by_key = {(clip["name"], clip["facing"]): clip for clip in cls.clips}

    def native_idle(self, facing):
        source = GAME / "data/anim/player_idles.zip"
        if not source.exists():
            self.skipTest("Set DST_GAME to an installed DST directory for native idle comparison")
        if not hasattr(self.__class__, "idles"):
            with ZipFile(source) as archive:
                clips = read_animation(archive.read("anim.bin"))
            self.__class__.idles = {c["facing"]: c["frames"][0]
                                   for c in clips if c["name"] == "idle_loop"}
        return self.idles[facing]

    def native_stance(self, facing):
        source = GAME / "data/anim/player_parryblock.zip"
        if not source.exists():
            self.skipTest("Native bent-leg comparison requires an installed DST directory")
        if not hasattr(self.__class__, "stances"):
            with ZipFile(source) as archive:
                clips = read_animation(archive.read("anim.bin"))
            self.__class__.stances = {c["facing"]: c["frames"][0]
                                     for c in clips if c["name"] == "parry_loop"}
        return self.stances[facing]

    def hold_clips(self, facing):
        return [self.clip(phase, facing) for phase in
                ("loop", *(f"recoil_{i:02d}" for i in range(1, 13)))]

    def elements(self, frame, symbol):
        return [e for e in frame["elements"] if e[0] == engine_hash(symbol)]

    @staticmethod
    def object_local(element, point):
        a, b, c, d, x, y = element[3:9]
        px, py = point[0] - x, point[1] - y
        determinant = a*d - b*c
        return ((d*px - c*py)/determinant, (a*py - b*px)/determinant)

    def clip(self, phase, facing):
        return self.by_key[("nw_hold_cast_" + phase, facing)]

    def test_transform_only_archive_has_consistent_runtime_counts(self):
        self.assertEqual(self.files, ["anim.bin"], "player skins and equipped wand must supply textures")
        self.assertEqual(self.data[:4], b"ANIM")
        version, elements, frames, events, count = struct.unpack_from("<IIIII", self.data, 4)
        all_frames = [frame for clip in self.clips for frame in clip["frames"]]
        self.assertEqual(version, 4)
        self.assertEqual(count, 45)
        self.assertEqual(count, len(self.clips))
        self.assertEqual(frames, len(all_frames))
        self.assertEqual(elements, sum(len(frame["elements"]) for frame in all_frames))
        self.assertEqual(events, 0)
        self.assertTrue(all(not frame["events"] for frame in all_frames), "pose must not carry native attack events")
        expected = {("nw_hold_cast_" + phase, facing)
                    for phase in ("pre", "loop", "pst", *(f"recoil_{i:02d}" for i in range(1, 13)))
                    for facing in (2, 5, 8)}
        self.assertEqual(len(self.by_key), len(self.clips), "duplicate animation/facing pair")
        self.assertEqual(set(self.by_key), expected)
        for clip in self.clips:
            with self.subTest(clip=clip["name"], facing=clip["facing"]):
                self.assertEqual(clip["root"], engine_hash("wilson"))
                self.assertEqual(clip["fps"], 30)
                self.assertEqual(len(clip["frames"]),
                                 11 if clip["name"].endswith(("_pre", "_pst")) else 36)
                self.assertTrue(all(frame["elements"] for frame in clip["frames"]))

    def test_pose_boundaries_join_without_a_transform_jump(self):
        for facing in (2, 5, 8):
            with self.subTest(facing=facing):
                pre = self.clip("pre", facing)["frames"]
                loop = self.clip("loop", facing)["frames"]
                post = self.clip("pst", facing)["frames"]
                self.assertEqual(pre[-1], loop[0])
                self.assertEqual(post[0], loop[0])
                self.assertEqual(post[-1], pre[0])
                self.assertEqual(post, pre[::-1], "retract must exactly retrace the extension")
                self.assertNotEqual(pre[0]["elements"], loop[0]["elements"], "extend must not be a frozen hold")

    def test_symbol_and_layer_names_remain_resolvable_for_character_builds(self):
        for key, name in self.names.items():
            self.assertEqual(key, engine_hash(name), name)
        self.assertEqual(self.names[engine_hash("wilson")], "wilson")
        for clip in self.clips:
            for frame in clip["frames"]:
                for symbol, index, layer, *transform in frame["elements"]:
                    self.assertIn(symbol, self.names, "unresolvable symbol would prevent skin lookup")
                    self.assertIn(layer, self.names, "unresolvable layer would prevent symbol overrides")
                    self.assertTrue(all(math.isfinite(value) for value in transform))
                    a, b, c, d = transform[:4]
                    self.assertGreater(abs(a*d - b*c), 1e-6,
                                       "collapsed affine geometry cannot carry native art")
                self.assertIn(engine_hash("swap_object"), {element[0] for element in frame["elements"]},
                              "equipped wand must remain a replaceable symbol")

    def test_side_hold_points_the_wand_forward_near_horizontal(self):
        elements = self.clip("loop", 5)["frames"][0]["elements"]
        swap = [element for element in elements if element[0] == engine_hash("swap_object")]
        self.assertEqual(len(swap), 1)
        _, _, _, a, b, c, d, tx, ty, depth = swap[0]
        # The native held object extends along its local -Y axis. Its world
        # direction is (-c, -d); facing 5 is the source side-facing pose.
        self.assertGreater(abs(c), .5, "held object axis collapsed")
        self.assertGreater(-d, 0, "side hold should point slightly down in screen coordinates")
        self.assertLess(abs(d), abs(c) * .15, "held object is no longer nearly horizontal")
        self.assertGreater(-c, 0, "held object points behind the side-facing player")

    def test_native_idle_character_and_skin_layers_are_preserved(self):
        for facing in (2, 5, 8):
            original = self.native_idle(facing)["elements"]
            for clip in (c for c in self.clips if c["facing"] == facing):
                for frame in clip["frames"]:
                    with self.subTest(facing=facing, clip=clip["name"]):
                        # Preserve every symbol and alternate skin layer; the
                        # new arm/staff order must be reflected in the binary.
                        self.assertEqual(Counter((e[0], e[2]) for e in frame["elements"]),
                                         Counter((e[0], e[2]) for e in original))
                        depths = [e[9] for e in frame["elements"]]
                        self.assertEqual(depths, sorted(depths), "native frame draw order must match depths")
                        replaceable = {engine_hash("hand"), engine_hash("leg")}
                        self.assertEqual(Counter(e[:3] for e in frame["elements"] if e[0] not in replaceable),
                                         Counter(e[:3] for e in original if e[0] not in replaceable))
            self.assertEqual(self.clip("pre", facing)["frames"][0]["elements"], original,
                             "entry must begin in the native idle silhouette")
            stance_legs = self.elements(self.native_stance(facing), "leg")
            if facing == 2:
                idle_legs = self.elements(self.native_idle(facing), "leg")
                native_legs = Counter((idle_legs[0][:3],
                                       (idle_legs[1][0], stance_legs[1][1], idle_legs[1][2])))
            else:
                native_legs = Counter(e[:3] for e in stance_legs)
            for clip in self.hold_clips(facing):
                for frame in clip["frames"]:
                    self.assertEqual(Counter(e[:3] for e in self.elements(frame, "leg")), native_legs,
                                     "stance must retain native leg cels, with one straight support leg in back view")

    def test_back_arms_stay_behind_the_body_and_elbow_points_down(self):
        arm_names = {engine_hash(name) for name in
                     ("arm_upper", "arm_upper_skin", "arm_lower", "arm_lower_cuff", "hand")}
        for clip in self.hold_clips(2):
            for index, frame in enumerate(clip["frames"]):
                with self.subTest(clip=clip["name"], frame=index):
                    cover = [e for name in ("headbase", "torso", "torso_pelvis", "SWAP_BODY", "SWAP_BODY_TALL", "skirt")
                             for e in self.elements(frame, name)]
                    arms = [e for e in frame["elements"] if e[0] in arm_names
                            and e[2] != engine_hash("ARM_normal")]
                    self.assertTrue(arms)
                    for arm in arms:
                        self.assertGreater(arm[9], max(e[9] for e in cover),
                                           "every arm/skin copy must be covered by the back and head")
                        self.assertGreater(frame["elements"].index(arm),
                                           max(frame["elements"].index(e) for e in cover))
                    # ARM_carry contains duplicate upper arms in the native
                    # back bank; check their elbow against the shoulder, too.
                    uppers = [e for e in self.elements(frame, "arm_upper") if e[2] == engine_hash("ARM_carry")]
                    lower, = [e for e in self.elements(frame, "arm_lower") if e[2] == engine_hash("ARM_carry")]
                    self.assertGreaterEqual(len(uppers), 2, "native duplicate carry upper arms must survive")
                    self.assertGreater(lower[8], min(e[8] for e in uppers) + 2,
                                       "near elbow must bend down instead of jutting into the nape")
                    native_feet = self.elements(self.native_idle(2), "foot")
                    feet = self.elements(frame, "foot")
                    native_width = abs(native_feet[1][7] - native_feet[0][7])
                    self.assertLessEqual(abs(feet[1][7] - feet[0][7]), native_width + 12,
                                         "back stance must not bow both legs far out to the sides")

    def test_feet_open_on_entry_then_remain_planted_through_every_hold_phase(self):
        for facing in (2, 5, 8):
            feet = self.elements(self.native_idle(facing), "foot")
            self.assertEqual(len(feet), 2)
            planted = self.elements(self.clip("loop", facing)["frames"][0], "foot")
            self.assertEqual(self.elements(self.clip("pre", facing)["frames"][0], "foot"), feet)
            self.assertEqual(self.elements(self.clip("pst", facing)["frames"][-1], "foot"), feet)
            for clip in (c for c in self.clips if c["facing"] == facing):
                for index, frame in enumerate(clip["frames"]):
                    with self.subTest(facing=facing, clip=clip["name"], frame=index):
                        actual = self.elements(frame, "foot")
                        for foot, native in zip(actual, feet):
                            self.assertEqual(foot[:7], native[:7])
                            self.assertEqual(foot[8:], native[8:], "feet must stay on the original ground")
                            self.assertLessEqual(abs(foot[7] - native[7]), 16,
                                                 "entry may only open the stance a little")
                        if clip in self.hold_clips(facing):
                            self.assertEqual(actual, planted, "breathing/recoil must not slide either foot")

    def test_body_braces_and_keeps_breathing_even_at_maximum_recoil(self):
        for facing in (2, 5, 8):
            original = self.native_idle(facing)
            native_torso, = self.elements(original, "torso")
            for clip in self.hold_clips(facing):
                with self.subTest(facing=facing, clip=clip["name"]):
                    torso = [self.elements(f, "torso")[0] for f in clip["frames"]]
                    self.assertGreater(min(e[8] - native_torso[8] for e in torso), 6,
                                       "hold must visibly lower the hips into a braced stance")
                    self.assertLess(max(e[8] - native_torso[8] for e in torso), 24)
                    self.assertLessEqual(max(abs(e[7] - native_torso[7]) for e in torso), 8.0001,
                                         "symbol motion must not become a forward lunge")
                    for symbol in ("torso", "torso_pelvis", "headbase", "SWAP_BODY", "SWAP_BODY_TALL", "leg"):
                        samples = [self.elements(f, symbol) for f in clip["frames"]]
                        self.assertTrue(all(samples), symbol)
                        self.assertGreater(max(math.dist(e[0][7:9], samples[0][0][7:9]) for e in samples), .5,
                                           f"{symbol} must visibly follow the living stance")
                    # Breathing is rigid body motion, not character flattening.
                    for symbol in ("torso", "torso_pelvis", "headbase", "SWAP_BODY", "SWAP_BODY_TALL"):
                        for frame in clip["frames"]:
                            for actual, native in zip(self.elements(frame, symbol), self.elements(original, symbol)):
                                for pair in ((3, 4), (5, 6)):
                                    self.assertAlmostEqual(math.hypot(*(actual[i] for i in pair)),
                                                           math.hypot(*(native[i] for i in pair)), delta=1e-5)

    def test_breathing_cycle_wraps_without_a_pose_jump(self):
        for facing in (2, 5, 8):
            for clip in self.hold_clips(facing):
                frames = clip["frames"]
                for symbol in ("torso", "headbase", "leg", "swap_object", "hand"):
                    samples = [self.elements(f, symbol) for f in frames]
                    steps = [max(math.dist(a[7:9], b[7:9]) for a, b in zip(previous, current))
                             for previous, current in zip(samples, samples[1:])]
                    wrap = max(math.dist(a[7:9], b[7:9]) for a, b in zip(samples[-1], samples[0]))
                    self.assertLessEqual(wrap, max(steps)*1.5 + .05,
                                         (facing, clip["name"], symbol, "loop seam"))

    def test_both_hands_follow_the_same_rigid_wand_during_recoil(self):
        for facing in (2, 5, 8):
            baseline = None
            for phase in ("loop", *(f"recoil_{i:02d}" for i in range(1, 13))):
                for index, frame in enumerate(self.clip(phase, facing)["frames"]):
                    wand, = self.elements(frame, "swap_object")
                    hands = [e for e in self.elements(frame, "hand")
                             if e[2] != engine_hash("ARM_normal")]
                    self.assertEqual(len(hands), 2, "both visible arms need a grip")
                    local = [self.object_local(wand, hand[7:9]) for hand in hands]
                    # Compare in wand pitch space: foreshortening must shorten
                    # the shaft and its wrist separation together.
                    grip_span = 37 if facing == 8 else 56
                    self.assertAlmostEqual(abs(local[0][1] - local[1][1]) * .95, grip_span, delta=.001)
                    self.assertLess(max(abs(point[0]) * .95 for point in local), 20)
                    if baseline is None:
                        baseline = local
                    for actual, expected in zip(local, baseline):
                        for value, target in zip(actual, expected):
                            self.assertAlmostEqual(value, target, delta=.0005,
                                                   msg=f"hand slips at facing {facing}, {phase}, frame {index}")

    def test_recoil_levels_progressively_raise_and_retract_the_side_wand(self):
        poses = [self.clip("loop", 5)["frames"][0]] + [
            self.clip(f"recoil_{i:02d}", 5)["frames"][0] for i in range(1, 13)]
        wands = [self.elements(frame, "swap_object")[0] for frame in poses]
        angles = [math.degrees(math.atan2(-wand[6], -wand[5])) for wand in wands]
        self.assertGreater(angles[0], 0)
        self.assertLess(angles[-1], -15, "maximum recoil must visibly raise the muzzle")
        self.assertGreater(angles[-1], -30)
        for previous, current in zip(angles, angles[1:]):
            self.assertLess(current, previous)
        for previous, current in zip(wands, wands[1:]):
            self.assertLess(current[7], previous[7], "recoil should kick back toward the shoulder")
        for wand in wands:
            a, b, c, d = wand[3:7]
            self.assertAlmostEqual(math.hypot(a, b), .95, delta=1e-5)
            self.assertAlmostEqual(math.hypot(c, d), .95, delta=1e-5)
            self.assertAlmostEqual(a*c + b*d, 0, delta=1e-5)

    def test_side_and_front_staff_draw_between_hands_and_every_body_layer(self):
        for facing in (5, 8):
            for phase in ("loop", *(f"recoil_{i:02d}" for i in range(1, 13))):
                for frame in self.clip(phase, facing)["frames"]:
                    head, = self.elements(frame, "headbase")
                    wand, = self.elements(frame, "swap_object")
                    for body_name in ("torso", "torso_pelvis", "SWAP_BODY", "SWAP_BODY_TALL", "skirt"):
                        for body in self.elements(frame, body_name):
                            self.assertLess(wand[9], body[9], "body/clothing must not cover the staff")
                            self.assertLess(frame["elements"].index(wand), frame["elements"].index(body))
                    for hand in self.elements(frame, "hand"):
                        if hand[2] != engine_hash("ARM_normal"):
                            self.assertLess(hand[9], wand[9], "palm must cover the held shaft")
                            self.assertGreater(hand[9], head[9], "grip must not cover the face")
                            self.assertLess(frame["elements"].index(hand), frame["elements"].index(wand))

    def test_front_staff_points_down_with_visible_foreshortening(self):
        for frame in self.clip("loop", 8)["frames"]:
            wand, = self.elements(frame, "swap_object")
            self.assertGreater(-wand[6], .2, "front staff should reach visibly down")
            self.assertGreater(-wand[6], abs(wand[5]), "front shaft should be more vertical than horizontal")
            width = math.hypot(wand[3], wand[4])
            length = math.hypot(wand[5], wand[6])
            self.assertGreater(length / width, .25)
            self.assertLess(length / width, .45)

    def test_front_far_hand_reaches_below_the_face_instead_of_hiding_in_it(self):
        for clip in self.hold_clips(8):
            for index, frame in enumerate(clip["frames"]):
                with self.subTest(clip=clip["name"], frame=index):
                    head, = self.elements(frame, "headbase")
                    far_hand, = [e for e in self.elements(frame, "hand")
                                 if e[2] not in (engine_hash("ARM_carry"), engine_hash("ARM_normal"))]
                    # Registration points do not describe the cel's lower
                    # edge; native alpha visibility is checked below, too.
                    self.assertGreater(far_hand[8], head[8] + 8,
                                       "front far wrist needs visible clearance below the head")
                    self.assertGreater(far_hand[9], head[9], "front grip must remain behind the face")
                    for name in ("torso", "torso_pelvis", "SWAP_BODY", "SWAP_BODY_TALL", "skirt"):
                        for body in self.elements(frame, name):
                            self.assertLess(far_hand[9], body[9], "front far grip must be in front of clothing")
        if not (GAME / "data/anim/wilson.zip").exists():
            self.skipTest("Native front hand alpha visibility requires the Wilson build")
        player = NativeAnimation("player_idles", game=GAME, build_name="wilson")
        for phase in ("loop", "recoil_07", "recoil_11", "recoil_12"):
            for index in (0, 15):
                frame = self.clip(phase, 8)["frames"][index]
                hand, = [e for e in self.elements(frame, "hand")
                         if e[2] not in (engine_hash("ARM_carry"), engine_hash("ARM_normal"))]
                masks = []
                for parts in ([hand], self.elements(frame, "headbase")):
                    player.clips = [dict(name="visibility_mask", facing=8, frames=[dict(elements=parts)])]
                    rendered, origin = player.render_frame("visibility_mask", facing=8)
                    masks.append((rendered.getchannel("A"), origin))
                (hand_alpha, (hx, hy)), (head_alpha, (fx, fy)) = masks
                visible = 0
                for y in range(hand_alpha.height):
                    for x in range(hand_alpha.width):
                        px, py = x + hx - fx, y + hy - fy
                        covered = (0 <= px < head_alpha.width and 0 <= py < head_alpha.height
                                   and head_alpha.getpixel((px, py)) > 64)
                        visible += hand_alpha.getpixel((x, y)) > 64 and not covered
                self.assertGreater(visible, 100, (phase, index, "front far palm hidden by the native head cel"))

    def test_long_staff_tip_clears_the_ground_in_every_pose(self):
        # Front view deliberately lowers the longest tip. Keep a positive
        # screen-space margin while allowing that intended downward reach.
        longest_tip = 110 * 1.6 * 1.2
        for clip in self.clips:
            for index, frame in enumerate(clip["frames"]):
                wand, = self.elements(frame, "swap_object")
                tip_y = wand[8] - wand[6] * longest_tip
                self.assertLess(tip_y, -8, (clip["name"], clip["facing"], index))

    def test_manifest_identifies_the_shipped_binary_and_native_sources(self):
        manifest = json.loads((ROOT / "assets_src/player_hold_cast/manifest.json").read_text(encoding="utf8"))
        self.assertEqual(manifest["output_sha256"], hashlib.sha256(self.data).hexdigest())
        self.assertEqual(manifest["recoil_levels"], 12)
        for bank, digest in manifest["source_sha256"].items():
            source = GAME / "data/anim" / (bank + ".zip")
            if not source.exists():
                self.skipTest("Native source hash verification requires an installed DST directory")
            with ZipFile(source) as archive:
                self.assertEqual(hashlib.sha256(archive.read("anim.bin")).hexdigest(), digest)


if __name__ == "__main__":
    unittest.main()
