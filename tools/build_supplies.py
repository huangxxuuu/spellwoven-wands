"""Build material sprites and inventory icons for supplies, coffer and workbench."""
from io import BytesIO
from pathlib import Path
import subprocess
from xml.etree import ElementTree as ET

from PIL import Image, ImageOps
import resvg_py
from build_art_assets import ROOT, anim, compile_bank, frame, resize

tools = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
build = ET.Element("Build", name="nw_supplies")
animations = ET.Element("Anims")
images = {}
inventory_images = {}
ET.register_namespace("", "http://www.w3.org/2000/svg")
for path in sorted((ROOT / "assets_src/supplies").glob("*.svg")):
    source = ET.parse(path).getroot()
    # Keep the original 2px/unit body size and position; add margins for ink.
    encoded = resvg_py.svg_to_bytes(svg_string=ET.tostring(source, encoding="unicode"))
    sprite = Image.open(BytesIO(encoded)).convert("RGBA")
    images[path.stem] = sprite
    # The compiler uses PNG dimensions for vertices; Frame w/h do not resize it.
    # Body still starts at y=-124; the extended footprint reaches below y=0.
    w,h=sprite.size
    cy=20-h/2
    frame(build,path.stem,path.stem,(w,h),(0,cy))
    anim(animations,path.stem,"nw_supplies",[(path.stem,0,0)])
    animations[-1][0].attrib.update(x="0",y=str(cy),w=str(w),h=str(h))
    source = ET.parse(path).getroot()
    source.remove(next(node for node in source if node.get("id") == "ground-shadow"))
    source.attrib.update(viewBox="0 0 64 64", width="128", height="128")
    encoded = resvg_py.svg_to_bytes(svg_string=ET.tostring(source, encoding="unicode"))
    inventory_images[path.stem] = Image.open(BytesIO(encoded)).convert("RGBA")
compile_bank("nw_supplies",build,animations,images,tools)
images = inventory_images
images["nw_workbench"] = resize("workbench",(64,64))
for name in ("nw_dustbox", "nw_dustbox_open"):
    images[name] = Image.open(ROOT / "assets_src/dustbox" / (name+".png")).convert("RGBA")
sheet = Image.new("RGBA",(1024,256))
atlas = ET.Element("Atlas")
ET.SubElement(atlas,"Texture",filename="nw_supplies.tex")
entries = ET.SubElement(atlas,"Elements")
for index, (name,sprite) in enumerate(images.items()):
    sheet.alpha_composite(sprite.resize((64,64),Image.Resampling.LANCZOS),(index*64,0))
    ET.SubElement(entries,"Element",name=name+".tex",u1=str(index*64/sheet.width),
                  u2=str((index+1)*64/sheet.width),v1="0.75",v2="1")
# The native pinbar uses the atlas element's pixel size; the station filter
# scales the same element to its button. Keep a tight inset for both.
station=resize("workbench",(256,256))
station=ImageOps.contain(station.crop(station.getchannel("A").getbbox()),(210,210),Image.Resampling.LANCZOS)
x=len(images)*64
sheet.alpha_composite(station,(x+(256-station.width)//2,(256-station.height)//2))
ET.SubElement(entries,"Element",name="nw_workbench_station.tex",u1=str(x/sheet.width),
              u2=str((x+256)/sheet.width),v1="0",v2="1")
png = ROOT / "dist/intermediate/nw_supplies.png"
sheet.save(png)
dest = ROOT / "mod/images/inventoryimages"
ET.ElementTree(atlas).write(dest/"nw_supplies.xml",encoding="utf-8",xml_declaration=True)
subprocess.run([str(tools/"tools/bin/TextureConverter.exe"),"--swizzle","--format","bc3","--platform",
                "opengl","--premultiply","-i",str(png),"-o",str(dest/"nw_supplies.tex")],check=True)
