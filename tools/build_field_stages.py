"""Build layered field lifecycles from existing painted component art.

This bank deliberately contains no projectile or insect assets. Ground planes
use native OnGround projection where they define an area; planted Billboard
bodies retain their ground anchor, while detached glints and fragments move.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageChops, ImageOps

from build_art_assets import ROOT, RUNTIME, compile_bank

BANK = "nw_field_stages"
FPS = 30
KINDS = (
    "crystal_mine", "sleep_crystal", "payload_egg", "moon_fall", "delay_seal",
    "detonate", "rain_cloud", "storm_cloud", "guard_ring", "shock_ring",
    "vortex", "deer_decoy", "vital_ring", "spore_sentry",
)
PERIODS = {"spawn": .2, "idle": 1.2, "pulse": .2, "end": .3,
           "warning": .3, "fall": .24}
# The world anchor is the centre of the painted contact patch. The foreground
# edge of an isometric base extends below it; anchoring its lowest pixel at
# zero makes the whole base read as sitting behind/above its placement point.
PLACEMENT_BASELINE = {"crystal_mine": 12, "sleep_crystal": 10, "payload_egg": 5}
SOURCE = ROOT / "assets_src/fields/stages_v1"
WORLD = RUNTIME / "nw_spell_world"
ORIGINALS = ROOT / "assets_src/art_v1/originals"
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")


def opened(path: Path, fit=None):
    image = Image.open(path).convert("RGBA")
    image.putalpha(image.getchannel("A").point(lambda a: a if a > 8 else 0))
    image = image.crop(image.getchannel("A").getbbox())
    if fit:
        image = ImageOps.contain(image, fit, Image.Resampling.LANCZOS)
    return image


def select(image, predicate):
    """Extract an existing painted layer without inventing replacement pixels."""
    output = image.copy()
    alpha = []
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = image.getpixel((x, y))
            alpha.append(round(a * max(0, min(1, predicate(x, y, r, g, b)))))
    output.putalpha(Image.new("L", image.size))
    output.getchannel("A")  # Keep the image mode explicit for the compiler.
    channel = Image.new("L", image.size)
    channel.putdata(alpha)
    output.putalpha(channel)
    return output


def main_piece(image):
    """Discard isolated neighbouring paint flecks without changing registration."""
    pixels = image.getchannel("A")
    remaining = {(x, y) for y in range(image.height) for x in range(image.width)
                 if pixels.getpixel((x, y)) > 8}
    largest = set()
    while remaining:
        pending = [remaining.pop()]
        component = set(pending)
        while pending:
            x, y = pending.pop()
            for point in ((x-1,y), (x+1,y), (x,y-1), (x,y+1)):
                if point in remaining:
                    remaining.remove(point)
                    component.add(point)
                    pending.append(point)
        if len(component) > len(largest):
            largest = component
    return select(image, lambda x, y, r, g, b: 1 if (x, y) in largest else 0)


class FieldBank:
    def __init__(self):
        self.build = ET.Element("Build", name=BANK)
        self.animations = ET.Element("Anims")
        self.images = {}
        self.sprites = {}
        self.clips = {}
        self.sources = {}

    def sprite(self, key, image, source, levels=8):
        self.sprites[key] = image
        self.sources[key] = source
        symbol = ET.SubElement(self.build, "Symbol", name=key)
        for level in range(levels):
            opacity = (level + 1) / levels
            copy = image.copy()
            copy.putalpha(copy.getchannel("A").point(lambda a: round(a * opacity)))
            name = f"{key}_{level}"
            self.images[name] = copy
            ET.SubElement(symbol, "Frame", framenum=str(level), duration="1", image=name,
                          x="0", y="0", w=str(image.width), h=str(image.height))

    def layer(self, key, x=0, y=0, angle=0, sx=1, sy=None, opacity=1):
        if opacity <= .025:
            return None
        return (key, x, y, angle, sx, sx if sy is None else sy,
                max(0, min(7, math.ceil(opacity * 8) - 1)))

    def clip(self, name, seconds, make_pose, loop=False):
        # The native compiler accepts integer fps only. Six frames at 25 fps
        # preserve the .24 s fall exactly instead of rounding the deadline.
        fps = 25 if seconds == .24 else FPS
        count = max(1, round(seconds * fps))
        animation = ET.SubElement(self.animations, "anim", name=name, root=BANK,
                                  framerate=str(fps))
        poses = []
        for index in range(count):
            t = index / count if loop else index / max(1, count - 1)
            layers = [layer for layer in make_pose(t, index) if layer is not None]
            poses.append(layers)
            frame = ET.SubElement(animation, "frame")
            corners = []
            for z, (key, x, y, angle, sx, sy, opacity) in enumerate(layers):
                a, b = math.cos(angle) * sx, math.sin(angle) * sx
                c, d = -math.sin(angle) * sy, math.cos(angle) * sy
                if key in ("vortex_core", "vortex_rocks"):
                    # Restore the source's circular footprint before rotating.
                    # Runtime OnGround supplies the camera projection exactly.
                    aspect = self.sprites[key].width/self.sprites[key].height
                    a, b = math.cos(angle)*sx, math.sin(angle)*sx
                    c, d = -math.sin(angle)*sx*aspect, math.cos(angle)*sx*aspect
                sprite = self.sprites[key]
                for px in (-sprite.width / 2, sprite.width / 2):
                    for py in (-sprite.height / 2, sprite.height / 2):
                        corners.append((x + a * px + c * py, y + b * px + d * py))
                ET.SubElement(frame, "element", name=key, frame=str(opacity),
                              layername=key, z_index=str(z), m_a=str(a), m_b=str(b),
                              m_c=str(c), m_d=str(d), m_tx=str(x), m_ty=str(y))
            if not corners:
                corners = [(-1, -1), (1, 1)]
            xs, ys = zip(*corners)
            frame.attrib.update(x=str((min(xs) + max(xs)) / 2),
                                y=str((min(ys) + max(ys)) / 2),
                                w=str(max(xs) - min(xs) + 2), h=str(max(ys) - min(ys) + 2))
        self.clips[name] = {"seconds": seconds, "fps": fps, "loop": loop, "poses": poses}

    def manifest(self):
        manifest = {"bank": BANK, "orientation": "BillBoard", "ground_kinds": ["vortex", "shock_ring"], "kinds": KINDS,
                    "placement_baseline_pixels": PLACEMENT_BASELINE,
                    "pixels_per_world_unit": 150, "sources": self.sources,
                    "packing": self.packing,
                    "sprite_sizes": {key: im.size for key, im in self.sprites.items()},
                    "clips": {key: {k: v for k, v in clip.items() if k != "poses"}
                              | {"frames": len(clip["poses"])} for key, clip in self.clips.items()},
                    "footprint_width_pixels": {"moon_fall": 100, "shock_ring": 191, "vortex": 220},
                    "notes": ["Runtime fits moon/shock/vortex art to gameplay radius", "Moon fall is non-looping",
                              "Moon warning uses a separate native soft shadow, without a range circle",
                              "Deer uses four idle poses and a single eight-pose spin followed by dissolution",
                              "Guard and vital rings use independent client members, never a composite ring",
                              "Eight alpha levels are baked into existing painted textures"]}
        return manifest

    def prune_unused_frames(self):
        """Pack only referenced alpha/pose images, with compact frame indices.

        DST's default animation shader supports two atlas pages. Baking every
        alpha level of every deer pose needlessly exceeds that limit even
        though nearly all those combinations never appear in an animation.
        This preserves every rendered pixel and pose while removing dead data.
        """
        used = {}
        for part in self.animations.iter("element"):
            used.setdefault(part.get("name"), set()).add(int(part.get("frame")))
        remap = {key: {old: new for new, old in enumerate(sorted(levels))}
                 for key, levels in used.items()}
        images = {}
        before = len(self.images)
        for symbol in list(self.build):
            key = symbol.get("name")
            if key not in used:
                self.build.remove(symbol)
                continue
            for frame in list(symbol):
                old = int(frame.get("framenum"))
                if old not in used[key]:
                    symbol.remove(frame)
                    continue
                index = remap[key][old]
                name = f"{key}_{index}"
                images[name] = self.images[frame.get("image")]
                frame.set("framenum", str(index))
                frame.set("image", name)
        for part in self.animations.iter("element"):
            part.set("frame", str(remap[part.get("name")][int(part.get("frame"))]))
        for clip in self.clips.values():
            clip["poses"] = [[(*part[:6], remap[part[0]][part[6]]) for part in pose]
                             for pose in clip["poses"]]
        self.images = images
        self.packing = {"candidate_images": before, "referenced_images": len(images),
                        "max_atlas_pages": 2, "source_pixels_unchanged": True}

    def prepare(self):
        folder = RUNTIME / BANK
        folder.mkdir(parents=True, exist_ok=True)
        SOURCE.mkdir(parents=True, exist_ok=True)
        for key, image in self.images.items():
            image.save(folder / f"{key}.png")
        ET.ElementTree(self.build).write(folder / "build.xml", encoding="utf-8", xml_declaration=True)
        ET.ElementTree(self.animations).write(folder / "animation.xml", encoding="utf-8", xml_declaration=True)
        manifest = self.manifest()
        (SOURCE / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return manifest


def build_bank():
    bank = FieldBank()
    L = bank.layer
    for key in ("crystal_mine", "sleep_crystal", "payload_egg", "rain_cloud", "shield", "drop", "signal0"):
        path = WORLD / f"{key}.png"
        bank.sprite(key, opened(path), str(path.relative_to(ROOT)))
    for key, size in (("moon_fall", (165, 200)), ("delay_seal", (150, 150)),
                      ("detonate", (150, 150)), ("shock_ring", (200, 200)),
                      ("vortex", (220, 220)), ("storm_cloud", (240, 240))):
        path = ORIGINALS / f"{key}.png"
        bank.sprite(key, opened(path, size), str(path.relative_to(ROOT)))
    ring = opened(RUNTIME / "nw_objects/blast_extent.png", (240, 240))
    bank.sprite("ground_ring", ring, "nw_objects/blast_extent.png")
    # Source coordinates refer to the full 900x450 canvas, not its trimmed
    # alpha bounds (the outer mushrooms leave a small transparent margin).
    vital = Image.open(RUNTIME / "nw_objects/garden_ring.png").convert("RGBA")
    mushroom = vital.crop((410, 47, 489, 113))
    cap = main_piece(mushroom.crop((0, 0, mushroom.width, 39)))
    cap = select(cap, lambda x, y, r, g, b: 1 if y >= max(0, 15-.5*x) else 0)
    bank.sprite("vital_cap", cap,
                "nw_objects/garden_ring.png: single upper mushroom cap")
    stem = main_piece(mushroom.crop((0, 34, mushroom.width, mushroom.height)))
    stem = select(stem, lambda x, y, r, g, b: 1 if 25 <= x <= 61 else 0)
    bank.sprite("vital_stem", stem,
                "nw_objects/garden_ring.png: single upper mushroom stem/ground")
    # Use a complete spore, not a rectangular crop through its luminous centre.
    mote = vital.crop((426, 298, 499, 362))
    mote = select(mote, lambda x, y, r, g, b:
                  max(0, min(1, (min(r,g,b)-100)/60)) if g > r+5 and g > b+3 else 0)
    mote = main_piece(mote)
    mote = ImageOps.contain(mote.crop(mote.getchannel("A").getbbox()), (27, 27), Image.Resampling.LANCZOS)
    bank.sprite("vital_mote", mote, "nw_objects/garden_ring.png: one complete pale green spore")
    for pose in ("bud", "sprout", "idle", "aim", "fire", "wilt"):
        path = RUNTIME / "nw_objects" / f"plant_{pose}.png"
        bank.sprite("spore_" + pose, opened(path), str(path.relative_to(ROOT)))
    plant = bank.sprites["spore_idle"]
    bank.sprite("spore_head", plant.crop((0, 0, plant.width, 93)), "plant_idle: thorn head")
    bank.sprite("spore_root", plant.crop((0, 88, plant.width, plant.height)), "plant_idle: fixed stem/root")
    # The painted objects stay rooted. These masks contain their existing bright
    # facets only, so the pulsing layer does not stretch the stones or egg shell.
    for key in ("crystal_mine", "sleep_crystal", "payload_egg", "delay_seal", "detonate", "shock_ring"):
        image = bank.sprites[key]
        shine = select(image, lambda x, y, r, g, b: max(0, (max(r, g, b) - 165) / 90))
        bank.sprite(key + "_shine", shine, key + ": existing bright painted facets")
    # Cloud body stays painted; actual strikes now use native shock_fx strokes
    # between cloud and target. A facet shimmer gives the warning its own cue.
    storm = bank.sprites["storm_cloud"]
    cloud = select(storm, lambda x, y, r, g, b: 0 if y > storm.height*.43 and b>r+18 and b>155
                   else 1 if y < storm.height*.60 else max(0, 1-(y/storm.height-.60)/.10))
    shine = select(cloud, lambda x, y, r, g, b: max(0, (min(r, g, b)-120)/135))
    bank.sprite("storm_body", cloud, "storm_cloud: cloud portion")
    bank.sprite("storm_shine", shine, "storm_cloud: existing bright cloud facets")
    vortex = bank.sprites["vortex"]
    center = (vortex.width / 2, vortex.height / 2)
    radius = min(vortex.size) * .34
    core = select(vortex, lambda x, y, r, g, b: max(0, min(1, (radius + 5 - math.hypot(x-center[0], y-center[1])) / 10)))
    outer = vortex.copy()
    outer.putalpha(ImageChops.subtract(vortex.getchannel("A"), core.getchannel("A")))
    bank.sprite("vortex_core", core, "vortex: inner swirl")
    bank.sprite("vortex_rocks", outer, "vortex: outer rocks")

    # Keep the generated atlas' cell registration: a dissolve frame must not
    # be enlarged/recentred as its surviving silhouette becomes smaller.
    deer_path = SOURCE / "deer_spirit_v2.png"
    deer_sheet = Image.open(deer_path).convert("RGBA")
    for index in range(16):
        column, row = index % 4, index // 4
        bounds = (round(column*deer_sheet.width/4), round(row*deer_sheet.height/4),
                  round((column+1)*deer_sheet.width/4), round((row+1)*deer_sheet.height/4))
        pose = deer_sheet.crop(bounds).resize((256, 256), Image.Resampling.LANCZOS)
        bank.sprite(f"deer_pose_{index}", pose,
                    f"{deer_path.relative_to(ROOT)}: row {row+1}, column {column+1}")

    def ground(t, opacity=.5, scale=1):
        return L("ground_ring", 0, 1, sx=scale, sy=.46 * scale, opacity=opacity)

    moon = bank.sprites["moon_fall"]
    moon_angle = -.45
    mc, ms = math.cos(moon_angle), math.sin(moon_angle)
    # Measure painted contact, not the rotated rectangular canvas corners.
    # The rock centre is left/below the full sprite centre because of its tail.
    moon_x = -(mc*(50-moon.width/2)-ms*(115-moon.height/2))
    moon_y = 5-max(ms*(x-moon.width/2)+mc*(y-moon.height/2)
                   for y in range(moon.height) for x in range(moon.width)
                   if moon.getpixel((x, y))[3] > 32)

    def fragments(key, t, base_y, base_x=0, angle=0):
        # End-only quadrants use the authored registration, never a per-frame
        # recenter. The intact object remains fixed before this stage.
        image = bank.sprites[key]
        layers = []
        for index in range(4):
            part = f"{key}_piece_{index}"
            if part not in bank.sprites:
                x0 = index % 2 * image.width // 2
                y0 = index // 2 * image.height // 2
                x1 = image.width if index % 2 else image.width // 2
                y1 = image.height if index // 2 else image.height // 2
                bank.sprite(part, image.crop((x0, y0, x1, y1)), key + ": breakup quadrant")
            dx = -1 if index % 2 == 0 else 1
            dy = -1 if index < 2 else 1
            px, py = dx*image.width/4, dy*image.height/4
            layers.append(L(part, base_x+math.cos(angle)*px-math.sin(angle)*py+dx*48*t,
                            base_y+math.sin(angle)*px+math.cos(angle)*py-55*t+45*t*t,
                            angle=angle+dx*t*.45, opacity=1-t))
        return layers

    def posed(kind, phase, t, index, shields=2):
        alpha = t if phase == "spawn" else 1-t if phase == "end" else 1
        pulse = math.sin(t * math.pi) if phase in ("pulse", "warning") else 0
        wave = (math.sin(t * math.tau) + 1) / 2
        if kind in ("crystal_mine", "sleep_crystal", "payload_egg"):
            y = -bank.sprites[kind].height / 2 + PLACEMENT_BASELINE[kind]
            if phase == "end":
                return [ground(t, (1-t)*.6, .35+t*.6)] + fragments(kind, t, y)
            layers = [L(kind, y=y, opacity=alpha)]
            if kind != "payload_egg" or phase != "idle":
                layers.append(L(kind+"_shine", y=y, opacity=alpha*(.20 + .7*pulse + .14*wave)))
            if kind == "crystal_mine":
                for n in range(3):
                    age = (t + n/3) % 1
                    layers.append(L("signal0", y=-105-age*20+PLACEMENT_BASELINE[kind], sx=.6+age*.6,
                                    sy=.6, opacity=alpha*(1-age)*.8))
            return layers
        if kind == "moon_fall":
            if phase in ("spawn", "idle", "warning"):
                return []  # Native meteor_shadow is a separate ground-plane child.
            if phase == "fall":
                return [L(kind, 135*(1-t)+moon_x*t, -550+(550+moon_y)*t*t, angle=moon_angle)]
            return fragments(kind, t, moon_y, moon_x, moon_angle)
        if kind in ("delay_seal", "detonate"):
            y = -bank.sprites[kind].height/2-8
            return [ground(t, alpha*(.25+.4*pulse), .65+.25*pulse),
                    L(kind, y=y, opacity=alpha),
                    L(kind+"_shine", y=y, opacity=alpha*(.2+.8*pulse+.15*wave))]
        if kind in ("rain_cloud", "storm_cloud"):
            storm = kind == "storm_cloud"
            key = "storm_body" if storm else "rain_cloud"
            y = -330 if storm else -370
            # Body position does not bob; detached rain/bolt layers own motion.
            layers = [L(key, y=y, opacity=alpha)]
            if phase == "end":
                for n in (-1, 1):
                    layers.append(L(key, n*t*45, y-15*t, sx=.55, sy=.85,
                                    opacity=(1-t)*.35))
                return layers
            if storm:
                if phase in ("warning", "pulse"):
                    layers.append(L("storm_shine", y=y,
                                    opacity=alpha*(.28+.72*pulse if phase=="warning" else 1)))
            else:
                for n in range(14):
                    u = (t*2+n*.371) % 1
                    layers.append(L("drop", ((n*79)%302)-151-u*13, -320+u*315,
                                    sx=.7, sy=1, opacity=alpha*(1-u*.3)))
            return layers
        if kind in ("guard_ring", "vital_ring", "spore_sentry"):
            # Root clips are transparent placeholders only. The runtime owns
            # independent world-coordinate shield/mushroom members and their
            # stage changes. No painted ring is ever shown by the root.
            return []
        if kind == "shock_ring":
            aspect = bank.sprites[kind].width/bank.sprites[kind].height
            return [L(kind, sx=1, sy=aspect, opacity=alpha*.7),
                    L(kind+"_shine", sx=.85+.15*pulse, sy=aspect*(.85+.15*pulse),
                      opacity=alpha*(.3+.7*pulse))]
        if kind == "vortex":
            theta = t*math.tau if phase=="idle" else t*math.pi/2
            return [L("vortex_core", angle=theta, opacity=alpha),
                    L("vortex_rocks", angle=-theta*.25, opacity=alpha)]
        if kind == "deer_decoy":
            if phase == "end":
                # Fifteen 30 Hz frames: one full body turn, then the four
                # authored dissolve poses. No rotation of the flat sprite.
                sequence = (4, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 13, 14, 15, 15)
                pose = sequence[min(index, len(sequence)-1)]
                opacity = 1 if index < 11 else (14-index)/4
            else:
                pose = (0, 1, 2, 3, 2, 1)[min(5, int(t*6))] if phase=="idle" else 0
                opacity = alpha
            return [L(f"deer_pose_{pose}", y=-107, opacity=opacity)]
        raise KeyError(kind)

    for kind in KINDS:
        for phase in ("spawn", "idle", "pulse", "end"):
            seconds = .5 if kind=="deer_decoy" and phase=="end" else PERIODS[phase]
            bank.clip(f"{kind}_{phase}", seconds,
                      lambda t, index, kind=kind, phase=phase: posed(kind, phase, t, index), phase=="idle")
    for phase in ("warning", "fall"):
        bank.clip("moon_fall_"+phase, PERIODS[phase],
                  lambda t, index, phase=phase: posed("moon_fall", phase, t, index), phase=="warning")
    bank.clip("storm_cloud_warning", .3, lambda t, index: posed("storm_cloud", "warning", t, index))
    def member(kind, phase, t):
        alpha = t if phase == "spawn" else 1-t if phase == "end" else 1
        pulse = math.sin(t*math.pi) if phase == "pulse" else 0
        if kind == "guard":
            return [L("shield", angle=.06*math.sin(t*math.tau) if phase=="idle" else -.10*pulse,
                      sx=1+.10*pulse, sy=1-.05*pulse, opacity=alpha)]
        growth = .15+.85*t if phase=="spawn" else 1-.85*t if phase=="end" else 1
        cap_scale = .3+.7*t if phase=="spawn" else 1-.7*t if phase=="end" else 1
        stem = bank.sprites["vital_stem"]
        cap = bank.sprites["vital_cap"]
        cap_y = -stem.height*growth - cap.height*cap_scale/2 + 5*cap_scale
        return [L("vital_stem", y=-stem.height*growth/2, sx=1, sy=growth, opacity=alpha),
                L("vital_cap", y=cap_y-3*pulse, sx=cap_scale*(1+.05*pulse),
                  sy=cap_scale, opacity=alpha),
                L("vital_mote", y=cap_y-10-16*pulse, sx=1.4+.8*pulse,
                  opacity=alpha*pulse)]

    for kind in ("guard", "vital"):
        for phase in ("spawn", "idle", "pulse", "end"):
            bank.clip(f"{kind}_member_{phase}", PERIODS[phase],
                      lambda t, index, kind=kind, phase=phase: member(kind, phase, t), phase=="idle")
    bank.clip("vital_mote_idle", 1.2,
              lambda t, index: [L("vital_mote", sx=.8+.15*math.sin(t*math.tau),
                                  opacity=.55+.35*(math.sin(t*math.tau)+1)/2)], True)
    bank.clip("vital_mote_pulse", .2,
              lambda t, index: [L("vital_mote", sx=1.2+.8*math.sin(t*math.pi),
                                  opacity=.8+.2*math.sin(t*math.pi))])

    def plant_pose(phase, t, index):
        if phase == "idle":
            # Roots stay fixed. The thorn head moves around the stem attachment,
            # with a tiny breathing displacement rather than swaying the soil.
            angle = .018*math.sin(t*math.tau)
            return [L("spore_root", y=-bank.sprites["spore_root"].height/2),
                    L("spore_head", x=2*math.sin(t*math.tau), y=-91.5,
                      angle=angle)]
        if phase == "grow":
            key = "spore_" + ("bud" if t < 5/18 else "sprout" if t < 12/18 else "idle")
            return [L(key, y=-bank.sprites[key].height/2, opacity=min(1, t*5+.2))]
        if phase == "fire":
            key = "spore_" + ("aim" if t < .5 else "fire" if t < .8 else "idle")
            recoil = -4*math.sin((t-.5)*math.pi*2) if .5 < t < 1 else 0
            return [L(key, x=recoil, y=-bank.sprites[key].height/2)]
        return [L("spore_wilt", y=-bank.sprites["spore_wilt"].height/2,
                  opacity=1-t)]

    for phase, seconds in (("grow", .6), ("idle", 1.2), ("fire", .4), ("wilt", .3)):
        bank.clip("spore_"+phase, seconds,
                  lambda t, index, phase=phase: plant_pose(phase, t, index), phase=="idle")
    bank.prune_unused_frames()
    return bank


def make_bank():
    """Side-effect-free entry for the isolated hot-preview compiler."""
    bank = build_bank()
    return bank.build, bank.animations, bank.images, bank.manifest()


def old_bank_hashes():
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (ROOT/"mod/anim").glob("nw_*.zip")
            if path.stem in ("nw_elemental_flight", "nw_spark_flight", "nw_spell_world", "nw_objects")}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    before = old_bank_hashes()
    bank = build_bank()
    manifest = bank.prepare()
    if not args.prepare_only:
        compile_bank(BANK, bank.build, bank.animations, bank.images, MOD_TOOLS)
    assert old_bank_hashes() == before, "Unrelated banks changed while compiling field stages"
    print(json.dumps({"bank": BANK, "clips": len(manifest["clips"]), "images": len(bank.images),
                      "old_banks_unchanged": len(before), "prepared_only": args.prepare_only}))


if __name__ == "__main__":
    main()
