"""Crop/size the approved generated wooden panel and export nine real textures."""
from pathlib import Path
from xml.etree import ElementTree as ET
import subprocess
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
art=ROOT/'assets_src/hud'
source=Image.open(art/'frame_source.png').convert('RGBA')
bounds=source.getchannel('A').point(lambda a:255 if a>80 else 0).getbbox()
source=source.crop(bounds).resize((256,256),Image.Resampling.LANCZOS)
source.save(art/'nw_frame.png')
atlas=ET.Element('Atlas');ET.SubElement(atlas,'Texture',filename='nw_frame.tex')
entries=ET.SubElement(atlas,'Elements')
edges=(0,24,232,256)
for row in range(3):
    for col in range(3):
        x1,x2=edges[col:col+2];y1,y2=edges[row:row+2]
        ET.SubElement(entries,'Element',name=f'frame_{row+1}_{col+1}.tex',
            u1=str(x1/256),u2=str(x2/256),v1=str(1-y2/256),v2=str(1-y1/256))
dest=ROOT/'mod/images'
ET.ElementTree(atlas).write(dest/'nw_frame.xml',encoding='utf-8',xml_declaration=True)
converter=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/tools/bin/TextureConverter.exe")
subprocess.run([str(converter),'--swizzle','--format','bc3','--platform','opengl','--premultiply',
    '-i',str(art/'nw_frame.png'),'-o',str(dest/'nw_frame.tex')],check=True)
print('PASS 9 wooden frame regions, no native white side-strip textures')
