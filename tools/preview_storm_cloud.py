"""Review actual cloud animation XML offline, at normal and giant sizes.

The cloud is centred for close inspection. This is not a DST screenshot;
target-dependent electric strokes and gameplay circles are not synthesized.
An optional saved builder supplies the original animation for comparison.
"""
from __future__ import annotations

import argparse
import importlib.util
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_field_stages import ROOT, build_bank
from preview_basic_flight import BG, INK
from preview_field_stages import Review

OUT = ROOT / "docs/previews/storm-cloud-v2"
BEFORE = ROOT / "test_reports/storm_cloud_before/build_field_stages.py"
FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
TITLE = ImageFont.truetype(FONT_PATH, 28)
FONT = ImageFont.truetype(FONT_PATH, 21)
SMALL = ImageFont.truetype(FONT_PATH, 16)
MUTED = (157, 174, 178)
ACCENT = (190, 203, 182)
PHASES = {"spawn": "聚云", "idle": "悬浮", "warning": "预警",
          "pulse": "击发", "end": "散云"}
FPS = 30
EXPIRY = 2.55


class CloudReview(Review):
    def __init__(self, bank):
        # Reuse the production XML renderer without loading unrelated native
        # meteor/shield assets or rebuilding the bank a second time.
        self.bank = bank
        self.animations = {clip.get("name"): clip for clip in bank.animations}


def before_review(path):
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location("storm_cloud_before_builder", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return CloudReview(module.build_bank())


def timeline(review, now):
    """Use gameplay deadlines and each build's actual animation durations."""
    clips = review.bank.clips
    duration = lambda phase: clips["storm_cloud_"+phase]["seconds"]
    if now >= EXPIRY:
        return "storm_cloud_end", now-EXPIRY, now < EXPIRY+duration("end")
    spawn = duration("spawn")
    if now < spawn:
        return "storm_cloud_spawn", now, True
    idle_from = spawn
    for pulse in (.8, 1.6, 2.4):
        warning = pulse-duration("warning")
        if warning <= now < pulse:
            return "storm_cloud_warning", now-warning, True
        if pulse <= now < pulse+duration("pulse"):
            return "storm_cloud_pulse", now-pulse, True
        if now >= pulse+duration("pulse"):
            idle_from = pulse+duration("pulse")
    return "storm_cloud_idle", now-idle_from, True


def envelope(reviews):
    points = []
    for review in reviews:
        for name, animation in review.animations.items():
            if not name.startswith("storm_cloud_"):
                continue
            for index in range(len(animation)):
                image, (x, y) = review.frame(name, index)
                bounds = image.getchannel("A").getbbox()
                if bounds:
                    left, top, right, bottom = bounds
                    points.extend(((x+left, y+top), (x+right, y+bottom)))
    xs, ys = zip(*points)
    return min(xs), min(ys), max(xs), max(ys)


def stamp_centred(review, canvas, now, centre, factor, scale, bounds):
    clip, age, active = timeline(review, now)
    if active:
        left, top, right, bottom = bounds
        anchor = (centre[0]-(left+right)*.5*scale*factor,
                  centre[1]-(top+bottom)*.5*scale*factor)
        review.stamp(canvas, clip, age, anchor, scale*factor)
    return PHASES[clip.rsplit("_", 1)[-1]] if active else "已消散"


def stage_sheet(review):
    # Rows pair x1 and x2.5 at one camera zoom, so the giant modifier remains
    # visible instead of normalizing both renders to the same thumbnail size.
    bounds = envelope([review])
    width, height = 2080, 1700
    cell_width, row_height = 510, 355
    scale = min(.85, (cell_width-40)/((bounds[2]-bounds[0])*2.5),
                (row_height-64)/((bounds[3]-bounds[1])*2.5))
    canvas = Image.new("RGBA", (width, height), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 17), "局部雷云 · 聚拢、预警与散云", font=TITLE, fill=INK)
    draw.text((24, 60), "离线动画分解 · 生产动画 XML · 两档大小共用镜头缩放", font=FONT, fill=MUTED)
    groups = ((.10, .35, .65, .84), (2.55, 2.78, 3.05, 3.30))
    for group, times in enumerate(groups):
        section_top = 113+group*775
        caption = "出现 0.50 秒 → 预警 0.30 秒 → 击发 0.20 秒" if group==0 else "场效果在 2.55 秒结束 → 纯视觉散云 0.80 秒"
        draw.text((24, section_top), caption, font=FONT, fill=ACCENT)
        for row, factor in enumerate((1, 2.5)):
            top = section_top+40+row*row_height
            for column, now in enumerate(times):
                left = 20+column*cell_width
                draw.rectangle((left, top, left+cell_width-8, top+row_height-8), outline=(52, 64, 68))
                phase = stamp_centred(review, canvas, now,
                    (left+cell_width/2, top+row_height/2+15), factor, scale, bounds)
                draw.text((left+14, top+10), f"{now:.2f} s  ·  {phase}  ·  x{factor:g}", font=FONT, fill=INK)
    draw.text((24, 1670), "云体局部预览；实战落雷随目标生成。此图不是游戏截图。", font=SMALL, fill=MUTED)
    canvas.convert("RGB").save(OUT/"stages.png")
    return canvas


