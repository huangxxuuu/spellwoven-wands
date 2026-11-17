"""Render production key-hint/guide widgets using compiled textures and native UI glyphs.

English letters and mouse symbols use the installed game's bitmap fonts. Chinese
uses Microsoft YaHei as a labelled fallback; this is an offline layout preview.
"""
from functools import lru_cache
from io import BytesIO
import json
from pathlib import Path
import re
from xml.etree import ElementTree as ET
from zipfile import ZipFile

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageChops, ImageDraw, ImageFont

from native_animation import GAME, texture
from preview_quickguide import BACKEND, ROOT, colour, sprite

OUT = ROOT / "test_reports/keycap"


class Fonts:
    def __init__(self):
        self.glyphs = {"ui":{}, "dialog":{}, "symbols":{}}
        with ZipFile(GAME / "data/databundles/fonts.zip") as archive:
            for name, alias, adjustment, coloured in (("belisaplumilla50", "ui", -2, False), ("opensans50", "dialog", 0, False), ("controllers", "symbols", 0, True)):
                with ZipFile(BytesIO(archive.read(f"fonts/{name}.zip"))) as font:
                    xml = ET.fromstring(font.read("font.fnt"))
                    sheet = texture(font.read("font.tex"), unpremultiply=True)
                for element in xml.find("chars"):
                    data = {key: int(value) for key, value in element.attrib.items()}
                    x, y, w, h = (data[key] for key in ("x", "y", "width", "height"))
                    self.glyphs[alias][data["id"]] = (sheet.crop((x, y, x+w, y+h)), data, adjustment, coloured)

    @lru_cache(None)
    def raster(self, value, size, font="ui"):
        size = float(size)
        scale = size / 50
        x = 0
        items = []
        for character in value:
            entry = self.glyphs.get(font,self.glyphs["ui"]).get(ord(character)) or self.glyphs["symbols"].get(ord(character))
            if entry:
                tile, metrics, adjust, coloured = entry
                tile = tile.resize((max(1, round(tile.width*scale)), max(1, round(tile.height*scale))), Image.Resampling.LANCZOS)
                items.append((tile, round(x+metrics["xoffset"]*scale), round(metrics["yoffset"]*scale), coloured))
                x += (metrics["xadvance"]+adjust)*scale
            else:
                fallback_font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", max(1, round(size)))
                box = fallback_font.getbbox(character, stroke_width=1)
                tile = Image.new("RGBA", (max(1, box[2]-box[0]), max(1, box[3]-box[1])))
                ImageDraw.Draw(tile).text((-box[0], -box[1]), character, font=fallback_font, fill="white", stroke_width=1, stroke_fill="black")
                items.append((tile, round(x), round((size-tile.height)/2), False))
                x += fallback_font.getlength(character)
        left = min([0]+[px for _, px, _, _ in items])
        top = min([0]+[py for _, _, py, _ in items])
        right = max([round(x)]+[px+tile.width for tile, px, _, _ in items])
        bottom = max([round(size)]+[py+tile.height for tile, _, py, _ in items])
        normal = Image.new("RGBA", (max(1, right-left), max(1, bottom-top)))
        symbols = Image.new("RGBA", normal.size)
        for tile, px, py, coloured in items:
            (symbols if coloured else normal).alpha_composite(tile, (px-left, py-top))
        return normal, symbols

    def measure(self, value, size, font="ui"):
        layers = [self.raster(line, size, font)[0] for line in value.split("\n")]
        return max(image.width for image in layers), sum(image.height for image in layers)

    def text(self, canvas, value, size, tint, x, y, align="center", font="ui"):
        normal, symbols = self.raster(value, size, font)
        image = ImageChops.multiply(normal, Image.new("RGBA", normal.size, tint))
        image.alpha_composite(symbols)
        canvas.alpha_composite(image, (round(x if align=="left" else x-image.width/2), round(y-image.height/2)))


def draw_widget(canvas, node, fonts, x, y):
    if node.dead or node.hidden:
        return
    x += node.x or 0
    y -= node.y or 0
    if node.kind == "image":
        w, h = max(1, round(node.w)), max(1, round(node.h))
        tile = Image.new("RGBA", (w, h), "white") if node.texture=="square.tex" else sprite(node.atlas, node.texture).resize((w,h), Image.Resampling.LANCZOS)
        tile = ImageChops.multiply(tile, Image.new("RGBA", tile.size, colour(node.tint)))
        canvas.alpha_composite(tile, (round(x-w/2), round(y-h/2)))
    elif node.kind == "text":
        size = node.fontsize
        lines = []
        for paragraph in (node.text or "").split("\n"):
            line = ""
            for character in paragraph:
                candidate = line+character
                if node.w and line and fonts.measure(candidate, size, node.font or "ui")[0]>node.w:
                    lines.append(line);line=character
                else:
                    line=candidate
            lines.append(line)
        height = len(lines)*size*1.2
        assert not node.h or height<=node.h+1, f"text overflows: {node.text}"
        for index, line in enumerate(lines):
            left = node.halign==1 and node.w is not None
            fonts.text(canvas, line, size, colour(node.tint), x-node.w/2 if left else x,
                       y-height/2+(index+.5)*size*1.2, "left" if left else "center", node.font or "ui")
    for child in node.children.values():
        draw_widget(canvas, child, fonts, x, y)


