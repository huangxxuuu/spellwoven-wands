"""Compile the selected A3/B2 painting into DST world sprites and UI atlases."""
from pathlib import Path
import math
import subprocess
from xml.etree import ElementTree as ET
from PIL import Image, ImageOps, ImageDraw, ImageFilter
from build_art_assets import ROOT, anim, compile_bank, frame

tools=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
master=Image.open(ROOT/"assets_src/stations/stations.png").convert("RGBA")
assert master.size==(1774,887)
bank="nw_stations"
build=ET.Element("Build",name=bank)
animations=ET.Element("Anims")
images={}
def sprite(box):
    art=master.crop(box)
    art.putalpha(art.getchannel("A").point(lambda a: 0 if a<9 else a))
    return art.resize((round(art.width*320/art.height),320),Image.Resampling.LANCZOS)
images["engraver"]=sprite((60,40,821,848))
images["furnace"]=sprite((1018,93,1710,832))
# The native researchlab2 idle frame uses a 212x55 machine_shadow symbol:
# broken horizontal ink strokes with transparent turf between strokes.
from io import BytesIO
import resvg_py
shadow=Image.open(ROOT/"assets_src/stations/researchlab2_machine_shadow.png").convert("RGBA")
soil=Image.open(BytesIO(resvg_py.svg_to_bytes(svg_path=str(ROOT/"assets_src/stations/foot_soil.svg")))).convert("RGBA")
icons=images.copy()
images["workbench"]=Image.open(ROOT/"assets_src/art_v1/runtime/nw_objects/workbench.png").convert("RGBA")
footprints={
    "workbench":((-3,189,259,252),[(28,217,44),(182,243,53),(233,208,34),(90,190,30)]),
    "engraver":((-2,264,299,322),[(71,310,60),(260,298,54),(30,291,42)]),
    "furnace":((-8,258,307,326),[(66,306,74),(246,305,77)]),
}
def grounded(art,name):
    margin=16
    out=Image.new("RGBA",(art.width+margin*2,art.height+margin*2))
    (left,top,right,bottom),feet=footprints[name]
    texture=ImageOps.mirror(shadow) if name=="engraver" else shadow
    out.alpha_composite(texture.resize((right-left,bottom-top),Image.Resampling.LANCZOS),(margin+left,margin+top))
    out.alpha_composite(art,(margin,margin))
    for i,(x,y,width) in enumerate(feet):
        patch=soil if i%2==0 else ImageOps.mirror(soil)
        patch=patch.resize((width,round(width*.25)),Image.Resampling.LANCZOS)
        out.alpha_composite(patch,(margin+x-width//2,margin+y-patch.height//2))
    return out
for name,art in images.items():
    frame(build,name,name,art.size,(0,-88 if name=="workbench" else -140))
    anim(animations,name,bank,[(name,0,0)])

# An additive light pass over the hanging gem and inner rim. All phases
# share the camera, pivot and stone silhouette of the idle painting.
factor=320/739
def point(x,y):return ((x-1018)*factor,(y-93)*factor)
def active_frame(phase,flash):
    base=images["furnace"]
    light=Image.new("RGBA",base.size)
    draw=ImageDraw.Draw(light)
    glow=.7+.3*math.cos(phase)
    draw.polygon([point(x,y) for x,y in [(1394,246),(1413,248),(1435,292),(1395,365),(1355,292),(1377,247)]],
                 fill=(54,244,234,round(40+72*glow)))
    cx,cy=point(1376,435)
    rx,ry=60,12
    draw.ellipse((cx-rx,cy-ry,cx+rx,cy+ry),fill=(15,183,180,round(100+75*glow)))
    pts=[]
    for j in range(110):
        t=j/109
        angle=phase+t*math.tau*1.6
        pts.append((cx+rx*.87*t*math.cos(angle),cy+ry*.85*t*math.sin(angle)))
    draw.line(pts, fill=(176,255,240,235),width=3 if flash else 2)
    out=base.copy()
    out.alpha_composite(light.filter(ImageFilter.GaussianBlur(4 if flash else 3)))
    out.alpha_composite(light)
    return out
for name,count,fps in [("active",8,8),("pulse",3,18)]:
    sequence=ET.SubElement(animations,"anim",name=name,root=bank,framerate=str(fps))
    # A single symbol with multiple UV frames keeps the station centered.
    symbol=ET.SubElement(build,"Symbol",name=name)
    for i in range(count):
        key=f"{name}_{i}"
        images[key]=active_frame(math.tau*i/count,name=="pulse")
        w,h=images[key].size
        ET.SubElement(symbol,"Frame",framenum=str(i),duration="1",image=key,x="0",y="-140",w=str(w),h=str(h))
        f=ET.SubElement(sequence,"frame",x="0",y="-140",w=str(w),h=str(h))
        ET.SubElement(f,"element",name=name,frame=str(i),layername=name,z_index="0",m_a="1",m_b="0",m_c="0",m_d="1",m_tx="0",m_ty="0")
for name in ("engraver","furnace","workbench"):
    art=images[name]
    animations.find(f"anim[@name='{name}']")[0].attrib.update(x="0",y="-88" if name=="workbench" else "-140",w=str(art.width),h=str(art.height))
# Pad all frames equally so neither the feet nor the crystal jump between poses.
for key,art in list(images.items()):
    images[key]=grounded(art,key if key in footprints else "furnace")
for symbol_frame in build.findall("./Symbol/Frame"):
    w,h=images[symbol_frame.get("image")].size
    symbol_frame.attrib.update(w=str(w),h=str(h))
for seq in animations:
    key=seq.get("name")
    w,h=images[key if key in footprints else "furnace"].size
    for f in seq:
        f.attrib.update(w=str(w),h=str(h))
compile_bank(bank,build,animations,images,tools)
atlas=ET.Element("Atlas")
ET.SubElement(atlas,"Texture",filename="nw_stations.tex")
entries=ET.SubElement(atlas,"Elements")
sheet=Image.new("RGBA",(512,256))
for key,source,x,size in [("nw_engraver","engraver",0,64),("nw_disassembler","furnace",64,64),("nw_engraver_station","engraver",256,256)]:
    img=ImageOps.contain(icons[source],(round(size*.90),round(size*.90)),Image.Resampling.LANCZOS)
    sheet.alpha_composite(img,(x+(size-img.width)//2,(size-img.height)//2))
    ET.SubElement(entries,"Element",name=key+".tex",u1=str(x/512),u2=str((x+size)/512),v1=str(1-size/256),v2="1")
dest=ROOT/"mod/images/inventoryimages"
ET.ElementTree(atlas).write(dest/"nw_stations.xml",encoding="utf8")
png=ROOT/"dist/intermediate/nw_stations.png";sheet.save(png)
subprocess.run([str(tools/"tools/bin/TextureConverter.exe"),"--swizzle","--format","bc3","--platform","opengl","--premultiply","-i",str(png),"-o",str(dest/"nw_stations.tex")],check=True)
# Relative sizes match the prefabs: workbench scales its 256px frame by 1.48.
preview=Image.new("RGBA",(810,310),"#514e3a")
for index,(img,scale) in enumerate([(images["workbench"],1.48),
                                     (images["engraver"],1),(images["active_2"],1)]):
    factor=.68*scale
    img=img.resize((round(img.width*factor),round(img.height*factor)),Image.Resampling.LANCZOS)
    preview.alpha_composite(img,(135+270*index-img.width//2,281-img.height))
preview.convert("RGB").save(ROOT/"assets_src/stations/lineup.png")
