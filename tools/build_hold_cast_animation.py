"""Build the planted two-hand player cast rig and compiled-art previews.

The editable source is assets_src/player_hold_cast/rig.json. Existing native
character/skin symbols and the equipped modular wand supply all raster art.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

from native_animation import GAME, NativeAnimation, read_animation, read_build, texture

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets_src/player_hold_cast"
from hold_cast_rig import Rig, RIG_PATH, encode, name_hash


def build(game=GAME, destination=None, manifest=True):
    rig = Rig(game)
    clips = rig.clips()
    data = encode(clips, rig.names)
    assert len(read_animation(data)) == 45
    destination = destination or ROOT / "mod/anim/nw_hold_cast.zip"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(destination, "w", ZIP_DEFLATED) as archive:
        info = ZipInfo("anim.bin", date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        archive.writestr(info, data)
    if manifest:
        ART.mkdir(parents=True, exist_ok=True)
        record = {"rig": str(RIG_PATH.relative_to(ROOT)).replace("\\", "/"),
                  "source_sha256": rig.sources, "bank": "wilson", "fps": 30,
                  "facings": [2, 5, 8], "frames": {"pre": 11, "loop": rig.config["cycle_frames"], "pst": 11},
                  "recoil_levels": 12, "rig_parameters": rig.config,
                  "output_sha256": hashlib.sha256(data).hexdigest(),
                  "notes": "Braced native leg cels, planted stance, channelcast breath and full-body recoil; shared loop phase, no textures/events."}
        (ART / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf8")
    print(f"Built {destination}: 3 directions; pre/hold/post plus 12 recoil levels; planted feet")
    return clips


def preview(clips, game=GAME):
    """Render real compiled character and modular-wand art, with native pivots."""
    from PIL import Image, ImageDraw
    from lupa.lua51 import LuaRuntime

    player = NativeAnimation("player_attacks", game=game, build_name="wilson", unpremultiply=True)
    player.clips = clips
    wand = NativeAnimation.__new__(NativeAnimation)
    with ZipFile(ROOT / "mod/anim/nw_parts.zip") as archive:
        wand.clips = read_animation(archive.read("anim.bin"))
        wand.build = read_build(archive.read("build.bin"))
        wand.atlases = [texture(archive.read(p), unpremultiply=True) for p in wand.build["atlases"]]
    wand.cache = {}
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + lua.globals().package.path
    head, length, tail, body = lua.eval('require("nw/visual").parts')(18)
    replacements = {name_hash("head"): head, name_hash("body"): body, name_hash("tail"): tail}
    original_wand_symbol = wand.symbol
    wand.symbol = lambda key, frame=0: original_wand_symbol(replacements.get(key, key), frame)
    for key in replacements:
        wand.build["frames"][key] = []
    wand_image = wand.render_frame("held_" + length)
    swap = name_hash("swap_object")
    original_symbol = player.symbol
    player.symbol = lambda key, frame=0: wand_image if key == swap else original_symbol(key, frame)
    player.build["frames"][swap] = []
    hidden = {name_hash(n) for n in ("ARM_normal", "HAT", "HAIR_HAT", "HEAD_HAT")}
    # Rendering only: keep runtime clips (including clothing layers) untouched.
    player.clips = [{**c, "frames": [{**f, "elements": [e for e in f["elements"] if e[2] not in hidden]}
                                     for f in c["frames"]]} for c in clips]
    ART.mkdir(parents=True, exist_ok=True)
    cycle = len(next(c for c in clips if c["name"] == "nw_hold_cast_loop")["frames"])
    sequence = [("pre", i) for i in range(11)] + [("loop", i % cycle) for i in range(cycle*2)]
    recoil = 0
    # Two slower shots, then a short rapid burst; settle while still aiming.
    for tick in range(144):
        recoil = max(0, recoil - 2.5/30)
        if tick in (0, 25, 50) or (70 <= tick < 96 and tick % 3 == 1) or 96 <= tick <= 110:
            recoil = min(1, recoil + .35)
        level = math.ceil(recoil*12-1e-6)
        sequence.append((f"recoil_{level:02d}" if level else "loop", tick % cycle))
    sequence += [("pst", i) for i in range(11)]
    images = []
    rendered = {}
    for suffix, index in sequence:
        canvas = Image.new("RGB", (1260, 520), "#ddd7ca")
        for column, facing in enumerate((5, 8, 2)):
            key = suffix, index, facing
            if key not in rendered:
                im, (x, y) = player.render_frame("nw_hold_cast_" + suffix, index, facing)
                rendered[key] = im.resize((round(im.width * .7), round(im.height * .7))), (x, y)
            im, (x, y) = rendered[key]
            canvas.paste(im, (column * 420 + 125 + round(x * .7), 335 + round(y * .7)), im)
        ImageDraw.Draw(canvas).text((12, 12), f"Braced stance + breathing + full-body recoil | {suffix} frame {index}", fill="black")
        images.append(canvas)
    images[11].save(ART / "hold_preview.png")
    keys = [("pre", 0), ("pre", 5), ("loop", 0), ("recoil_12", 0), ("pst", 5)]
    sheet = Image.new("RGB", (1750, 480), "#ddd7ca")
    draw = ImageDraw.Draw(sheet)
    for column, (suffix, frame) in enumerate(keys):
        im, (x, y) = player.render_frame("nw_hold_cast_" + suffix, frame, 5)
        im = im.resize((round(im.width * .8), round(im.height * .8)))
        sheet.paste(im, (column * 350 + 120 + round(x * .8), 385 + round(y * .8)), im)
        draw.text((column*350+12, 15), f"{column+1:02d} {suffix}", fill="black")
        draw.line((column*350+15, 398, column*350+335, 398), fill="#b5ad9f")
    sheet.save(ART / "keyposes_runtime.png")
    images[0].save(ART / "hold_preview.gif", save_all=True, append_images=images[1:], duration=33, loop=0)
    print(f"Preview: {ART / 'hold_preview.gif'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=GAME)
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    clips = build(args.game)
    if args.preview:
        preview(clips, args.game)
