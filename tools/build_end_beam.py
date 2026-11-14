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
from beam_texture import TEXTURE_POLICY, retain_archive_mip0

BANK = "nw_end_beam"
SOURCE = ROOT / "assets_src/projectiles/end_beam_v2_20261114/source-01.png"
PREVIEW = ROOT / "docs/previews/end-beam-v2"
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
FRAMES = 16
SLICES = 4
VISUAL_PARTS = 16
PART_RESAMPLE = 2
STRIP_SIZE = (672, 64)


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


def make_bank():
    band, head = prepare_art()
    # Resample the continuous periodic material once, with neighboring cycles
    # supplying the filter footprint at both ends. Resizing each narrow part
    # separately would clamp its edges and change the phase at every joint.
    periodic = Image.new("RGBA", (band.width * 3, band.height))
    for cycle in range(3):
        periodic.paste(band, (cycle * band.width, 0))
    visual_width = band.width * PART_RESAMPLE
    visual_band = periodic.resize((visual_width * 3, band.height), Image.Resampling.LANCZOS).crop(
        (visual_width, 0, visual_width * 2, band.height))
    build = ET.Element("Build", name=BANK)
    animations = ET.Element("Anims")
    images = {"head": head}
    frame(build, "head", "head", head.size)
    slice_width = band.width // SLICES
    for piece in range(SLICES):
        clip = ET.SubElement(animations, "anim", name=f"beam_{piece}", root=BANK, framerate="30")
        parts = [ET.SubElement(animations, "anim", name=f"beam_{piece}_part_{part}", root=BANK, framerate="30")
                 for part in range(VISUAL_PARTS)]
        for index in range(FRAMES):
            shifted = ImageChops.offset(band, round(index*band.width/FRAMES), 0)
            visual_shifted = ImageChops.offset(visual_band, round(index*band.width/FRAMES) * PART_RESAMPLE, 0)
            image = shifted.crop((piece*slice_width, 0, (piece+1)*slice_width, band.height))
            key = f"beam_{piece}_{index}"
            images[key] = image
            frame(build, key, key, image.size)
            pose = ET.SubElement(clip, "frame", x="0", y="0", w="300", h="64")
            ET.SubElement(pose, "element", name=key, frame="0", layername="beam", z_index="0",
                          m_a=str(300/image.width), m_b="0", m_c="0", m_d="1", m_tx="0", m_ty="0")
            # Every part has the same 21px density and exact 18.75 native
            # length; the original 168px slice cannot divide evenly into 16.
            part_width = slice_width * PART_RESAMPLE // VISUAL_PARTS
            part_native_length = 300 / VISUAL_PARTS
            for part, part_clip in enumerate(parts):
                part_key = f"beam_{piece}_part_{part}_{index}"
                left = piece * slice_width * PART_RESAMPLE + part * part_width
                part_image = visual_shifted.crop((left, 0, left + part_width, band.height))
                images[part_key] = part_image
                frame(build, part_key, part_key, part_image.size)
                pose = ET.SubElement(part_clip, "frame", x="0", y="0", w=str(part_native_length), h="64")
                ET.SubElement(pose, "element", name=part_key, frame="0", layername="beam", z_index="0",
                              m_a=str(part_native_length / part_width), m_b="0", m_c="0", m_d="1", m_tx="0", m_ty="0")
    clip = ET.SubElement(animations, "anim", name="head", root=BANK, framerate="30")
    for index in range(FRAMES):
        pulse = 1 + .035*math.sin(index*math.tau/FRAMES)
        pose = ET.SubElement(clip, "frame", x="0", y="0", w="140", h="96")
        ET.SubElement(pose, "element", name="head", frame="0", layername="head", z_index="0",
                      m_a=str(pulse), m_b="0", m_c="0", m_d=str(pulse), m_tx="0", m_ty="0")
    manifest = {"bank": BANK, "source": str(SOURCE.relative_to(ROOT)),
                "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                "frames": FRAMES, "fps": 30, "slices": SLICES,
                "visual_parts_per_slice": VISUAL_PARTS,
                "visual_part_pixels": [slice_width * PART_RESAMPLE // VISUAL_PARTS, band.height],
                "visual_horizontal_resample": PART_RESAMPLE,
                "visual_part_native_length": 300 / VISUAL_PARTS,
                "beam_world_length": 2, "beam_world_width": 64/150,
                "head_world_width": 90/150, "direction": "+X",
                "unused_source_component": "bottom terminal starburst (preserved for future art work)",
                "texture_sampling": TEXTURE_POLICY}
    return build, animations, images, manifest


def preview(images, manifest):
    PREVIEW.mkdir(parents=True, exist_ok=True)
    frames = []
    for index in range(FRAMES):
        scene = Image.new("RGBA", (1000, 280), "#353d37")
        draw = ImageDraw.Draw(scene)
        draw.text((24, 18), "END BEAM / painted core and forward-flowing violet energy", fill="#ede1cc")
        draw.text((24, 246), "Runtime material preview - not an in-game screenshot", fill="#b8bcb5")
        for part in range(12):
            # The renderer stretches consecutive material slices over each
            # confirmed span. This preview uses the same clip frame sequence.
            sprite = images[f"beam_{part%SLICES}_{index}"].resize((70, 38), Image.Resampling.LANCZOS)
            scene.alpha_composite(sprite, (34+part*70, 124))
        head = images["head"].resize((84, 57), Image.Resampling.LANCZOS)
        scene.alpha_composite(head, (832, 115))
        frames.append(scene.convert("RGB"))
    frames[0].save(PREVIEW / "preview.png")
    frames[0].save(PREVIEW / "flow.gif", save_all=True, append_images=frames[1:],
                   duration=[33, 33, 34, 33]*4, loop=0, disposal=2)
    board = Image.new("RGB", (1000, 280*3), "#353d37")
    for row, index in enumerate((0, 5, 10)):
        board.paste(frames[index], (0, row*280))
    board.save(PREVIEW / "frames.png")
    (PREVIEW / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--no-preview", action="store_true", help="rebuild runtime assets without overwriting preview artifacts")
    args = parser.parse_args()
    build, animations, images, manifest = make_bank()
    if not args.prepare_only:
        compile_bank(BANK, build, animations, images, MOD_TOOLS)
        manifest["texture_packaging"] = retain_archive_mip0(ROOT / f"mod/anim/{BANK}.zip")
    if not args.no_preview:
        preview(images, manifest)
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