def lifecycle(reviews, palette_source):
    bounds = envelope([review for _, review in reviews])
    width, row_height = 1600, 450
    height = 180+len(reviews)*row_height+65
    scale = min(.9, 735/((bounds[2]-bounds[0])*2.5),
                363/((bounds[3]-bounds[1])*2.5))
    palette = palette_source.convert("RGB").quantize(colors=256)
    frames = []
    length = EXPIRY+max(review.bank.clips["storm_cloud_end"]["seconds"] for _, review in reviews)+.4
    for index in range(math.ceil(length*FPS)):
        now = index/FPS
        canvas = Image.new("RGBA", (width, height), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((24, 16), "局部雷云 · 出现与消散", font=TITLE, fill=INK)
        draw.text((24, 59), "离线动画预览 · 相同镜头缩放 · 直接渲染生产动画", font=FONT, fill=MUTED)
        draw.text((24, 96), "0.50 s 聚云  /  0.30 s 预警  /  0.20 s 击发  /  0.80 s 散云", font=FONT, fill=ACCENT)
        draw.text((width-170, 23), f"{now:.2f} s", font=TITLE, fill=INK)
        for row, (label, review) in enumerate(reviews):
            top = 153+row*row_height
            draw.line((24, top, width-24, top), fill=(69, 83, 87))
            draw.text((24, top+10), label, font=FONT, fill=ACCENT)
            for factor, x in ((1, 400), (2.5, 1200)):
                phase = stamp_centred(review, canvas, now, (x, top+248), factor, scale, bounds)
                draw.text((x-95, top+row_height-35), f"x{factor:g}  ·  {phase}", font=FONT, fill=INK)
        draw.text((24, height-52), "实际击发：0.80 / 1.60 / 2.40 秒；2.55 秒结束场效果。此图仅展示云体，不是游戏截图。", font=SMALL, fill=MUTED)
        frames.append(canvas.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE))
    # GIF stores centiseconds: alternating 30/40/30 ms preserves 30 fps timing.
    durations = [10*(round((i+1)*100/FPS)-round(i*100/FPS)) for i in range(len(frames))]
    frames[0].save(OUT/"lifecycle.gif", save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, disposal=1, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before-source", type=Path, default=BEFORE)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    current = CloudReview(build_bank())
    old = before_review(args.before_source)
    reviews = []
    if old:
        reviews.append(("调整前 · 0.20 秒出现 / 0.30 秒消失", old))
    reviews.append(("调整后 · 分层聚云 / 云瓣散开", current))
    sheet = stage_sheet(current)
    lifecycle(reviews, sheet)
    print(f"Saved offline cloud review to {OUT}")


if __name__=="__main__":
    main()
