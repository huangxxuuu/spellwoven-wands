"""Preview the compiled furnace wave with the project's offline ground projection."""
from __future__ import annotations

import argparse
import math
from pathlib import Path
from zipfile import ZipFile

from PIL import Image, ImageDraw, ImageFont, ImageOps

from animation_atlas import validate_animation_archive
from native_animation import NativeAnimation, read_animation, read_build, texture

ROOT = Path(__file__).resolve().parents[1]
BANK = "nw_furnace_wave"
ARCHIVE = ROOT / f"mod/anim/{BANK}.zip"
FURNACE = ROOT / "assets_src/stations_redraw_v3_20261110/furnace/source.png"
OUT = ROOT / "assets_src/disassembler_wave_v2_complete_20261110/previews"
FPS = 30
CLIP_LENGTHS = {"grow": 60, "loop": 60, "release": 18}
PLAYBACK = (("grow", 60), ("loop", 90), ("release", 18), ("idle", 15))
LABELS = {"grow": "展开", "loop": "循环", "release": "碎散", "idle": "静止"}
KEY_TICKS = (15, 30, 45, 59, 60, 75, 105, 149, 150, 159, 167, 168)

# Match the review camera in preview_basic_flight.py / preview_field_stages.py.
PROJECTION = math.sin(math.radians(35))
SCALE = 0.65
SCENE_SIZE = (900, 480)
ORIGIN = (450, 240)
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


def stamp(canvas, sprite, offset, scale_x, scale_y):
    width = max(1, round(sprite.width * scale_x))
    height = max(1, round(sprite.height * scale_y))
    sprite = sprite.resize((width, height), Image.Resampling.LANCZOS)
    left = round(ORIGIN[0] + offset[0] * scale_x)
    top = round(ORIGIN[1] + offset[1] * scale_y)
    canvas.alpha_composite(sprite, (left, top))


def banner(scene, caption, stage, font, small):
    image = Image.new("RGB", (SCENE_SIZE[0], SCENE_SIZE[1] + HEADER), MAT)
    image.paste(scene, (0, HEADER))
    draw = ImageDraw.Draw(image)
    draw.text((22, 10), caption, font=font, fill=INK)
    draw.text((22, 46), "离线合成 · 展开 2 秒 / 循环 3 秒 / 碎散 0.6 秒 / 静止 0.5 秒",
              font=small, fill=MUTED)
    draw.text((878, 33), LABELS[stage], anchor="rm", font=font, fill=MUTED)
    return image.quantize(colors=256)


def contact_sheet(entries, font, small, path):
    width, height = 360, 192
    margin, gap, label_height = 18, 12, 28
    rows = (len(entries) + 2) // 3
    sheet = Image.new("RGB", (2 * margin + 3 * width + 2 * gap,
                             HEADER + rows * (height + label_height + gap) + margin), MAT)
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 10), "分解炉圈 · 方案 2 · 关键时刻", font=font, fill=INK)
    draw.text((margin, 46), "离线合成 · 圈为编译后动画帧，炉体用于观察比例", font=small, fill=MUTED)
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
    font = ImageFont.truetype(FONT_PATH, 24)
    small = ImageFont.truetype(FONT_PATH, 15)
    with Image.open(FURNACE) as source:
        furnace = ImageOps.contain(source.convert("RGBA"), (300, 320), Image.Resampling.LANCZOS)
    furnace_offset = (-furnace.width / 2, -140 - furnace.height / 2)

    paired, wave_only, key_frames = [], [], []
    tick = 0
    for stage, length in PLAYBACK:
        for index in range(length):
            scene = Image.new("RGBA", SCENE_SIZE, GROUND)
            if stage != "idle":
                # Render in animation space before projecting the ground plane.
                sprite, offset = animation.render_frame(stage, index)
                stamp(scene, sprite, offset, SCALE, SCALE * PROJECTION)
            wave_only.append(banner(scene, "分解炉圈 · 方案 2", stage, font, small))
            stamp(scene, furnace, furnace_offset, SCALE * 1.1, SCALE * 1.1)
            paired.append(banner(scene, "分解炉圈 · 方案 2 / 炉体比例参考", stage, font, small))
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
