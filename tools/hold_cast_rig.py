"""Editable, planted player rig using the game's existing symbol builds.

Arm joints are solved in the source animation coordinate system. Both wrists
follow the same rigid held-object transform; feet never inherit upper-body
motion. No raster artwork or character-specific texture is emitted.
"""
from __future__ import annotations

import hashlib
import io
import json
import math
import struct
from pathlib import Path
from zipfile import ZipFile

from native_animation import read_animation

ROOT = Path(__file__).resolve().parents[1]
RIG_PATH = ROOT / "assets_src/player_hold_cast/rig.json"


def name_hash(name):
    value = 0
    for char in name.lower():
        value = (ord(char) + value * 65599) & 0xFFFFFFFF
    return value


def read_native(game, bank):
    with ZipFile(game / "data/anim" / (bank + ".zip")) as archive:
        data = archive.read("anim.bin")
    assert struct.unpack_from("<I", data, 4)[0] == 4
    clips = read_animation(data)
    offset = 24
    for clip in clips:
        offset += 4 + len(clip["name"].encode("utf8")) + 13
        for frame in clip["frames"]:
            offset += 24 + 4 * len(frame["events"]) + 40 * len(frame["elements"])
    reader = io.BytesIO(data[offset:])
    integer = lambda: struct.unpack("<I", reader.read(4))[0]
    names = {}
    for _ in range(integer()):
        key = integer()
        names[key] = reader.read(integer()).decode("utf8")
    assert not reader.read()
    return clips, names, hashlib.sha256(data).hexdigest()


def transform_point(m, p):
    a, b, c, d, x, y = m
    return a * p[0] + c * p[1] + x, b * p[0] + d * p[1] + y


def compose(m, n):
    a, b, c, d, x, y = m
    aa, bb, cc, dd, xx, yy = n
    return (a*aa+c*bb, b*aa+d*bb, a*cc+c*dd, b*cc+d*dd,
            a*xx+c*yy+x, b*xx+d*yy+y)


def inverse(m):
    a, b, c, d, x, y = m
    det = a*d-b*c
    return d/det, -b/det, -c/det, a/det, (c*y-d*x)/det, (b*x-a*y)/det


def apply(element, transform):
    return (*element[:3], *compose(transform, element[3:9]), element[9])


def lerp(a, b, t):
    return a + (b-a)*t


def pivot_transform(pivot, angle, dx=0, dy=0):
    co, si = math.cos(angle), math.sin(angle)
    x, y = pivot
    return co, si, -si, co, x-co*x+si*y+dx, y-si*x-co*y+dy


def lerp_matrix(a, b, t):
    """Interpolate affine rotation/scale/shear without collapsing a quarter turn."""
    def decompose(m):
        aa, bb, cc, dd, x, y = m
        scale = math.hypot(aa, bb)
        return math.atan2(bb, aa), scale, (aa*dd-bb*cc)/scale, (aa*cc+bb*dd)/scale, x, y
    a, b = decompose(a), decompose(b)
    angle = a[0] + ((b[0]-a[0]+math.pi) % math.tau-math.pi)*t
    sx, sy, shear, x, y = (lerp(aa, bb, t) for aa, bb in zip(a[1:], b[1:]))
    co, si = math.cos(angle), math.sin(angle)
    return co*sx, si*sx, co*shear-si*sy, si*shear+co*sy, x, y


def similarity(a, b, target_a, target_b):
    vx, vy = b[0]-a[0], b[1]-a[1]
    ux, uy = target_b[0]-target_a[0], target_b[1]-target_a[1]
    denominator = vx*vx+vy*vy
    co, si = (ux*vx+uy*vy)/denominator, (uy*vx-ux*vy)/denominator
    return co, si, -si, co, target_a[0]-co*a[0]+si*a[1], target_a[1]-si*a[0]-co*a[1]


def elbow(shoulder, wrist, original, lengths):
    vx, vy = wrist[0]-shoulder[0], wrist[1]-shoulder[1]
    distance = max(.001, math.hypot(vx, vy))
    l1, l2 = lengths
    stretch = max(1, distance/(l1+l2-.001))
    l1, l2 = l1*stretch, l2*stretch
    along = (l1*l1-l2*l2+distance*distance)/(2*distance)
    across = math.sqrt(max(0, l1*l1-along*along)) * original
    return (shoulder[0]+along*vx/distance-across*vy/distance,
            shoulder[1]+along*vy/distance+across*vx/distance)


