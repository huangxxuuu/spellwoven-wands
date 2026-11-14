"""Register the painted star and continue the beam material beneath it.

No new art is synthesized: the connector reuses the authored ribbon, with a
small geometric taper. Its four 16-frame clips share the beam's exact clock.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageChops, ImageDraw

from build_art_assets import ROOT, compile_bank, frame
from beam_texture import TEXTURE_POLICY, retain_archive_mip0
from native_animation import NativeAnimation, read_animation, read_build, texture
from build_end_beam import prepare_art, SOURCE as BEAM_SOURCE, FRAMES as BEAM_FRAMES, SLICES

BANK = "nw_end_beam_head"
SOURCE = ROOT / "assets_src/projectiles/end_beam_head_v3_20261114"
CONNECTOR_SOURCE = ROOT / "assets_src/projectiles/end_beam_connector_v5_20261114/connector-source-01.png"
PREVIEW = ROOT / "docs/previews/end-beam-aligned-v6"
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
FRAMES = 12
FPS = 30
STAR_SCALE = 1.12
CONNECTOR_HEIGHT = 64
CONNECTOR_LENGTH = 80
CONNECTOR_END_SCALE = .85


def connector_art(band, piece, index):
    """Keep the actual beam edge; taper the continuing painted UV window.

    The first column is deliberately identical, including alpha and vertical
    core position. The white core then gently settles at the star's registered
    centre. There is no separately faded overlap or median-height assumption.
    """
    shifted = ImageChops.offset(band, round(index*band.width/BEAM_FRAMES), 0)
    edge = (piece+1)*(band.width//SLICES)-1
    image = Image.new("RGBA", (CONNECTOR_LENGTH, CONNECTOR_HEIGHT))
    for x in range(CONNECTOR_LENGTH):
        t = x/(CONNECTOR_LENGTH-1)
        easing = t*t*(3-2*t)
        # The beam displays 168 source pixels over 300 native animation units.
        source_x = (edge+round(x*(band.width//SLICES)/300)) % band.width
        column = shifted.crop((source_x, 0, source_x+1, band.height))
        if x == 0:
            image.paste(column, (0, 0))
            continue
        core = [y for y in range(band.height)
                if min(column.getpixel((0,y))[:3]) >= 210 and column.getpixel((0,y))[3] >= 192]
        core_y = (min(core)+max(core)+1)/2 if core else band.height/2
        scale = 1-(1-CONNECTOR_END_SCALE)*easing
        offset = (band.height/2-core_y)*scale*easing
        column = column.transform((1, band.height), Image.Transform.AFFINE,
                                  (1, 0, 0, 0, 1/scale, band.height/2-(band.height/2+offset)/scale),
                                  Image.Resampling.BICUBIC)
        image.paste(column, (x, 0))
    return image


def clean(image):
    image = image.convert("RGBA")
    image.putalpha(image.getchannel("A").point(lambda a: 0 if a <= 2 else min(255, round(a*255/254))))
    return image


def make_bank():
    registration = json.loads((SOURCE / "registration.json").read_text(encoding="utf-8"))
    source_path = SOURCE / registration["source"]
    source = clean(Image.open(source_path))
    poses = registration["frames"]
    assert len(poses) == FRAMES
    # A single source scale preserves authored size changes. Registration
    # translates each white core to the origin, not each asymmetrical bbox.
    radius = 0
    for pose in poses:
        left, top, right, bottom = pose["box"]
        px, py = pose["pivot"]
        for y in range(top, bottom):
            for x in range(left, right):
                if source.getpixel((x, y))[3] > 8:
                    radius = max(radius, math.hypot(x-px, y-py))
    scale = 40/radius
    images = {}
    build, animations = ET.Element("Build", name=BANK), ET.Element("Anims")
    for index, pose in enumerate(poses):
        px, py = pose["pivot"]
        left, top, _, _ = pose["box"]
        cutout = source.crop(pose["box"])
        # Each output comes from a different authored frame. These transforms
        # only register/resample the frames, never synthesize missing poses.
        image = cutout.transform((96, 96), Image.Transform.AFFINE,
                                 (1/scale, 0, px-left-48/scale, 0, 1/scale, py-top-48/scale),
                                 Image.Resampling.BICUBIC)
        key = f"star_{index}"
        images[key] = image
        frame(build, key, key, image.size)
    clip = ET.SubElement(animations, "anim", name="head", root=BANK, framerate=str(FPS))
    for index in range(FRAMES):
        pose = ET.SubElement(clip, "frame", x="0", y="0", w="108", h="108")
        # Rotation is already painted into these twelve poses. Adding a second
        # matrix turn would double the spin and collapse the apparent cycle.
        ET.SubElement(pose, "element", name=f"star_{index}", frame="0", layername="star", z_index="0",
                      m_a=str(STAR_SCALE), m_b="0", m_c="0", m_d=str(STAR_SCALE), m_tx="0", m_ty="0")
    band, _ = prepare_art()
    for piece in range(SLICES):
        clip = ET.SubElement(animations, "anim", name=f"connector_{piece}", root=BANK, framerate=str(FPS))
        for index in range(BEAM_FRAMES):
            key = f"connector_{piece}_{index}"
            images[key] = connector_art(band, piece, index)
            frame(build, key, key, images[key].size)
            pose = ET.SubElement(clip, "frame", x="0", y="0", w=str(CONNECTOR_LENGTH), h=str(CONNECTOR_HEIGHT))
            ET.SubElement(pose, "element", name=key, frame="0", layername="connector", z_index="0",
                          m_a="1", m_b="0", m_c="0", m_d="1", m_tx="0", m_ty="0")
    manifest = {"bank": BANK, "frames": FRAMES, "fps": FPS,
                "star_source": source_path.relative_to(ROOT).as_posix(),
                "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
                "registration_sha256": hashlib.sha256((SOURCE / "registration.json").read_bytes()).hexdigest(),
                "common_star_scale": scale, "connector_world_width": CONNECTOR_HEIGHT/150,
                "star_display_scale": STAR_SCALE,
                "connector_material_source": BEAM_SOURCE.relative_to(ROOT).as_posix(),
                "connector_material_sha256": hashlib.sha256(BEAM_SOURCE.read_bytes()).hexdigest(),
                "connector_shape_reference": CONNECTOR_SOURCE.relative_to(ROOT).as_posix(),
                "connector_clips": SLICES, "connector_frames": BEAM_FRAMES,
                "connector_taper_length": CONNECTOR_LENGTH, "connector_rear_overlap": 0,
                "connector_end_scale": CONNECTOR_END_SCALE,
                "star_poses": "12 independently painted turning poses, white-core registration, no added matrix turn",
                "layer_order": ["beam entity FinalOffset 3", "connector entity FinalOffset 4", "star entity FinalOffset 5"],
                "star_orientation": "BillBoard", "texture_sampling": TEXTURE_POLICY}
    return build, animations, images, manifest


def load_compiled(bank):
    material = NativeAnimation.__new__(NativeAnimation)
    with zipfile.ZipFile(ROOT / f"mod/anim/{bank}.zip") as archive:
        material.clips = read_animation(archive.read("anim.bin"))
        material.build = read_build(archive.read("build.bin"))
        # Klei's buildanimation pipeline premultiplies alpha; Pillow expects
        # straight RGB for compositing, for BOTH ribbon and head materials.
        material.atlases = [texture(archive.read(p), unpremultiply=True) for p in material.build["atlases"]]
    material.cache = {}
    return material


def draw_material(canvas, material, clip, index, x, y, sx, sy, angle=0, opacity=1, matrix=None):
    if sx <= 0 or sy <= 0:
        return
    sprite, (ox, oy) = material.render_frame(clip, index)
    # Resolve exact pixel-centre/quad-edge ties consistently for adjacent
    # Pillow draws (the GPU resolves shared raster edges itself).
    x += .00001
    y += .00001
    if matrix is None:
        c, s = math.cos(angle), math.sin(angle)
        a, b, cc, d = sx*c, sx*s, -sy*s, sy*c
    else:
        # Forward affine basis: screen = origin + (a,b)*u + (cc,d)*v.
        a, b, cc, d = matrix
    det = a*d-b*cc
    if abs(det) < 1e-12:
        return
    corners = [(x+a*u+cc*v, y+b*u+d*v) for u in (ox,ox+sprite.width) for v in (oy,oy+sprite.height)]
    left, top = math.floor(min(p[0] for p in corners)), math.floor(min(p[1] for p in corners))
    right, bottom = math.ceil(max(p[0] for p in corners)), math.ceil(max(p[1] for p in corners))
    sprite = sprite.transform((right-left,bottom-top), Image.Transform.AFFINE,
                              (d/det,-cc/det,(d*(left-x)-cc*(top-y))/det-ox,
                               -b/det,a/det,(-b*(left-x)+a*(top-y))/det-oy), Image.Resampling.BICUBIC)
    if opacity < 1:
        sprite.putalpha(sprite.getchannel("A").point(lambda p: round(p*opacity)))
    canvas.alpha_composite(sprite, (left,top))


def compiled_preview(manifest):
    material, body = load_compiled(BANK), load_compiled("nw_end_beam")
    PREVIEW.mkdir(parents=True, exist_ok=True)
    frames = []
    # 48 frames is the shared loop of 16 beam frames and 12 head frames.
    for index in range(48):
        canvas = Image.new("RGBA", (1000, 260), "#353d37")
        draw = ImageDraw.Draw(canvas)
        draw.text((24, 18), "END BEAM / shared flowing material, independent turning star", fill="#ede1cc")
        draw.text((24, 228), "Compiled material cycle preview - not an in-game screenshot", fill="#b8bcb5")
        beam_end = 874-CONNECTOR_LENGTH*38/CONNECTOR_HEIGHT
        last_piece = None
        for piece in range(12):
            left = 34+piece*70
            visible = max(0, min(70, beam_end-left))
            if visible == 0:
                continue
            draw_material(canvas, body, f"beam_{piece%4}", index%16,
                          left+visible/2, 129, visible/300, 38/64)
            last_piece = piece
        scale = 38/CONNECTOR_HEIGHT
        draw_material(canvas, material, f"connector_{last_piece%4}", index%16,
                      (beam_end+874)/2, 129, scale, scale)
        draw_material(canvas, material, "head", index%FRAMES, 874, 129, scale, scale)
        frames.append(canvas.convert("RGB"))
    frames[0].save(PREVIEW / "preview.png")
    frames[0].save(PREVIEW / "flow.gif", save_all=True, append_images=frames[1:],
                   duration=[33, 33, 34]*16, loop=0, disposal=2)
    closeups = []
    for frame_image in frames:
        detail = Image.new("RGB", (570, 380), "#353d37")
        detail.paste(frame_image.crop((760, 75, 950, 185)).resize((570, 330), Image.Resampling.NEAREST), (0, 30))
        ImageDraw.Draw(detail).text((16, 10), "Shared flowing connection / independent star (3x detail)", fill="#ede1cc")
        closeups.append(detail)
    closeups[0].save(PREVIEW / "head-layers.png")
    closeups[0].save(PREVIEW / "head-layers.gif", save_all=True, append_images=closeups[1:],
                     duration=[33, 33, 34]*16, loop=0, disposal=2)
    board = Image.new("RGB", (1000, 260*4))
    for row, index in enumerate((0, 3, 6, 9)):
        board.paste(frames[index], (0, row*260))
    board.save(PREVIEW / "frames.png")
    (PREVIEW / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare-only", action="store_true")
    args = parser.parse_args()
    build, animations, images, manifest = make_bank()
    if not args.prepare_only:
        compile_bank(BANK, build, animations, images, MOD_TOOLS)
        manifest["texture_packaging"] = retain_archive_mip0(ROOT / f"mod/anim/{BANK}.zip")
        compiled_preview(manifest)
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
