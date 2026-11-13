"""Preview the compiled furnace wave with the project's offline ground projection."""
from __future__ import annotations

import argparse
import math
from pathlib import Path
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from animation_atlas import validate_animation_archive
from native_animation import NativeAnimation, read_animation, read_build, texture

ROOT = Path(__file__).resolve().parents[1]
BANK = "nw_furnace_wave"
ARCHIVE = ROOT / f"mod/anim/{BANK}.zip"
FURNACE = ROOT / "assets_src/stations_redraw_v3_20261110/furnace/source.png"
OUT = ROOT / "assets_src/disassembler_wave_perimeter_animation_20261114/previews/rotation"
FPS = 30
CLIP_LENGTHS = {"grow": 60, "loop": 60, "release": 18}
PLAYBACK = (("grow", 60), ("loop", 90), ("release", 18), ("idle", 15))
LABELS = {"grow": "展开", "loop": "循环", "release": "碎散", "idle": "静止"}
KEY_TICKS = (15, 30, 45, 59, 60, 75, 105, 149, 150, 159, 167, 168)

# Match the review camera in preview_basic_flight.py / preview_field_stages.py.
PROJECTION = math.sin(math.radians(35))
# Match the approved F static composition: 430px outer radius, 320px furnace
# width, foot 9px below the ground origin. This is a proportion illustration.
REFERENCE_RADIUS = 430
FURNACE_WIDTH = 320
SCENE_SIZE = (1000, 666)
ORIGIN = (500, 348)
GROUND = (77, 86, 74)
MAT = (33, 39, 36)
INK = (239, 240, 229)
MUTED = (182, 196, 181)
FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
HEADER = 74


class FurnaceWave(NativeAnimation):
    def __init__(self, path: Path):
        validate_animation_archive(path)
        with ZipFile(path) as archive:
            self.build = read_build(archive.read("build.bin"))
            self.clips = read_animation(archive.read("anim.bin"))
            self.atlases = []
            for name in self.build["atlases"]:
                image = texture(archive.read(name))
                # The animation compiler premultiplies KTEX. Convert to straight
                # RGBA before NativeAnimation alpha-composites its symbols.
                straight = Image.frombytes("RGBa", image.size, image.tobytes()).convert("RGBA")
                self.atlases.append(straight)
        self.cache = {}
        clips = {clip["name"]: (clip["fps"], len(clip["frames"])) for clip in self.clips}
        expected = {name: (FPS, length) for name, length in CLIP_LENGTHS.items()}
        if self.build["name"] != BANK or len(self.clips) != len(expected) or clips != expected:
            raise ValueError(f"{path}: expected {BANK} with {expected}, found {clips}")

    def symbol(self, key, frame=0):
        # Fully transparent painted endpoints compile to a frame with no
        # vertices. Preserve that real alpha rather than inventing a fade.
        if isinstance(key, str):
            key = next(k for k, name in self.build["names"].items() if name == key)
        row = next(row for row in self.build["frames"][key] if row[0] <= frame < row[0] + row[1])
        if row[7] == 0:
            return Image.new("RGBA", (1, 1)), (0, 0)
        return super().symbol(key, frame)


def stamp(canvas, sprite, offset, scale_x, scale_y):
    width = max(1, round(sprite.width * scale_x))
    height = max(1, round(sprite.height * scale_y))
    sprite = sprite.resize((width, height), Image.Resampling.LANCZOS)
    left = round(ORIGIN[0] + offset[0] * scale_x)
    top = round(ORIGIN[1] + offset[1] * scale_y)
    canvas.alpha_composite(sprite, (left, top))


def reference_scale(animation, target_radius=REFERENCE_RADIUS):
    sprite, offset = animation.render_frame("loop", 0)
    yy, xx = np.nonzero(np.asarray(sprite.getchannel("A")) >= 64)
    if not len(xx):
        raise ValueError("loop's reference pose must have alpha>=64 artwork")
    radius = float(np.hypot(xx + offset[0], yy + offset[1]).max())
    return target_radius / radius


def reference_furnace(path=FURNACE, width=FURNACE_WIDTH):
    with Image.open(path) as source:
        furnace = source.convert("RGBA")
    bounds = furnace.getchannel("A").getbbox()
    if not bounds:
        raise ValueError(f"{path}: empty furnace reference")
    furnace = furnace.crop(bounds)
    return furnace.resize((width, round(furnace.height * width / furnace.width)), Image.Resampling.LANCZOS)


def load_rotation_angle():
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    module = lua.execute((ROOT / "mod/scripts/nw/furnace_visual.lua").read_text(encoding="utf8"))
    return module.rotation_angle