class Rig:
    def __init__(self, game, config=None):
        self.config = config or json.loads(RIG_PATH.read_text(encoding="utf8"))
        idle, idle_names, idle_hash = read_native(game, "player_idles")
        attacks, attack_names, attack_hash = read_native(game, "player_attacks")
        parry, parry_names, parry_hash = read_native(game, "player_parryblock")
        channel, channel_names, channel_hash = read_native(game, "player_channelcast_basic")
        self.names = {**idle_names, **attack_names, **parry_names, **channel_names}
        self.sources = {"player_idles": idle_hash, "player_attacks": attack_hash,
                        "player_parryblock": parry_hash, "player_channelcast_basic": channel_hash}
        self.idles = {c["facing"]: c["frames"][0] for c in idle if c["name"] == "idle_loop"}
        self.grips = {c["facing"]: c["frames"][3] for c in attacks if c["name"] == "spearjab"}
        self.stances = {c["facing"]: c["frames"][0] for c in parry if c["name"] == "parry_loop"}
        self.breath = {c["facing"]: [next(e[8] for e in f["elements"] if e[0] == name_hash("torso"))
                                    for f in c["frames"]]
                       for c in channel if c["name"] == "channelcast_idle"}

    def pose(self, facing, extension, recoil=0, phase=0):
        conf = self.config
        design = conf["facings"][str(facing)]
        native = self.idles[facing]["elements"]
        grip = self.grips[facing]["elements"]
        symbol = lambda e: self.names[e[0]].lower()
        layer = lambda e: self.names[e[2]].lower()
        near = lambda e: layer(e) == "arm_carry"
        arm_symbols = {"arm_upper", "arm_upper_skin", "arm_lower", "arm_lower_cuff", "hand"}
        far = lambda e: symbol(e) in arm_symbols and layer(e) not in ("arm_carry", "arm_normal")
        find = lambda elements, name, predicate: next(e for e in elements if symbol(e) == name and predicate(e))
        old_object = find(native, "swap_object", near)
        template_object = find(grip, "swap_object", near)
        curve = self.breath[facing]
        cursor = (phase % 1)*len(curve)
        index = int(cursor)
        sample = lerp(curve[index], curve[(index+1) % len(curve)], cursor-index)
        breath = (sample-curve[0])/(max(curve)-min(curve))*conf["breath_pixels"]
        theta = phase*math.tau
        vibration = math.sin(theta*6)*recoil**2
        body_y = conf["crouch_pixels"]+breath+recoil*conf["recoil_body_pixels"]
        body_y += vibration*conf["recoil_vibration_pixels"]
        body_x = design["hip_shift"] + (.45*math.sin(theta)-1.5*recoil if facing == 5 else 0)
        lean = design["lean_degrees"] + (.6*math.sin(theta)-2*recoil if facing == 5 else .35*math.sin(theta))
        torso = find(native, "torso", lambda e: True)
        body = pivot_transform(torso[7:9], math.radians(lean)*extension,
                               body_x*extension, body_y*extension)
        # Head lags the chest slightly instead of translating the whole actor
        # as one rigid card. All face, beard, hair and hat layers share it.
        head_pivot = find(native, "headbase", lambda e: True)[7:9]
        head = compose(body, pivot_transform(head_pivot,
                        math.radians(.6*math.sin(theta-.35)-.6*recoil)*extension,
                        dy=.55*(math.sin(theta-.35)-math.sin(-.35))*extension))
        # A single shared object matrix is also the authoritative wrist target.
        pitch = math.radians(design["aim_degrees"] + recoil*design["recoil_degrees"]
                             + .45*math.sin(theta) + .8*vibration)
        direction = math.cos(pitch), math.sin(pitch)
        anchor = (design["anchor"][0]-direction[0]*recoil*design["kickback"],
                  design["anchor"][1]+body_y-direction[1]*recoil*design["kickback"])
        angle = pitch+math.pi/2
        scale = conf["object_scale"]
        # A staff aimed into/out of the screen needs foreshortening; otherwise
        # its front-facing tip passes below the planted feet.
        longitudinal = design.get("longitudinal_scale", 1)
        target_object = (math.cos(angle)*scale, math.sin(angle)*scale,
                         -math.sin(angle)*scale*longitudinal,
                         math.cos(angle)*scale*longitudinal, *anchor)
        # Back-facing held sprites are mirrored in the native character bank.
        if facing == 2:
            target_object = (-target_object[0], -target_object[1], *target_object[2:])
        matrix = lerp_matrix(old_object[3:9], target_object, extension)
        remap_grip = compose(target_object, inverse(template_object[3:9]))
        arms = {}
        for side, predicate in (("near", near), ("far", far)):
            upper = find(native, "arm_upper", predicate)
            lower = find(native, "arm_lower", predicate)
            hand = find(native, "hand", predicate)
            # Native spearjab supplies closed palm shapes and their grip axis,
            # never its lunging body or stretched legs.
            template_hand = next(e for e in grip if symbol(e) == "hand" and
                                 ((e[1] == (4 if facing == 2 else 1)) if side == "near"
                                  else (e[1] != (4 if facing == 2 else 1))))
            target_hand = apply(template_hand, remap_grip)
            # Both hands stay on the wood even with the shortest modular wand.
            hx, hy = target_hand[7]-anchor[0], target_hand[8]-anchor[1]
            along = hx*direction[0]+hy*direction[1]
            adjust = design.get("grips", conf["grips"])[side]*longitudinal-along
            target_hand = (*target_hand[:7], target_hand[7]+direction[0]*adjust,
                           target_hand[8]+direction[1]*adjust, target_hand[9])
            hand_matrix = lerp_matrix(hand[3:9], target_hand[3:9], extension)
            a, b, w = upper[7:9], lower[7:9], hand[7:9]
            shoulder = transform_point(body, a)
            wrist = hand_matrix[4:6]
            cross = (w[0]-a[0])*(b[1]-a[1])-(w[1]-a[1])*(b[0]-a[0])
            lengths = math.dist(a, b), math.dist(b, w)
            native_bend = 1 if cross >= 0 else -1
            bend = design.get("elbow_bend", {}).get(side, native_bend)
            joint = elbow(shoulder, wrist, native_bend, lengths)
            if bend != native_bend:
                braced_joint = elbow(shoulder, wrist, bend, lengths)
                joint = tuple(lerp(a, b, extension) for a, b in zip(joint, braced_joint))
            arms[side] = {"upper": similarity(a, b, shoulder, joint),
                          "lower": similarity(b, w, joint, wrist),
                          "hand": (*hand[:1], template_hand[1] if extension >= .35 else hand[1],
                                   hand[2], *hand_matrix, hand[9])}
        output = []
        feet = [e for e in native if symbol(e) == "foot"]
        legs = [e for e in native if symbol(e) == "leg"]
        stance = self.stances[facing]["elements"]
        stance_legs = [e for e in stance if symbol(e) == "leg"]
        stance_feet = [e for e in stance if symbol(e) == "foot"]
        foot_targets = [apply(e, (1, 0, 0, 1, design["foot_shift"][i]*extension, 0))
                        for i, e in enumerate(feet)]
        head_symbols = {"headbase", "headbase_hat", "swap_hat", "swap_face", "beard", "face",
                        "hair", "hairfront", "hair_hat", "hairpigtails"}
        for element in native:
            kind = symbol(element)
            if kind == "swap_object":
                output.append((*element[:3], *matrix, element[9]))
            elif kind == "foot":
                output.append(foot_targets[feet.index(element)])
            elif kind == "leg":
                i = legs.index(element)
                hip = transform_point(body, element[7:9])
                ankle = foot_targets[i][7:9]
                # Native bent-leg cels avoid making a knee by flattening a
                # straight leg. Select the crouched cel midway through entry.
                bent = extension >= .35 and design.get("leg_stance", ["parry", "parry"])[i] == "parry"
                template = stance_legs[i] if bent else element
                old_ankle = stance_feet[i][7:9] if bent else feet[i][7:9]
                posed = apply(template, similarity(template[7:9], old_ankle, hip, ankle))
                output.append((element[0], posed[1], element[2], *posed[3:9], element[9]))
            elif kind in arm_symbols and (near(element) or far(element)):
                side = "near" if near(element) else "far"
                if kind == "hand":
                    output.append(arms[side]["hand"])
                else:
                    output.append(apply(element, arms[side]["upper" if kind.startswith("arm_upper") else "lower"]))
            else:
                output.append(apply(element, head if kind in head_symbols else body))
        if facing in (5, 8):
            # Layered followers inherit swap_object's draw slot. Keep the whole
            # staff above body/clothing, with hands covering the wooden grip.
            # SWAP_BODY may be in front of torso: checking torso alone is wrong.
            body_depth = min(e[9] for e in native if symbol(e) in
                             ("torso", "torso_pelvis", "swap_body", "swap_body_tall", "skirt"))
            face_depth = min(e[9] for e in native if symbol(e) == "headbase")
            fractions = ({"arm_upper": .55, "arm_upper_skin": .56,
                          "arm_lower": .65, "arm_lower_cuff": .66,
                          "swap_object": .4, "hand": .75} if facing == 5 else
                         {"arm_upper": .15, "arm_upper_skin": .2,
                          "arm_lower": .3, "arm_lower_cuff": .35,
                          "swap_object": .5, "hand": .75})
            output = [(*e[:9], lerp(e[9], lerp(body_depth, face_depth,
                                              fractions[symbol(e)]), extension))
                      if symbol(e) in fractions and layer(e) != "arm_normal" else e
                      for e in output]
        elif facing == 2:
            # Native back idle has two carry upper-arm entries. Both must sit
            # behind the head and back when the hands reach forward; otherwise
            # the first copy draws through the nape despite the second being hidden.
            cover_depth = max(e[9] for e in native if symbol(e) in
                              ("headbase", "torso", "torso_pelvis", "swap_body", "swap_body_tall", "skirt"))
            depths = {"arm_upper": .3, "arm_upper_skin": .29,
                      "arm_lower": .2, "arm_lower_cuff": .19, "hand": .1}
            output = [(*e[:9], lerp(e[9], cover_depth + depths[symbol(e)], extension))
                      if symbol(e) in depths and layer(e) != "arm_normal" else e
                      for e in output]
        # Native banks encode each frame in ascending depth order. A preview
        # renderer sorting by depth can otherwise hide a malformed draw order.
        output.sort(key=lambda e: e[9])
        return {"bounds": (0, -160, 750, 700), "events": [], "elements": output}

    def clips(self):
        result = []
        for facing in (5, 8, 2):
            def add(name, frames):
                result.append(dict(name="nw_hold_cast_"+name, root=name_hash("wilson"),
                                   facing=facing, fps=30, frames=frames))
            count = self.config["frames"]
            frames = []
            for index in range(count):
                t = index/(count-1)
                frames.append(self.pose(facing, t*t*(3-2*t)))
            add("pre", frames)
            cycle = self.config["cycle_frames"]
            add("loop", [self.pose(facing, 1, phase=i/cycle) for i in range(cycle)])
            add("pst", frames[::-1])
            for level in range(1, self.config["recoil_levels"]+1):
                add(f"recoil_{level:02d}", [self.pose(facing, 1, level/self.config["recoil_levels"], i/cycle)
                                          for i in range(cycle)])
        return result


def encode(clips, names):
    output = io.BytesIO()
    def pack(fmt, *values):
        output.write(struct.pack("<"+fmt, *values))
    def string(value):
        data = value.encode("utf8"); pack("I", len(data)); output.write(data)
    output.write(b"ANIM")
    pack("IIIII", 4, sum(len(f["elements"]) for c in clips for f in c["frames"]),
         sum(len(c["frames"]) for c in clips), 0, len(clips))
    for clip in clips:
        string(clip["name"])
        pack("BIfI", clip["facing"], clip["root"], clip["fps"], len(clip["frames"]))
        for frame in clip["frames"]:
            pack("ffffII", *frame["bounds"], 0, len(frame["elements"]))
            for element in frame["elements"]:
                pack("IIIfffffff", *element)
    pack("I", len(names))
    for key, value in sorted(names.items()):
        pack("I", key); string(value)
    return output.getvalue()
