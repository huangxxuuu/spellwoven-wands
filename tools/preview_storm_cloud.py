"""One continuous storm scene, rendered from production animation assets.

Cloud transforms use the production XML. Strike geometry runs electric_visual
span/project with the production arc bank and native shock_fx textures. This is
an offline fixed-camera review, not an in-game capture or a damage simulation.
"""
from __future__ import annotations

import math
import zipfile

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

from build_field_stages import ROOT, build_bank
from native_animation import NativeAnimation, read_animation
from preview_basic_flight import BG, INK
from preview_field_stages import Review

OUT = ROOT / "docs/previews/storm-cloud-v5"
FONT_PATH = "C:/Windows/Fonts/msyh.ttc"
TITLE = ImageFont.truetype(FONT_PATH, 25)
SMALL = ImageFont.truetype(FONT_PATH, 15)
MUTED = (157, 174, 178)
FPS = 30
EXPIRY = 2.55
STRIKES = (.8, 1.6, 2.4)
WIDTH, HEIGHT = 960, 720
ANCHOR = (480, 650)
SCALE = 1.3


class CloudReview(Review):
    def __init__(self, bank):
        self.bank = bank
        self.animations = {clip.get("name"): clip for clip in bank.animations}


def timeline(review, now):
    """Gameplay deadlines and each build's actual animation durations."""
    duration = lambda phase: review.bank.clips["storm_cloud_"+phase]["seconds"]
    if now >= EXPIRY:
        return "storm_cloud_end", now-EXPIRY, now < EXPIRY+duration("end")
    spawn = duration("spawn")
    if now < spawn:
        return "storm_cloud_spawn", now, True
    idle_from, idle_suffix = spawn, ""
    for cycle, pulse in enumerate(STRIKES, 1):
        suffix = "" if cycle==1 else "_"+str(cycle)
        warning = pulse-duration("warning")
        if warning <= now < pulse:
            return "storm_cloud_warning"+suffix, now-warning, True
        if pulse <= now < pulse+duration("pulse"):
            return "storm_cloud_pulse"+suffix, now-pulse, True
        if now >= pulse+duration("pulse"):
            idle_from, idle_suffix = pulse+duration("pulse"), suffix
    return "storm_cloud_idle"+idle_suffix, now-idle_from, True


class ElectricReview:
    def __init__(self):
        self.native = NativeAnimation("shock_fx")
        with zipfile.ZipFile(ROOT / "mod/anim/nw_electric_arc.zip") as archive:
            self.native.clips = read_animation(archive.read("anim.bin"))
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("package.path = '"+str(ROOT / "mod/scripts/?.lua").replace("\\", "/")+";'..package.path")
        self.electric = self.lua.eval('require("nw/electric_visual")')
        self.stages = self.lua.eval('require("nw/field_stages")')
        self.pitch = math.radians(35)
        # This fixed point only drives the review. Game targets remain dynamic.
        self.target = (-.25, .15, .6)
        self.cache = {}

    def point(self, x, y, z):
        px, py = self.electric.project(x, y, z, 0, self.pitch)
        return ANCHOR[0]+px*150*SCALE, ANCHOR[1]+py*150*SCALE

    def stamp(self, canvas, now):
        start = next((when for when in STRIKES if when <= now < when+.23), None)
        if start is None:
            return
        age = now-start
        dx, dy, dz = self.target
        # Keep the billboard source lift in sync with the production module.
        lift = self.stages.storm_lift(self.lua.table_from({}))
        count, scale, direction, raised = self.electric.span(dx, dy, dz, lift, 0, self.pitch)
        for index in range(1, int(count)+1):
            t = (index-.5)/count
            x, y = self.point(dx*t, raised+(dy-raised)*t, dz*t)
            frame = math.floor((age+(index % 4)/30)*30) % 4
            key = direction, frame
            if key not in self.cache:
                self.cache[key] = self.native.render_frame("arc_"+str(direction), frame)
            image, offset = self.cache[key]
            visual_scale = scale*SCALE
            image = image.resize((max(1, round(image.width*visual_scale)),
                                  max(1, round(image.height*visual_scale))), Image.Resampling.LANCZOS)
            alpha = min(1, max(0, (.23-age)/.07))
            image.putalpha(image.getchannel("A").point(lambda value: round(value*alpha)))
            canvas.alpha_composite(image, (round(x+offset[0]*visual_scale),
                                          round(y+offset[1]*visual_scale)))


def render(review, electric, now):
    canvas = Image.new("RGBA", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((28, 22), "局部雷云", font=TITLE, fill=INK)
    draw.text((28, HEIGHT-34), "离线动画预览 · 生产云体动画与原生电弧 · 非游戏截图", font=SMALL, fill=MUTED)
    # Ground contact reference is review UI, with no gameplay range implied.
    tx, ty = electric.point(electric.target[0], 0, electric.target[2])
    draw.ellipse((tx-18, ty-5, tx+18, ty+5), fill=(29, 35, 37), outline=(70, 79, 81))
    electric.stamp(canvas, now)
    clip, age, active = timeline(review, now)
    if active:
        review.stamp(canvas, clip, age, ANCHOR, SCALE)
    return canvas


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    review, electric = CloudReview(build_bank()), ElectricReview()
    length = EXPIRY+review.bank.clips["storm_cloud_end"]["seconds"]+.4
    frames = [render(review, electric, index/FPS) for index in range(math.ceil(length*FPS))]
    # One shared palette from the whole lifecycle preserves strike colours.
    samples = [frame.resize((240, 180)).convert("RGB") for frame in frames[::3]]
    atlas = Image.new("RGB", (240*8, 180*math.ceil(len(samples)/8)))
    for index, sample in enumerate(samples):
        atlas.paste(sample, (index % 8*240, index//8*180))
    palette = atlas.quantize(colors=256)
    encoded = [frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    durations = [10*(round((i+1)*100/FPS)-round(i*100/FPS)) for i in range(len(frames))]
    encoded[0].save(OUT/"lifecycle.gif", save_all=True, append_images=encoded[1:],
                    duration=durations, loop=0, disposal=1, optimize=True)
    frames[round(.8*FPS)].convert("RGB").save(OUT/"poster.png")
    print(f"Saved one continuous {length:.2f} s storm review to {OUT}")


if __name__ == "__main__":
    main()
