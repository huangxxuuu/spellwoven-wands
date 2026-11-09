"""Export the approved wand-and-spell-card artwork for Workshop and DST."""
from pathlib import Path
import subprocess
from xml.etree import ElementTree as ET

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ARTWORK = ROOT / "assets_src/workshop_table_icon_v7"
PREVIEW = ROOT / "assets_src/mod_icon.png"
CONVERTER = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/tools/bin/TextureConverter.exe")

def export_icon(language, name):
    with Image.open(ARTWORK / language / "source.png") as source:
        if source.width != source.height:
            raise ValueError("The approved mod icon source must be square.")
        artwork = source.convert("RGBA")

    # Workshop uses a larger PNG; DST's list uses a 256px compiled texture.
    # Resize the complete approved composition without cropping or recoloring.
    if language == "zh":
        artwork.resize((512, 512), Image.Resampling.LANCZOS).convert("RGB").save(PREVIEW, optimize=True)
        if PREVIEW.stat().st_size >= 1024 * 1024:
            raise ValueError("Workshop preview must remain below 1 MiB.")
    game_icon = ARTWORK / language / "game_256.png"
    artwork.resize((256, 256), Image.Resampling.LANCZOS).save(game_icon, optimize=True)
    subprocess.run([
        str(CONVERTER), "--swizzle", "--format", "bc3", "--platform", "opengl", "--premultiply",
        "-i", str(game_icon), "-o", str(ROOT / "mod" / (name + ".tex")),
    ], check=True, capture_output=True, timeout=30)
    atlas = ET.Element("Atlas")
    ET.SubElement(atlas, "Texture", filename=name + ".tex")
    ET.SubElement(ET.SubElement(atlas, "Elements"), "Element", name=name + ".tex", u1="0", u2="1", v1="0", v2="1")
    ET.ElementTree(atlas).write(ROOT / "mod" / (name + ".xml"), encoding="utf-8", xml_declaration=True)
    print("DST icon:", ROOT / "mod" / (name + ".tex"))


def main():
    export_icon("zh", "modicon")
    export_icon("en", "modicon_en")
    print("Workshop preview:", PREVIEW)


if __name__ == "__main__":
    main()