def runtime(fonts):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix()+";"+vm.globals().package.path
    vm.globals()._measure_text = fonts.measure
    vm.execute(BACKEND)
    vm.execute('STRINGS={UI={CONTROLSSCREEN={INPUTS={{}}}}}')
    with ZipFile(GAME / "data/databundles/scripts.zip") as archive:
        strings = archive.read("scripts/strings.lua").decode()
    strings = strings[strings.index("INPUTS", strings.index("CONTROLSSCREEN")):]
    for code in (8, 9, 32, 107, 286, 1001, 1002):
        text = re.search(r"\["+str(code)+r'\]\s*=\s*("[^"\n]*")', strings).group(1)
        vm.execute(f"STRINGS.UI.CONTROLSSCREEN.INPUTS[1][{code}]={text}")
    vm.execute('''
preview_binding="key:8"
package.loaded["nw/cast_binding"]={ready=function() return true end,pending=function() return false end,
    get=function() return preview_binding end,get_default=function() return "mouse:1001" end,
    subscribe=function() return function() end end,query=function() end}
''')
    return vm


def header(canvas, text):
    ImageDraw.Draw(canvas).text((24,18), text, font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",20), fill="#eadfc8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    fonts = Fonts()
    vm = runtime(fonts)
    locale = vm.eval('require("nw/locale")')
    hint = vm.eval('require("widgets/nw_keyhint")')
    canvas = Image.new("RGBA", (960, 660), "#242a27")
    header(canvas, "KEYCAP PREVIEW / PRODUCTION LUA + COMPILED TEXTURES / 1:1 DISPLAY")
    report = {"note": "Offline; native English/mouse bitmap glyphs, substitute Chinese font; not an in-game screenshot.", "rows": []}
    bindings = ["key:107", "key:286", "key:9", "key:32", "key:8", "mouse:1001", "mouse:1002"]
    for col, language in enumerate(("zh", "en")):
        locale.configure(language, language)
        x = 240+col*480
        fonts.text(canvas, "中文" if language=="zh" else "English", 26, (238,230,211,255), x, 72)
        for row, binding in enumerate(bindings):
            widget = hint("ui", 30)
            action = ("灵魂跳跃" if language=="zh" else "Soul Hop") if binding=="mouse:1001" else ("施法" if language=="zh" else "Cast")
            widget.SetBinding(widget, binding, action)
            draw_widget(canvas, widget, fonts, x, 126+row*59)
            width, height = widget.GetRegionSize(widget)
            assert width<400 and height<50
            report["rows"].append({"language":language,"binding":binding,"label":widget.GetString(widget),"width":width,"height":height})
        # Casting hint over a bright world background; settings use plain text.
        ImageDraw.Draw(canvas).rectangle((col*480+24,554,col*480+456,614), fill="#cec5b5")
        widget = hint("ui", 30)
        widget.SetBinding(widget, "key:8")
        draw_widget(canvas, widget, fonts, x, 584)
    ImageDraw.Draw(canvas).text((24,634), "Native UI/mouse glyphs; Chinese font substituted. Bottom row: casting keycap over a bright background.", fill="#b8b8ad")
    canvas.convert("RGB").save(OUT / "keycap_preview.png")
    guide = vm.eval('require("nw/quickguide")')
    for language in ("zh", "en"):
        locale.configure(language, language)
        screen = guide.open()
        screen.select_page("personal")
        # Settings keep the native text row, with no keycap widgets.
        width, _ = screen.cast_key.GetRegionSize(screen.cast_key)
        assert screen.cast_key.kind=="text"
        assert screen.cast_key.x-screen.cast_key.w/2+width < screen.cast_key_capture.x-32
        preview = Image.new("RGBA", (960,720), "#242a27")
        header(preview, "PRODUCTION GUIDE / BACKSPACE / OFFLINE PREVIEW")
        draw_widget(preview, screen, fonts, 480,360)
        preview.convert("RGB").save(OUT / f"keycap_settings_{language}.png")
    (OUT / "layout.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"PASS keycap native-font layout, K/F5/Tab/Space/Backspace, native mouse, bilingual settings: {OUT}")


if __name__ == "__main__":
    main()
