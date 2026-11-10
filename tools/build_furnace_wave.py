"""Animate candidate 02's painted pieces; no replacement artwork is drawn.

The selected concept is a perspective sheet. We extract its full-reach pose,
restore a circular ground plane, and animate separate painted components in a
small native bank. Release fragments are exact subdivisions of these pixels.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree as ET

import numpy as np
from PIL import Image

from build_art_assets import ROOT, compile_bank
from animation_atlas import validate_animation_archive

BANK = "nw_furnace_wave"
FPS = 30
LEVELS = 8
TEXTURE_SCALE = .5
OUT = ROOT / "assets_src/disassembler_wave_v2_complete_20261110"
SELECTED = ROOT / "assets_src/disassembler_wave_redesign_20261110/originals/20261110T125727Z_f4460713/image-2.png"
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")


def clamp(value, low=0.0, high=1.0):
    return min(high, max(low, value))


def smooth(value):
    value = clamp(value)
    return value * value * (3 - 2 * value)


@dataclass
class Piece:
    key: str
    image: Image.Image
    x: float
    y: float
    kind: str
    index: int
    parent: int = -1


def components(alpha):
    """Eight-connected opaque islands, keeping the original edge alpha."""
    seen = alpha <= 8
    height, width = alpha.shape
    result = []
    for sy, sx in zip(*np.nonzero(~seen)):
        if seen[sy, sx]:
            continue
        pending = [(int(sx), int(sy))]
        seen[sy, sx] = True
        points = []
        while pending:
            x, y = pending.pop()
            points.append((x, y))
            for yy in range(max(0, y - 1), min(height, y + 2)):
                for xx in range(max(0, x - 1), min(width, x + 2)):
                    if not seen[yy, xx]:
                        seen[yy, xx] = True
                        pending.append((xx, yy))
        if len(points) >= 20:
            result.append(points)
    return sorted(result, key=lambda item: (-len(item), min(y for x, y in item), min(x for x, y in item)))


def extract():
    source = Image.open(SELECTED).convert("RGBA")
    # The user chose candidate 02; its lower-left is the full-reach key pose.
    pose = source.crop((0, 512, 768, 1024))
    pixels = np.array(pose)
    alpha = pixels[:, :, 3]
    ys, xs = np.nonzero(alpha >= 16)
    bounds = (int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1))
    cx = (bounds[0] + bounds[2]) / 2
    cy = (bounds[1] + bounds[3]) / 2
    inverse_projection = (bounds[2] - bounds[0]) / (bounds[3] - bounds[1])
    # Normalize the farthest painted point, not the rectangular canvas. This
    # keeps the visible perimeter inside the gameplay radius of 4 * 150 px.
    radius = np.sqrt((xs - cx) ** 2 + ((ys - cy) * inverse_projection) ** 2).max()
    scale = 590 / radius
    pieces = []
    for index, points in enumerate(components(alpha)):
        px, py = np.array(points).T
        x0, x1, y0, y1 = int(px.min()), int(px.max() + 1), int(py.min()), int(py.max() + 1)
        cutout = np.zeros((y1 - y0, x1 - x0, 4), dtype=np.uint8)
        cutout[py - y0, px - x0] = pixels[py, px]
        image = Image.fromarray(cutout)
        image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * inverse_projection * scale))), Image.Resampling.LANCZOS)
        x, y = ((x0 + x1) / 2 - cx) * scale, ((y0 + y1) / 2 - cy) * inverse_projection * scale
        # The seven largest islands are the selected design's broad arcs;
        # its bright diamond glyphs remain whole, with their own turning motion.
        kind = "arc" if index < 7 else "crystal" if math.hypot(x, y) > 390 else "rune"
        pieces.append(Piece(f"{kind}_{index:02}", image, x, y, kind, index))
    return pieces, {"pose_crop": [0, 512, 768, 1024], "alpha_bounds": bounds,
                    "source_center": [cx, cy], "inverse_projection": inverse_projection,
                    "pixel_scale": scale, "farthest_painted_radius": 590}


def split_arc(piece):
    """Partition painted pixels along irregular seams without painting new art."""
    arr = np.array(piece.image)
    yy, xx = np.mgrid[:arr.shape[0], :arr.shape[1]]
    world_x, world_y = xx - piece.image.width / 2 + piece.x, yy - piece.image.height / 2 + piece.y
    base_angle = math.atan2(piece.y, piece.x)
    angles = (np.arctan2(world_y, world_x) - base_angle + math.pi) % math.tau - math.pi
    radius = np.hypot(world_x, world_y)
    # A small nonuniform bend breaks the ruler-straight radial cuts. Each arc
    # gets a different seam rhythm; these masks only select existing pixels.
    angles = angles + .026 * np.sin(radius * .056 + piece.index * 1.71) + .012 * np.sin(radius * .153 + piece.index)
    active = arr[:, :, 3] > 0
    low, high = float(angles[active].min()), float(angles[active].max())
    count = 4 + piece.index % 3
    weights = np.array([.68 + .62 * (.5 + .5 * math.sin(piece.index * 1.71 + i * 2.39)) for i in range(count)])
    cuts = np.cumsum(weights / weights.sum())[:-1]
    bins = np.searchsorted(cuts, (angles - low) / max(.001, high - low))
    fragments = []
    for index in range(count):
        mask = active & (bins == index)
        y, x = np.nonzero(mask)
        if len(x) == 0:
            continue
        x0, x1, y0, y1 = int(x.min()), int(x.max() + 1), int(y.min()), int(y.max() + 1)
        cutout = arr.copy()
        cutout[:, :, 3] *= mask
        image = Image.fromarray(cutout[y0:y1, x0:x1])
        fragments.append(Piece(f"scrap_{piece.index:02}_{index}", image,
                               piece.x + (x0 + x1 - piece.image.width) / 2,
                               piece.y + (y0 + y1 - piece.image.height) / 2,
                               "scrap", piece.index * 8 + index, piece.index))
    return fragments


class WaveBank:
    def __init__(self):
        self.build = ET.Element("Build", name=BANK)
        self.animations = ET.Element("Anims")
        self.images = {}
        self.pieces, self.registration = extract()
        self.fragments = [fragment for piece in self.pieces if piece.kind == "arc" for fragment in split_arc(piece)]
        self.paintings = {piece.key: piece for piece in self.pieces + self.fragments}
        self.clips = {}
        for piece in self.pieces + self.fragments:
            symbol = ET.SubElement(self.build, "Symbol", name=piece.key)
            for level in range(LEVELS):
                name = f"{piece.key}_{level:02}"
                image = piece.image.copy()
                image.putalpha(image.getchannel("A").point(lambda value: round(value * (level + 1) / LEVELS)))
                # Separate texture resolution from animation coordinates. At
                # world display scale this is ample, and keeps the build below
                # DST's two-atlas sampling limit even with opacity variants.
                image = image.resize((max(1, round(image.width * TEXTURE_SCALE)),
                                      max(1, round(image.height * TEXTURE_SCALE))), Image.Resampling.LANCZOS)
                self.images[name] = image
                ET.SubElement(symbol, "Frame", framenum=str(level), duration="1", image=name,
                              x="0", y="0", w=str(image.width), h=str(image.height))

    def layer(self, piece, x=None, y=None, angle=0, sx=1, sy=1, opacity=1):
        if opacity <= .015:
            return None
        return (piece.key, piece.x if x is None else x, piece.y if y is None else y,
                angle, max(.005, sx), max(.005, sy), min(LEVELS - 1, max(0, round(opacity * LEVELS) - 1)))

    def grow(self, t):
        pose = []
        for piece in self.pieces:
            phase = piece.index * 1.731
            # All motion converges exactly on the original selected painting.
            # Each arc has its own angular path and changing local aspect.
            twist = (1 - smooth(t)) * (.34 + .13 * math.sin(phase))
            a = math.atan2(piece.y, piece.x) + twist
            r = math.hypot(piece.x, piece.y) * t
            opacity = smooth(t / .16)
            local_angle = (1 - smooth(t)) * (-.40 + .19 * math.sin(phase))
            stretch = t * (.64 + .36 * smooth(t))
            breadth = t * (1.18 - .18 * smooth(t))
            if piece.kind == "rune":
                opacity *= smooth((t - .28 - .08 * math.sin(phase)) / .4)
                local_angle *= .5
            elif piece.kind == "crystal":
                local_angle += .35 * math.sin(math.pi * t) * math.sin(phase)
                stretch *= 1 - .24 * math.sin(math.pi * t) ** 2
                opacity *= smooth((t - .06) / .25)
            pose.append(self.layer(piece, r * math.cos(a), r * math.sin(a), local_angle,
                                   stretch, breadth, opacity))
        return pose

    def idle(self, t):
        pose = []
        wave = math.sin(math.tau * t)
        for piece in self.pieces:
            phase = piece.index * 1.731
            # These local offsets return to zero at the seam. No wholesale
            # spinning/scaling disc, and the outer gameplay boundary stays put.
            drift = .032 * wave * math.sin(phase)
            a = math.atan2(piece.y, piece.x) + drift
            r = math.hypot(piece.x, piece.y) + 3 * wave * math.cos(phase)
            angle = .045 * wave * math.cos(phase)
            opacity = 1
            if piece.kind == "rune":
                opacity = 1 - .4 * math.sin(math.pi * t) ** 2 * (.6 + .4 * math.sin(phase) ** 2)
            elif piece.kind == "crystal":
                angle += .12 * wave
                opacity = 1 - .18 * math.sin(math.pi * t) ** 2
            pose.append(self.layer(piece, r * math.cos(a), r * math.sin(a), angle,
                                   1 + .025 * wave * math.sin(phase), 1, opacity))
        return pose

    def release(self, t):
        if t == 0:
            return [self.layer(piece) for piece in self.pieces]
        pose = []
        for piece in [p for p in self.pieces if p.kind != "arc"] + self.fragments:
            phase = piece.index * 1.731
            # The front gold arc breaks first; neighbouring arcs follow with
            # separate timing. Let the gaps open before the main fade begins.
            delay = 0 if piece.parent == 4 else .05 + .16 * (.5 + .5 * math.sin(piece.parent * 1.71))
            breakup = smooth((t - delay) / (.78 - delay))
            fade_start = .28 + delay * .3
            fade = 1 - smooth((t - fade_start) / (1 - fade_start))
            a = math.atan2(piece.y, piece.x)
            drift = 28 * breakup * math.sin(phase)
            x = piece.x - math.sin(a) * drift
            y = piece.y + math.cos(a) * drift
            # Split in place; no shrinking ring or expanding radius at the end.
            angle = .42 * breakup * math.cos(phase)
            local_scale = 1 - .38 * breakup
            if piece.kind == "rune":
                fade = 1 - smooth(t / .65)
            pose.append(self.layer(piece, x, y, angle, local_scale, local_scale, fade))
        return pose

    def clip(self, name, count, callback, loop=False):
        animation = ET.SubElement(self.animations, "anim", name=name, root=BANK, framerate=str(FPS))
        self.clips[name] = {"frames": count, "fps": FPS, "seconds": count / FPS, "loop": loop}
        for index in range(count):
            t = index / (count if loop else count - 1)
            pose = [item for item in callback(t) if item is not None]
            output = ET.SubElement(animation, "frame")
            corners = []
            for z, (key, x, y, angle, sx, sy, opacity) in enumerate(pose):
                a, b, c, d = math.cos(angle) * sx, math.sin(angle) * sx, -math.sin(angle) * sy, math.cos(angle) * sy
                image = self.paintings[key].image
                texture = self.images[f"{key}_{opacity:02}"]
                texture_x, texture_y = image.width / texture.width, image.height / texture.height
                corners.extend((x + a * px + c * py, y + b * px + d * py)
                               for px in (-image.width / 2, image.width / 2)
                               for py in (-image.height / 2, image.height / 2))
                ET.SubElement(output, "element", name=key, frame=str(opacity), layername=key,
                              z_index=str(z), m_a=str(a * texture_x), m_b=str(b * texture_x),
                              m_c=str(c * texture_y), m_d=str(d * texture_y),
                              m_tx=str(x), m_ty=str(y))
            if not corners:
                corners = [(-1, -1), (1, 1)]
            xs, ys = zip(*corners)
            output.attrib.update(x=str((min(xs) + max(xs)) / 2), y=str((min(ys) + max(ys)) / 2),
                                 w=str(max(xs) - min(xs) + 2), h=str(max(ys) - min(ys) + 2))

    def save_sources(self):
        OUT.mkdir(parents=True, exist_ok=True)
        parts = OUT / "parts"
        parts.mkdir(exist_ok=True)
        for piece in self.pieces + self.fragments:
            piece.image.save(parts / f"{piece.key}.png")
        manifest = {"bank": BANK, "selected_candidate": 2, "source": SELECTED.relative_to(ROOT).as_posix(),
                    "source_sha256": hashlib.sha256(SELECTED.read_bytes()).hexdigest(),
                    "generation": "No new generation: selected prompt-generated pixels retained; mechanical extraction and native component animation.",
                    "source_prompt": "assets_src/disassembler_wave_redesign_20261110/prompt.txt",
                    "registration": self.registration, "orientation": "OnGround", "pixels_per_world_unit": 150,
                    "gameplay_radius": 4, "opacity_levels": LEVELS,
                    "texture_resolution_scale": TEXTURE_SCALE,
                    "clips": self.clips,
                    "pieces": [{"key": p.key, "kind": p.kind, "xy": [p.x, p.y], "size": p.image.size,
                                "parent": p.parent} for p in self.pieces + self.fragments]}
        (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
        board = Image.new("RGBA", (1200, 1200), (114, 119, 112, 255))
        for piece in self.pieces:
            board.alpha_composite(piece.image, (round(600 + piece.x - piece.image.width / 2), round(600 + piece.y - piece.image.height / 2)))
        board.convert("RGB").save(OUT / "restored_ground_plane.png")
        return manifest


def build_bank():
    bank = WaveBank()
    bank.clip("grow", 60, bank.grow)
    bank.clip("loop", 60, bank.idle, loop=True)
    bank.clip("release", 18, bank.release)
    return bank


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", type=Path, default=MOD_TOOLS)
    parser.add_argument("--no-compile", action="store_true")
    args = parser.parse_args()
    bank = build_bank()
    manifest = bank.save_sources()
    if not args.no_compile:
        compile_bank(BANK, bank.build, bank.animations, bank.images, args.tools)
        # Keep one page: Klei's legacy packer can misplace UVs on a smaller
        # second page. The exact compiled symbols are decoded in regression QA.
        manifest["archive_validation"] = validate_animation_archive(ROOT / "mod/anim" / f"{BANK}.zip", max_pages=1)
        archive = ROOT / "mod/anim" / f"{BANK}.zip"
        manifest["archive_bytes"] = archive.stat().st_size
        manifest["archive_sha256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
        (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf8")
    print(json.dumps({"bank": BANK, "pieces": len(bank.pieces), "fragments": len(bank.fragments),
                      "clips": bank.clips, "output": str(OUT)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
