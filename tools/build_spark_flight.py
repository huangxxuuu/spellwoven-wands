"""Compile the approved spark preview strips into their own DST animation bank."""
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageChops
from build_art_assets import ROOT, compile_bank, frame

BANK = "nw_spark_flight"
source = ROOT / "docs/previews/spark-six"
build = ET.Element("Build", name=BANK)
animations = ET.Element("Anims")
images = {}

# The head is three times the original 50-unit canvas. Give each tail a
# shorter silhouette along its local +X flight axis.
for name, file, width, height, indices, size in (
    ("head", "head-6x64.png", 64, 64, (0, 1, 2, 3, 4, 5), (150, 150)),
    ("tail", "tail-3x48.png", 48, 24, (0, 0, 1, 1, 2, 2), (108, 84)),
):
    strip = Image.open(source / file).convert("RGBA")
    assert strip.size == (width * (max(indices) + 1), height)
    sequence = ET.SubElement(animations, "anim", name=name, root=BANK, framerate="30")
    for i, index in enumerate(indices):
        image = strip.crop((index * width, 0, (index + 1) * width, height))
        if name == "tail" and i:
            # ForceFacePoint turns +X toward the head. Sweep a feathered edge
            # from left to right, leaving the forward end lit until frame six.
            alpha = image.getchannel("A")
            left, _, right, _ = alpha.point(lambda a: 255 if a > 20 else 0).getbbox()
            feather = 6
            edge = left - feather + (right - left + feather) * i / len(indices)
            row = [round(255 * max(0, min(1, (x - edge) / feather))) for x in range(width)]
            mask = Image.new("L", image.size)
            mask.putdata(row * height)
            image.putalpha(ImageChops.multiply(alpha, mask))
        key = f"{name}_{i}"
        images[key] = image
        frame(build, key, key, (width, height))
        pose = ET.SubElement(sequence, "frame", x="0", y="0", w=str(size[0]), h=str(size[1]))
        ET.SubElement(pose, "element", name=key, frame="0", layername=name, z_index="0",
                      m_a=str(size[0] / width), m_b="0", m_c="0", m_d=str(size[1] / height),
                      m_tx="0", m_ty="0")

compile_bank(BANK, build, animations, images,
             Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools"))
