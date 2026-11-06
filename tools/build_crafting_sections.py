"""Bake Chinese and English crafting-category title atlases."""
from pathlib import Path
from tempfile import TemporaryDirectory
from xml.etree import ElementTree as ET
import subprocess

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
for language in ("zh", "en"):
    lua = LuaRuntime()
    base = "nw_sections" + ("_en" if language == "en" else "")
    lua.globals().package.path = (root / "mod/scripts/?.lua").as_posix() + ";" + lua.globals().package.path
    lua.eval('require("nw/locale").configure')(language, language)
    entries = lua.eval('require("nw/acquisition").menu_entries')
    labels = {row.section_icon: row.title for row in entries.values() if row.section_icon}
    wrap = {"远程投射物": ["远程", "投射物"], "静态投射物": ["静态", "投射物"],
            "法术效果修正": ["法术", "效果修正"]}
    size = 128
    sheet = Image.new("RGBA", (512, 512))
    atlas = ET.Element("Atlas")
    ET.SubElement(atlas, "Texture", filename=base+".tex")
    elements = ET.SubElement(atlas, "Elements")
    for i, (key, label) in enumerate(labels.items()):
        tile = Image.new("RGBA", (size, size))
        draw = ImageDraw.Draw(tile)
        draw.rounded_rectangle((4, 4, 123, 123), radius=10, fill="#2a211e", outline="#b99157", width=4)
        icon_labels={"Projectiles":["Ranged"],"Static Projectiles":["Static","Shots"],
                     "Trajectories":["Paths"],"Effect Modifiers":["Effects"],
                     "Multicasts":["Multi","Cast"],"Target Selection":["Targets"]}
        lines = icon_labels.get(label,label.split(" ")) if language == "en" else wrap.get(label, [label[:2], label[2:]] if len(label) == 4 else [label])
        for j, line in enumerate(lines):
            font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf" if language == "en" else "C:/Windows/Fonts/msyhbd.ttc", 40)
            while draw.textbbox((0, 0), line, font=font)[2] > 108:
                font = font.font_variant(size=font.size-1)
            box = draw.textbbox((0, 0), line, font=font)
            y = size / 2 + (j - (len(lines) - 1) / 2) * 43
            draw.text(((size-box[0]-box[2])/2, y-(box[1]+box[3])/2), line, font=font, fill="#ffe4a6")
        x, y = i % 4 * size, i // 4 * size
        assert y + size <= sheet.height
        sheet.alpha_composite(tile, (x, y))
        ET.SubElement(elements, "Element", name=key+".tex", u1=str(x/512), u2=str((x+size)/512),
                      v1=str(1-(y+size)/512), v2=str(1-y/512))

    dest = root / "mod/images"
    converter = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/tools/bin/TextureConverter.exe")
    (root / "assets_src/localization").mkdir(exist_ok=True)
    sheet.save(root / "assets_src/localization" / (base+".png"))
    with TemporaryDirectory() as tmp:
        png = Path(tmp)/"sections.png"
        sheet.save(png)
        subprocess.run([str(converter), "--swizzle", "--format", "bc3", "--platform", "opengl", "--premultiply",
                        "-i", str(png), "-o", str(dest/(base+".tex"))], check=True)
    ET.ElementTree(atlas).write(dest/(base+".xml"), encoding="utf-8", xml_declaration=True)
