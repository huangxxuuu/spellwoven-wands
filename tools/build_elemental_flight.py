"""Build painted spell flight animations from transparent atlases and strips.

Rows 1-2 contain six looping heads; row 3 contains three detached tail poses;
row 4 contains three contact poses. All sprites point along local +X. Each
animation group uses one authored pivot, even when its painted bounds change.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image

from build_art_assets import ROOT, RUNTIME, compile_bank, frame

BANK = "nw_elemental_flight"
SOURCE = ROOT / "assets_src/projectiles/elemental_v1"
BASIC_SOURCE = ROOT / "assets_src/projectiles/basic_v1"
SPECIAL_SOURCE = ROOT / "assets_src/projectiles/special_v1"
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
FPS = 30
DIRECTIONS = 32
DIRECTION_COUNTS = {"land_hook": 64, "arrow": 128, "flint_lance": 128, "end_beam": 128}
FRAMES = 6
GROUPS = {
    "head": {"cells": (0, 1, 2, 3, 4, 5), "frames": (0, 1, 2, 3, 4, 5),
             "pixels": 96, "alpha": (1, 1, 1, 1, 1, 1)},
    "tail": {"cells": (6, 7, 8), "frames": (0, 0, 1, 1, 2, 2),
             "pixels": 64, "alpha": (1, .9, .76, .56, .32, .12)},
    "hit": {"cells": (9, 10, 11), "frames": (0, 0, 1, 1, 2, 2),
            "pixels": 96, "alpha": (1, .96, .84, .64, .4, .16)},
}
# The hook shares its head canvas with a long rope. Keep enough source pixels
# for the small iron head to remain readable when the projectile is enlarged.
PIXEL_SIZES = {"land_hook": {"head": 256}}
DISPLAY_SIZES = {
    "fire": {"head": (135, 110), "tail": (60, 45), "hit": (150, 125)},
    "frost": {"head": (130, 100), "tail": (54, 45), "hit": (150, 125)},
    "arrow": {"head": (150, 125), "tail": (80, 70), "hit": (100, 80)},
    "heavy": {"head": (175, 175), "tail": (165, 220), "hit": (180, 160)},
    "scatter": {"head": (55, 55), "tail": (42, 36), "hit": (55, 45)},
    "gust": {"head": (200, 180), "tail": (90, 90), "hit": (130, 110)},
    "slime": {"head": (255, 225), "tail": (67.5, 67.5), "hit": (165, 150)},
    "heal_bolt": {"head": (185, 170), "tail": (100, 130), "hit": (120, 110)},
    "flint_lance": {"head": (180, 105), "tail": (52, 80), "hit": (110, 95)},
    "grow_orb": {"head": (170, 170), "tail": (95, 120), "hit": (140, 140)},
    "star_vortex": {"head": (110, 110), "tail": (55, 60), "hit": (90, 90)},
    "glass_disc": {"head": (130, 130), "tail": (85, 135), "hit": (110, 110)},
    "tri_electric": {"head": (165, 165), "tail": (90, 97.5), "hit": (165, 165)},
    "end_beam": {"head": (245, 145), "tail": (110, 110), "hit": (140, 110)},
    "spore_ball": {"head": (170, 170), "tail": (65, 65), "hit": (140, 120)},
    "land_hook": {"head": (560, 532), "tail": (63, 56), "hit": (133, 112)},
    "soundwave": {"head": (195, 195), "tail": (120, 150), "hit": (210, 210)},
    "bee_swarm": {"head": (110, 115), "tail": (32, 25), "hit": (65, 65)},
    # Base size matches 80% of the previous single-giant (2.5x) appearance.
    "fireflies": {"head": (150, 130), "tail": (36, 36), "hit": (130, 130)},
}
ORIENTATION_RULES = {
    "bee_swarm": {"head": "upright_left"},
    "fireflies": {"head": "upright_left"},
}
# Tail-only revision strips preserve every approved head and contact pose.
# Their three ages share a fixed authored anchor and one crop/scale.
TAIL_STRIPS = {
    "arrow": {"file": "arrow-tail-v2.png", "pivot": (.5, .5)},
    "heavy": {"file": "heavy-tail-v2.png", "pivot": (.5, .5)},
    "flint_lance": {"file": "flint_lance-tail-v2.png", "pivot": (.5, 365 / 724)},
}
# Electric arcs change their attachment sites over a longer body-only loop.
# Detached trails and contacts retain their independent six-frame timeline.
HEAD_OVERRIDES = {
    "tri_electric": {"file": "tri_electric-head-v2.png", "columns": 3, "rows": 4,
                     "pivot": (182 / 362, 195 / 362),
                     # Measure the round ink shell, not the changing arc/glow.
                     "source_pivots": ((182 / 362, 195 / 362),) * 6
                                      + ((182 / 362, 196 / 362),) * 3
                                      + ((182 / 362, 195 / 362),) * 3},
}
# Small scatter fragments need to remain visible while a new fragment is born.
OPACITY_FRAMES = {"scatter": {"tail": (1, .98, .90, .78, .65, .28)}}
# Shared pivots measured from the generated atlases (296 x 444 nominal cells).
# Their cores are deliberately anchored rather than the empty cell centre.
PIVOTS = {
    "fire": {"head": (.5, 299 / 444), "tail": (.5, 210 / 444), "hit": (.5, 215 / 444)},
    "frost": {"head": (.5, 237 / 444), "tail": (.5, 221 / 444), "hit": (.5, 215 / 444)},
    "arrow": {"head": (.5, 254 / 444), "tail": (.5, 220 / 444), "hit": (.5, 220 / 444)},
    "heavy": {"head": (.5, 264 / 444), "tail": (.5, 225 / 444), "hit": (.5, 216 / 444)},
    "scatter": {"head": (.5, 225 / 444), "tail": (.5, 217 / 444), "hit": (.5, 218 / 444)},
    # The special sheets use 362 px cells. Anchor the front core instead of
    # letting a long painted rear wisp move the projectile's rotation centre.
    "gust": {"head": (250 / 362, 200 / 362)},
    "slime": {"head": (250 / 362, 183 / 362)},
    "spore_ball": {"head": (227 / 362, 188 / 362)},
    "flint_lance": {"head": (.5, 196 / 362)},
    "grow_orb": {"head": (235 / 362, 199 / 362)},
    "heal_bolt": {"head": (255 / 362, 199 / 362)},
    "star_vortex": {"head": (242 / 362, 193 / 362)},
    "glass_disc": {"head": (.5, 198 / 362), "tail": (.5, 170 / 362)},
    "tri_electric": {"head": (148 / 362, 190 / 362)},
    "end_beam": {"head": (270 / 362, 200 / 362)},
    "soundwave": {"head": (167 / 362, 208 / 362)},
    "bee_swarm": {"head": (200 / 362, 190 / 362)},
    "fireflies": {"head": (240 / 362, 199 / 362)},
    # This revision is a wide 1898 x 829 atlas with 633 x 207 nominal cells.
    "land_hook": {"head": (487 / 633, 114 / 207)},
}
# The generated arrow's second row places the shaft 36 source pixels higher.
# Register its authored shaft axes explicitly before applying one shared crop.
# These are source pivots, not independently calculated alpha-box centres.
SOURCE_FRAME_PIVOTS = {
    "arrow": {"head": ((.5, 254 / 444),) * 3 + ((.5, 218 / 444),) * 3},
    # Register the same measured shaft axis across both atlas rows/columns.
    "flint_lance": {"head": tuple((x / 362, y / 362) for y in (196, 191)
                                    for x in (189, 182, 176))},
    "slime": {"head": tuple((x / 362, 183 / 362) for x in (250, 252, 258, 262, 251, 249))},
    "star_vortex": {"head": tuple((x / 362, y / 362) for x, y in (
        (242, 193), (231, 191), (215, 193), (240, 185), (232, 182), (217, 182)))},
    "glass_disc": {"head": tuple((x / 362, y / 362) for y in (198, 184)
                                   for x in (189, 182, 175))},
    "end_beam": {"head": tuple((x / 362, 200 / 362) for x in (270, 254, 240)) * 2},
    "soundwave": {"head": tuple((x / 362, 208 / 362) for x in (167, 157, 147)) * 2},
    "fireflies": {"head": tuple((x / 362, y / 362) for y in (199, 200)
                                  for x in (240, 232, 223))},
    "bee_swarm": {"head": ((200 / 362, 190 / 362),) * 6},
    "land_hook": {"head": ((487 / 633, 114 / 207),) * 3 + ((487 / 633, 120 / 207),) * 3},
}


def atlas_cells(path: Path) -> list[Image.Image]:
    """Split exact grid boundaries without per-frame auto-cropping."""
    return grid_cells(path, 3, 4)


def grid_cells(path: Path, columns: int, rows: int) -> list[Image.Image]:
    """Read a transparent grid with the same fixed cell axes for every pose."""
    with Image.open(path) as source:
        if "A" not in source.getbands():
            raise ValueError(f"{path}: expected a transparent RGBA atlas")
        atlas = source.convert("RGBA")
    if atlas.getchannel("A").getextrema()[0] != 0:
        raise ValueError(f"{path}: atlas has no fully transparent background")
    width, height = atlas.size
    cell_size = (round(width / columns), round(height / rows))
    result = []
    for row in range(rows):
        for col in range(columns):
            bounds = (round(col * width / columns), round(row * height / rows),
                      round((col + 1) * width / columns), round((row + 1) * height / rows))
            cell = atlas.crop(bounds)
            if cell.size != cell_size:
                cell = cell.resize(cell_size, Image.Resampling.LANCZOS)
            cell.putalpha(cell.getchannel("A").point(lambda a: 0 if a <= 8 else a))
            if not cell.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox():
                raise ValueError(f"{path}: empty cell at row {row + 1}, column {col + 1}")
            result.append(cell)
    return result


def normalize_group(cells: list[Image.Image], pixels: int,
                    pivot: tuple[float, float] = (.5, .5)) -> tuple[list[Image.Image], tuple]:
    """Fit one shared, symmetric crop to the output; never recenter a pose.

    The pivot is a fraction of the source cell width and height. Symmetry
    around this shared point preserves the artist's anchor for every pose.
    All frames use the same crop, resize and padding, so a changing silhouette
    cannot turn into an artificial translation or per-frame scale change.
    """
    width, height = cells[0].size
    if any(cell.size != (width, height) for cell in cells):
        raise ValueError("Atlas cells must have the same dimensions")
    boxes = [cell.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
             for cell in cells]
    if any(box is None for box in boxes):
        raise ValueError("An animation group contains an empty pose")
    px, py = round(width * pivot[0]), round(height * pivot[1])
    half_width = math.ceil(max(max(px - box[0], box[2] - px) for box in boxes))
    half_height = math.ceil(max(max(py - box[1], box[3] - py) for box in boxes))
    # Include a tiny source gutter for resampling; preserve weak alpha inside it.
    half_width += 2
    half_height += 2
    left = px - half_width
    top = py - half_height
    bounds = (left, top, left + 2 * half_width, top + 2 * half_height)
    scale = (pixels - 6) / max(2 * half_width, 2 * half_height)
    size = (max(1, round(2 * half_width * scale)), max(1, round(2 * half_height * scale)))
    result = []
    for cell in cells:
        sprite = cell.crop(bounds).resize(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (pixels, pixels))
        canvas.alpha_composite(sprite, ((pixels - size[0]) // 2, (pixels - size[1]) // 2))
        canvas.putalpha(canvas.getchannel("A").point(lambda a: 0 if a <= 8 else a))
        result.append(canvas)
    return result, bounds


def register_group(cells: list[Image.Image], pivot: tuple[float, float],
                   source_pivots: tuple[tuple[float, float], ...]) -> list[Image.Image]:
    """Align authored frame axes without rescaling or recentering silhouettes."""
    if len(cells) != len(source_pivots):
        raise ValueError("Every registered pose needs an authored source pivot")
    result = []
    for cell, source_pivot in zip(cells, source_pivots):
        width, height = cell.size
        dx = round(width * pivot[0]) - round(width * source_pivot[0])
        dy = round(height * pivot[1]) - round(height * source_pivot[1])
        left, top, right, bottom = cell.getchannel("A").getbbox()
        if left + dx < 0 or top + dy < 0 or right + dx > width or bottom + dy > height:
            raise ValueError("Authored frame registration would crop painted pixels")
        aligned = Image.new("RGBA", cell.size)
        aligned.alpha_composite(cell, (dx, dy))
        result.append(aligned)
    return result


def clip_name(element: str, group: str, direction: int) -> str:
    suffix = "" if group == "head" else f"_{group}"
    return f"{element}{suffix}_dir_{direction}"


def directions_for(element: str) -> int:
    return DIRECTION_COUNTS.get(element, DIRECTIONS)


def direction_transform(element: str, group: str, direction: int) -> tuple[float, float, float, float]:
    """Return the exact source-to-animation matrix (a, b, c, d).

    Left-facing insects mirror horizontally and then lean within 90 degrees
    of upright. Algebraically this flips local Y before the usual rotation.
    Ignore floating-point cosine noise at the two vertical directions.
    """
    width, height = DISPLAY_SIZES[element][group]
    pixels = PIXEL_SIZES.get(element, {}).get(group, GROUPS[group]["pixels"])
    angle = direction * math.tau / directions_for(element)
    cosine, sine = math.cos(angle), math.sin(angle)
    a, b = cosine * width / pixels, sine * width / pixels
    c, d = -sine * height / pixels, cosine * height / pixels
    if ORIENTATION_RULES.get(element, {}).get(group) == "upright_left" and cosine < -1e-9:
        c, d = -c, -d
    return a, b, c, d


def source_folder(element: str, source: Path = SOURCE, basic_source: Path = BASIC_SOURCE,
                  special_source: Path = SPECIAL_SOURCE) -> Path:
    if element in ("fire", "frost"):
        return source
    if element in ("arrow", "heavy", "scatter"):
        return basic_source
    return special_source


def make_bank(source: Path = SOURCE, basic_source: Path = BASIC_SOURCE,
              special_source: Path = SPECIAL_SOURCE):
    build = ET.Element("Build", name=BANK)
    animations = ET.Element("Anims")
    images: dict[str, Image.Image] = {}
    manifest = {"bank": BANK, "fps": FPS, "frames": FRAMES, "directions": DIRECTIONS,
                "directions_by_kind": {kind: directions_for(kind) for kind in DISPLAY_SIZES},
                "orientation_rules": ORIENTATION_RULES,
                "source_layout": "3 columns x 4 rows: head/head/tail/hit",
                "frames_by_kind": {}, "sources": {}}
    for element, sizes in DISPLAY_SIZES.items():
        folder = source_folder(element, source, basic_source, special_source)
        path = folder / f"{element}-atlas.png"
        cells = atlas_cells(path)
        manifest["sources"][element] = {
            "path": path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "groups": {},
        }
        manifest["frames_by_kind"][element] = {}
        for group, config in GROUPS.items():
            pixels = PIXEL_SIZES.get(element, {}).get(group, config["pixels"])
            pivot = PIVOTS.get(element, {}).get(group, (.5, .5))
            poses = [cells[i] for i in config["cells"]]
            frame_indices = config["frames"]
            source_pivots = SOURCE_FRAME_PIVOTS.get(element, {}).get(group)
            strip = TAIL_STRIPS.get(element) if group == "tail" else None
            strip_path = folder / strip["file"] if strip else None
            if strip_path and strip_path.is_file():
                poses = grid_cells(strip_path, 3, 1)
                pivot = strip["pivot"]
                source_pivots = strip.get("source_pivots")
            head_override = HEAD_OVERRIDES.get(element) if group == "head" else None
            head_path = folder / head_override["file"] if head_override else None
            if head_path:
                poses = grid_cells(head_path, head_override["columns"], head_override["rows"])
                pivot = head_override["pivot"]
                source_pivots = head_override.get("source_pivots")
                frame_indices = tuple(range(len(poses)))
            if source_pivots:
                poses = register_group(poses, pivot, source_pivots)
            normalized, bounds = normalize_group(poses, pixels, pivot)
            manifest["sources"][element]["groups"][group] = {
                "source_crop": bounds, "source_pivot_fraction": pivot,
                "pixels": [pixels, pixels], "display_size": sizes[group],
                "frames": len(frame_indices), "period": len(frame_indices) / FPS,
            }
            manifest["frames_by_kind"][element][group] = len(frame_indices)
            if source_pivots:
                manifest["sources"][element]["groups"][group]["source_frame_pivot_fractions"] = source_pivots
            if strip_path and strip_path.is_file():
                manifest["sources"][element]["groups"][group]["override"] = {
                    "path": strip_path.relative_to(ROOT).as_posix() if strip_path.is_relative_to(ROOT) else str(strip_path),
                    "sha256": hashlib.sha256(strip_path.read_bytes()).hexdigest(),
                    "layout": "3 columns x 1 row: fresh/middle/old",
                }
            if head_path:
                manifest["sources"][element]["groups"][group]["override"] = {
                    "path": head_path.relative_to(ROOT).as_posix() if head_path.is_relative_to(ROOT) else str(head_path),
                    "sha256": hashlib.sha256(head_path.read_bytes()).hexdigest(),
                    "layout": f"{head_override['columns']} columns x {head_override['rows']} rows: head loop",
                }
            alpha = OPACITY_FRAMES.get(element, {}).get(group, config["alpha"])
            if head_override:
                alpha = (1,) * len(frame_indices)
            for index, (source_index, opacity) in enumerate(zip(frame_indices, alpha)):
                image = normalized[source_index].copy()
                if opacity != 1:
                    image.putalpha(image.getchannel("A").point(lambda value: round(value * opacity)))
                key = f"{element}_{group}_{index}"
                images[key] = image
                frame(build, key, key, image.size)
            display_width, display_height = sizes[group]
            directions = directions_for(element)
            for direction in range(directions):
                angle = direction * math.tau / directions
                cosine, sine = math.cos(angle), math.sin(angle)
                a, b, c, d = direction_transform(element, group, direction)
                sequence = ET.SubElement(animations, "anim", name=clip_name(element, group, direction),
                                         root=BANK, framerate=str(FPS))
                for index in range(len(frame_indices)):
                    # Bounds enclose the rotated canvas as well as its alpha.
                    w = abs(cosine) * display_width + abs(sine) * display_height
                    h = abs(sine) * display_width + abs(cosine) * display_height
                    pose = ET.SubElement(sequence, "frame", x="0", y="0", w=str(w + 2), h=str(h + 2))
                    ET.SubElement(pose, "element", name=f"{element}_{group}_{index}", frame="0",
                                  layername=group, z_index="0", m_a=str(a),
                                  m_b=str(b), m_c=str(c), m_d=str(d), m_tx="0", m_ty="0")
    return build, animations, images, manifest


def prepare(build, animations, images, manifest, destination: Path = RUNTIME / BANK):
    destination.mkdir(parents=True, exist_ok=True)
    for key, image in images.items():
        image.save(destination / f"{key}.png")
    ET.ElementTree(build).write(destination / "build.xml", encoding="utf-8", xml_declaration=True)
    ET.ElementTree(animations).write(destination / "animation.xml", encoding="utf-8", xml_declaration=True)
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE, help="Directory containing fire/frost-atlas.png")
    parser.add_argument("--basic-source", type=Path, default=BASIC_SOURCE,
                        help="Directory containing arrow/heavy/scatter-atlas.png")
    parser.add_argument("--special-source", type=Path, default=SPECIAL_SOURCE,
                        help="Directory containing special projectile, soundwave and insect atlases")
    parser.add_argument("--mod-tools", type=Path, default=MOD_TOOLS, help="Don't Starve Mod Tools/mod_tools directory")
    parser.add_argument("--prepare-only", action="store_true", help="Write PNG/XML/manifest without invoking the compiler")
    args = parser.parse_args()
    build, animations, images, manifest = make_bank(
        args.source.resolve(), args.basic_source.resolve(), args.special_source.resolve())
    prepare(build, animations, images, manifest)
    if not args.prepare_only:
        compile_bank(BANK, build, animations, images, args.mod_tools)
    print(f"{BANK}: {len(images)} sprites, {len(animations)} clips at {FPS} fps")
    print(f"Prepared: {RUNTIME / BANK}")
    if not args.prepare_only:
        print(f"Compiled: {ROOT / 'mod/anim' / (BANK + '.zip')}")


if __name__ == "__main__":
    main()
