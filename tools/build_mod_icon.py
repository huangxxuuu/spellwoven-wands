"""Pack the homepage's existing crossed-wand artwork as a DST mod icon."""
from pathlib import Path
import subprocess
from xml.etree import ElementTree as ET

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "site/dist/assets"
PREVIEW = ROOT / "assets_src/mod_icon.png"
CONVERTER = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/tools/bin/TextureConverter.exe")

# Match the rear/front stacking, relative heights and rotations in style.css.
# PIL's rotation sign is the opposite of CSS. Keep the source artwork intact.
canvas = Image.new("RGBA", (1024, 1024))
for name, height, center_x, angle in (
    ("ember", .75, .45, 28),
    ("jade", .96, .53, -41),
):
    with Image.open(SOURCE / (name + ".webp")) as source:
        wand = source.convert("RGBA")
    h = round(1024 * height)
    wand = wand.resize((round(wand.width * h / wand.height), h), Image.Resampling.LANCZOS)
    wand = wand.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    canvas.alpha_composite(wand, (round(1024 * center_x - wand.width / 2), round(512 - wand.height / 2)))

art = ImageOps.contain(canvas.crop(canvas.getbbox()), (240, 240), Image.Resampling.LANCZOS)
icon = Image.new("RGBA", (256, 256))
icon.alpha_composite(art, ((256 - art.width) // 2, (256 - art.height) // 2))
icon.save(PREVIEW)
subprocess.run([
    str(CONVERTER), "--swizzle", "--format", "bc3", "--platform", "opengl", "--premultiply",
    "-i", str(PREVIEW), "-o", str(ROOT / "mod/modicon.tex"),
], check=True, capture_output=True, timeout=30)
atlas = ET.Element("Atlas")
ET.SubElement(atlas, "Texture", filename="modicon.tex")
ET.SubElement(ET.SubElement(atlas, "Elements"), "Element", name="modicon.tex", u1="0", u2="1", v1="0", v2="1")
ET.ElementTree(atlas).write(ROOT / "mod/modicon.xml", encoding="utf-8", xml_declaration=True)
print("Built homepage crossed-wand mod icon:", PREVIEW)
