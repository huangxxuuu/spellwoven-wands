"""Build guide illustrations from the full building sprites, not 64px inventory icons."""
from pathlib import Path
from xml.etree import ElementTree as ET
import subprocess
from PIL import Image,ImageOps

ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'assets_src/art_v1/runtime/nw_stations'
atlas=Image.new('RGBA',(512,512));xml=ET.Element('Atlas')
ET.SubElement(xml,'Texture',filename='nw_guide.tex');els=ET.SubElement(xml,'Elements')
for i,(name,file) in enumerate([('nw_workbench','workbench'),('nw_engraver','engraver'),('nw_disassembler','furnace')]):
    im=Image.open(source/(file+'.png')).convert('RGBA')
    im=ImageOps.contain(im.crop(im.getchannel('A').getbbox()),(240,240),Image.Resampling.LANCZOS)
    x,y=(i%2)*256,(i//2)*256
    atlas.alpha_composite(im,(x+(256-im.width)//2,y+(256-im.height)//2))
    ET.SubElement(els,'Element',name=name+'.tex',u1=str(x/512),u2=str((x+256)/512),v1=str(1-(y+256)/512),v2=str(1-y/512))
png=ROOT/'assets_src/art_v1/runtime/nw_guide.png';atlas.save(png)
dest=ROOT/'mod/images'
ET.ElementTree(xml).write(dest/'nw_guide.xml',encoding='utf8',xml_declaration=True)
converter=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/tools/bin/TextureConverter.exe")
subprocess.run([str(converter),'--swizzle','--format','bc3','--platform','opengl','--premultiply','-i',str(png),'-o',str(dest/'nw_guide.tex')],check=True,capture_output=True)
print('PASS: three 256px guide illustrations')
