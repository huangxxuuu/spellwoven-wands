"""Build reusable head/body/tail icon layers, never whole-wand combinations."""
import argparse
import json
import subprocess
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageChops
from lupa.lua51 import LuaRuntime
from animation_atlas import validate_ktex

ROOT=Path(__file__).resolve().parents[1]
RUNTIME=ROOT/'assets_src/art_v1/runtime'
DEFAULT_TOOLS=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")

def build(tools=DEFAULT_TOOLS, images=None, specs=None, layouts=None):
    vm=LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path=(ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
    visual=vm.eval('require("nw/visual")')
    if specs is None:
        manifest=json.loads((ROOT/'assets_src/art_v1/manifest.json').read_text(encoding='utf8'))
        specs,layouts=manifest['parts'],manifest['layouts']
    if images is None:
        images={key:Image.open(RUNTIME/'nw_parts'/f'{key}.png').convert('RGBA')
                for key in specs if key.startswith(('head_','body_','tail_'))}
    tiles={}
    for length,extent in [('short',56),('medium',60),('long',63)]:
        layers={}
        union=Image.new('L',(192,256))
        for part,im in images.items():
            slot=part.split('_')[0]
            if slot not in ('head','body','tail') or slot=='body' and not part.endswith('_'+length):continue
            sprite=im.resize(tuple(specs[part]['world_size']),Image.Resampling.LANCZOS)
            dx,dy=layouts[length][slot]
            layer=Image.new('RGBA',(192,256))
            layer.alpha_composite(sprite,(round(96+dx-sprite.width/2),round(128+dy-sprite.height/2)))
            layers[part]=layer
            union=ImageChops.lighter(union,layer.getchannel('A'))
        bounds=union.getbbox()
        width,height=bounds[2]-bounds[0],bounds[3]-bounds[1]
        # Every part uses the same transform, so sockets coincide for all looks.
        def rotate(layer):
            return layer.crop(bounds).resize((round(width*1.32),height),Image.Resampling.LANCZOS).rotate(-36,Image.Resampling.BICUBIC,expand=True)
        mask=rotate(Image.merge('RGBA',(union,union,union,union))).getchannel('A')
        rotated_bounds=mask.getbbox()
        w,h=rotated_bounds[2]-rotated_bounds[0],rotated_bounds[3]-rotated_bounds[1]
        scale=extent/max(w,h); size=(round(w*scale),round(h*scale))
        for part,layer in layers.items():
            piece=rotate(layer).crop(rotated_bounds).resize(size,Image.Resampling.LANCZOS)
            tile=Image.new('RGBA',(64,64));tile.alpha_composite(piece,((64-size[0])//2,(64-size[1])//2))
            key=part if part.startswith('body_') else part+'_'+length
            tiles[key]=tile
    assert len(tiles)==162
    atlas=Image.new('RGBA',(1024,1024));xml=ET.Element('Atlas')
    ET.SubElement(xml,'Texture',filename='nw_wand_parts.tex');elements=ET.SubElement(xml,'Elements')
    def entry(name,x,y):
        ET.SubElement(elements,'Element',name=name+'.tex',u1=str(x/1024),u2=str((x+64)/1024),v1=str(1-(y+64)/1024),v2=str(1-y/1024))
    # A shared fallback serves third-party UIs that only read a flat image.
    # Native ItemTile and RecipeTile draw the three actual parts instead.
    atlas.alpha_composite(Image.open(RUNTIME/'icon_wand_icon.png').convert('RGBA'),(0,0))
    for i,(key,tile) in enumerate(sorted(tiles.items()),1):
        x,y=i%16*64,i//16*64;atlas.alpha_composite(tile,(x,y));entry(key,x,y)
    for code in range(visual.count):
        for broken in (False,True):entry(visual.icon(code,broken),0,0)
    dest=ROOT/'mod/images/inventoryimages';dest.mkdir(parents=True,exist_ok=True)
    source=RUNTIME/'nw_wand_parts.png';atlas.save(source)
    ET.ElementTree(xml).write(dest/'nw_wand_parts.xml',encoding='utf8',xml_declaration=True)
    subprocess.run([str(tools/'tools/bin/TextureConverter.exe'),'--swizzle','--format','bc3','--platform','opengl',
        '--premultiply','-i',str(source),'-o',str(dest/'nw_wand_parts.tex')],check=True,capture_output=True)
    validate_ktex((dest/'nw_wand_parts.tex').read_bytes(),'nw_wand_parts')
    print(f'Built {len(tiles)} shared layers for {visual.count*2} wand appearances')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--tools',type=Path,default=DEFAULT_TOOLS)
    build(parser.parse_args().tools)
