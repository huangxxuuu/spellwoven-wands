"""Prepare generated HUD icons and code-native circular progress indicators."""
from pathlib import Path
from xml.etree import ElementTree as ET
import subprocess
from PIL import Image, ImageOps, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
source=Image.open(ROOT/'assets_src/hud/status_source.png').convert('RGBA')
sprites={}
for i,name in enumerate(('readonly','edit','cast')):
    part=source.crop((i*source.width//3,0,(i+1)*source.width//3,source.height))
    # Disregard almost transparent generation margins when fitting tiny HUD art.
    bounds=part.getchannel('A').point(lambda a:255 if a>80 else 0).getbbox()
    icon=ImageOps.contain(part.crop(bounds),(56,56),Image.Resampling.LANCZOS)
    tile=Image.new('RGBA',(64,64))
    tile.alpha_composite(icon,((64-icon.width)//2,(64-icon.height)//2))
    sprites[name]=tile
for step in range(61):
    ring=Image.new('RGBA',(256,256))
    draw=ImageDraw.Draw(ring)
    draw.ellipse((16,16,240,240),outline=(12,10,8,255),width=24)
    draw.ellipse((24,24,232,232),outline=(70,60,43,255),width=12)
    if step:
        draw.arc((24,24,232,232),-90,-90+360*step/60,fill=(232,190,100,255),width=12)
    sprites['ring_%02d'%step]=ring.resize((64,64),Image.Resampling.LANCZOS)
sheet=Image.new('RGBA',(512,512))
atlas=ET.Element('Atlas');ET.SubElement(atlas,'Texture',filename='nw_hud.tex')
entries=ET.SubElement(atlas,'Elements')
for i,(name,im) in enumerate(sprites.items()):
    x,y=i%8*64,i//8*64
    sheet.alpha_composite(im,(x,y))
    ET.SubElement(entries,'Element',name=name+'.tex',u1=str(x/512),u2=str((x+64)/512),
                  v1=str(1-(y+64)/512),v2=str(1-y/512))
png=ROOT/'assets_src/hud/nw_hud.png';sheet.save(png)
dest=ROOT/'mod/images';dest.mkdir(exist_ok=True)
ET.ElementTree(atlas).write(dest/'nw_hud.xml',encoding='utf-8',xml_declaration=True)
converter=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/tools/bin/TextureConverter.exe")
subprocess.run([str(converter),'--swizzle','--format','bc3','--platform','opengl','--premultiply',
                '-i',str(png),'-o',str(dest/'nw_hud.tex')],check=True)
print('PASS',len(sprites),'HUD atlas elements; three icons and 61 clockwise progress states')