def rotate_ground(sprite, offset, angle):
    """Rotate decoded straight RGBA around animation (0, 0), before projection.

    This is an offline screen-plane convention; client rotation direction still
    requires in-game review of OnGround rendering.
    """
    cosine, sine = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    corners = [(cosine*x-sine*y, sine*x+cosine*y)
               for x in (offset[0], offset[0]+sprite.width)
               for y in (offset[1], offset[1]+sprite.height)]
    left, top = math.floor(min(x for x, _ in corners)), math.floor(min(y for _, y in corners))
    right, bottom = math.ceil(max(x for x, _ in corners)), math.ceil(max(y for _, y in corners))
    transform = (cosine, sine, cosine*left+sine*top-offset[0],
                 -sine, cosine, -sine*left+cosine*top-offset[1])
    image = sprite.transform((max(1, right-left), max(1, bottom-top)), Image.Transform.AFFINE,
                             transform, Image.Resampling.BICUBIC)
    return image, (left, top)


def banner(scene, caption, stage, font, small):
    image = Image.new("RGB", (SCENE_SIZE[0], SCENE_SIZE[1] + HEADER), MAT)
    image.paste(scene, (0, HEADER))
    draw = ImageDraw.Draw(image)
    draw.text((22, 10), caption, font=font, fill=INK)
    draw.text((22, 46), "比例示意 · 外半径 430px / 炉宽 320px · 非游戏实拍 · 展开2秒 / 循环3秒 / 碎散0.6秒",
              font=small, fill=MUTED)
    draw.text((SCENE_SIZE[0]-22, 33), LABELS[stage], anchor="rm", font=font, fill=MUTED)
    return image.quantize(colors=256)


def contact_sheet(entries, font, small, path):
    width = 360
    height = round(width * SCENE_SIZE[1] / SCENE_SIZE[0])
    margin, gap, label_height = 18, 12, 28
    rows = (len(entries) + 2) // 3
    sheet = Image.new("RGB", (2 * margin + 3 * width + 2 * gap,
                             HEADER + rows * (height + label_height + gap) + margin), MAT)
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 10), "分解炉圈 · 逐帧形变+整体旋转 · 关键时刻", font=font, fill=INK)
    draw.text((margin, 46), "比例示意 · 外半径430px / 炉宽320px · 编译后动画帧 · 非游戏实拍", font=small, fill=MUTED)
    for index, (tick, stage, scene) in enumerate(entries):
        row, col = divmod(index, 3)
        x = margin + col * (width + gap)
        y = HEADER + row * (height + label_height + gap)
        sheet.paste(scene.resize((width, height), Image.Resampling.LANCZOS), (x, y))
        draw.text((x, y + height + 3), f"{tick / FPS:0.2f} 秒 · {LABELS[stage]}",
                  font=small, fill=INK)
    sheet.save(path)


def save_gif(frames, path):
    # GIF duration is stored in centiseconds. Quantize the accumulated time
    # so three 30 FPS frames occupy exactly 100 ms.
    ticks = [round(i * 100 / FPS) for i in range(len(frames) + 1)]
    durations = [10 * (end - start) for start, end in zip(ticks, ticks[1:])]
    frames[0].save(path, save_all=True, append_images=frames[1:],
                   duration=durations, loop=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ARCHIVE)
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    animation = FurnaceWave(args.archive)
    scale = reference_scale(animation)
    rotation_angle = load_rotation_angle()
    active_ticks = sum(length for stage, length in PLAYBACK if stage in ("grow", "loop"))
    font = ImageFont.truetype(FONT_PATH, 24)
    small = ImageFont.truetype(FONT_PATH, 15)
    furnace = reference_furnace()
    furnace_offset = (-furnace.width / 2, 9 - furnace.height)

    paired, wave_only, key_frames = [], [], []
    tick = 0
    for stage, length in PLAYBACK:
        for index in range(length):
            scene = Image.new("RGBA", SCENE_SIZE, GROUND)
            if stage != "idle":
                # Render in animation space before projecting the ground plane.
                sprite, offset = animation.render_frame(stage, index)
                age = min(tick, active_ticks) / FPS
                sprite, offset = rotate_ground(sprite, offset, rotation_angle(age))
                stamp(scene, sprite, offset, scale, scale * PROJECTION)
            wave_only.append(banner(scene, "分解炉圈 · 逐帧形变+整体旋转", stage, font, small))
            stamp(scene, furnace, furnace_offset, 1, 1)
            paired.append(banner(scene, "分解炉圈 · 逐帧形变+整体旋转 / 炉体比例参考", stage, font, small))
            if tick in KEY_TICKS:
                key_frames.append((tick, stage, scene.convert("RGB")))
            tick += 1

    args.out.mkdir(parents=True, exist_ok=True)
    save_gif(paired, args.out / "furnace-wave.gif")
    save_gif(wave_only, args.out / "wave-only.gif")
    contact_sheet(key_frames, font, small, args.out / "keyframes.png")
    print(f"Saved previews to {args.out}")


if __name__ == "__main__":
    main()
