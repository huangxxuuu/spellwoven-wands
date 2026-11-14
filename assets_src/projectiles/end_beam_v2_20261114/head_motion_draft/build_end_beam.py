"""Compile the card-inspired painted beam into a forward-flowing local material.

The generated source is immutable. Cropping, alpha cleanup and scrolling below
are runtime asset preparation, not a redraw of the supplied art.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageChops, ImageDraw

from build_art_assets import ROOT, compile_bank, frame

BANK = "nw_end_beam"
SOURCE = ROOT / "assets_src/projectiles/end_beam_v2_20261114/source-01.png"
PREVIEW = ROOT / "docs/previews/end-beam-v2"
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
FRAMES = 16
HEAD_FRAMES = 48
SLICES = 4
STRIP_SIZE = (672, 64)
HEAD_WIDTH = 90
# White star core in the authored cutout, relative to its image centre.
HEAD_PIVOT = ((506-329)*132/369-66, (489-354)*90/252-45)


def prepare_art():
    source = Image.open(SOURCE).convert("RGBA")
    # Remove negligible API alpha dust; preserve soft antialiasing and the
    # opaque painted core. Never use transparent RGB as a visible backdrop.
    source.putalpha(source.getchannel("A").point(lambda a: 0 if a <= 2 else min(255, round(a * 255 / 254))))
    band = source.crop((100, 112, 935, 276)).resize((768, 64), Image.Resampling.LANCZOS)
    overlap = 96
    # Crossfade the trailing overlap into the beginning, then trim that first
    # overlap. This makes the material repeat without a hard vertical seam.
    mask = Image.new("L", (overlap, band.height))
    mask.putdata([round(255 * (1 - math.cos(math.pi*x/(overlap-1))) / 2)
                  for _ in range(band.height) for x in range(overlap)])
    seam = Image.composite(band.crop((0, 0, overlap, 64)),
                           band.crop((768-overlap, 0, 768, 64)), mask)
    band.paste(seam, (768-overlap, 0))
    band = band.crop((overlap, 0, 768, 64))
    assert band.size == STRIP_SIZE
    head = source.crop((329, 354, 698, 606)).resize((132, 90), Image.Resampling.LANCZOS)
    # Blend the painted connector into the underlying ribbon. Its original
    # cutout end is not an exposed outline when attached to a continuous beam.
    entrance = Image.new("L", head.size)
    entrance.putdata([min(255, round(255*x/16)) for _ in range(head.height) for x in range(head.width)])
    head.putalpha(ImageChops.multiply(head.getchannel("A"), entrance))
    return band, head


def head_pose(index, head):
    """Turn around the white core and breathe inside the beam's diameter."""
    cycle = index*math.tau/HEAD_FRAMES
    angle = math.radians(22)*math.sin(cycle)
    c, s = math.cos(angle), math.sin(angle)
    px, py = HEAD_PIVOT
    alpha = head.getchannel("A")
    silhouette_y = [s*(x-head.width/2-px)+c*(y-head.height/2-py)
                    for y in range(head.height) for x in range(head.width)
                    if alpha.getpixel((x, y)) > 8]
    # Account for rotating spikes, not just the unrotated canvas. Even the
    # largest breathing pose remains as thick as the connected ribbon.
    height = max(silhouette_y)-min(silhouette_y)+1
    breath = .91+.09*math.cos(cycle)
    scale = HEAD_WIDTH/height*breath
    a, b, c, d = c*scale, s*scale, -s*scale, c*scale
    return a, b, c, d, -a*px-c*py, -b*px-d*py


def head_preview(head, index):
    a, b, c, d, tx, ty = head_pose(index, head)
    determinant = a*d-b*c
    transform = (d/determinant, -c/determinant,
                 (d*(-80-tx)-c*(-65-ty))/determinant+head.width/2,
                 -b/determinant, a/determinant,
                 (-b*(-80-tx)+a*(-65-ty))/determinant+head.height/2)
    return head.transform((160, 130), Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC)


def make_bank():
    band, head = prepare_art()
    build = ET.Element("Build", name=BANK)
    animations = ET.Element("Anims")
    images = {"head": head}
    frame(build, "head", "head", head.size)
    slice_width = band.width // SLICES
    for piece in range(SLICES):
        clip = ET.SubElement(animations, "anim", name=f"beam_{piece}", root=BANK, framerate="30")
        for index in range(FRAMES):
            shifted = ImageChops.offset(band, round(index*band.width/FRAMES), 0)
            image = shifted.crop((piece*slice_width, 0, (piece+1)*slice_width, band.height))
            key = f"beam_{piece}_{index}"
            images[key] = image
            frame(build, key, key, image.size)
            pose = ET.SubElement(clip, "frame", x="0", y="0", w="300", h="64")
            ET.SubElement(pose, "element", name=key, frame="0", layername="beam", z_index="0",
                          m_a=str(300/image.width), m_b="0", m_c="0", m_d="1", m_tx="0", m_ty="0")
    clip = ET.SubElement(animations, "anim", name="head", root=BANK, framerate="30")
    for index in range(HEAD_FRAMES):
        a, b, c, d, tx, ty = head_pose(index, head)
        pose = ET.SubElement(clip, "frame", x="0", y="0", w="160", h="130")
        ET.SubElement(pose, "element", name="head", frame="0", layername="head", z_index="0",
                      m_a=str(a), m_b=str(b), m_c=str(c), m_d=str(d), m_tx=str(tx), m_ty=str(ty))
    manifest = {"bank": BANK, "source": str(SOURCE.relative_to(ROOT)),
                "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                "frames": FRAMES, "fps": 30, "slices": SLICES,
                "beam_world_length": 2, "beam_world_width": 64/150,
                "head_world_width": HEAD_WIDTH/150, "head_frames": HEAD_FRAMES,
                "head_diameter_ratio": [0.82, 1.0], "head_turn_degrees": [-22, 22],
                "direction": "+X",
                "unused_source_component": "bottom terminal starburst (preserved for future art work)"}
    return build, animations, images, manifest


def preview(images, manifest):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    frames = []
    for index in range(HEAD_FRAMES):
        scene = Image.new("RGBA", (1000, 280), "#353d37")
        draw = ImageDraw.Draw(scene)
        draw.text((24, 18), "END BEAM / painted core and forward-flowing violet energy", fill="#ede1cc")
        draw.text((24, 246), "Runtime material preview - not an in-game screenshot", fill="#b8bcb5")
        for part in range(12):
            # The renderer stretches consecutive material slices over each
            # confirmed span. This preview uses the same clip frame sequence.
            sprite = images[f"beam_{part%SLICES}_{index%FRAMES}"].resize((70, 38), Image.Resampling.LANCZOS)
            scene.alpha_composite(sprite, (34+part*70, 124))
        head = head_preview(images["head"], index).resize((68, 55), Image.Resampling.LANCZOS)
        scene.alpha_composite(head, (840, 116))
        frames.append(scene.convert("RGB"))
    frames[0].save(PREVIEW / "preview.png")
    frames[0].save(PREVIEW / "flow.gif", save_all=True, append_images=frames[1:],
                   duration=[33, 33, 34, 33]*12, loop=0, disposal=2)
    board = Image.new("RGB", (1000, 280*3), "#353d37")
    for row, index in enumerate((0, 12, 24)):
        board.paste(frames[index], (0, row*280))
    board.save(PREVIEW / "frames.png")
    (PREVIEW / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    build, animations, images, manifest = make_bank()
    preview(images, manifest)
    if not args.prepare_only:
        compile_bank(BANK, build, animations, images, MOD_TOOLS)
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
