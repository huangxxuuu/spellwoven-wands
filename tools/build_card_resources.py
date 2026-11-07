"""Install approved card compositions without rebuilding projectile/world effects."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image
from lupa.lua51 import LuaRuntime
from build_art_assets import ROOT, RUNTIME, ORIGINALS
from compose_spell_cards import OUT, KINDS, prepare_frames, fitted_subject
from animation_atlas import validate_ktex

PAGE_SIZE = 48
INVENTORY_SIZE = 128

def texture(images, dest, name, tile, tools):
    atlas = Image.new('RGBA', (tile * 8, tile * 8))
    root = ET.Element('Atlas')
    ET.SubElement(root, 'Texture', filename=name+'.tex')
    elements = ET.SubElement(root, 'Elements')
    assert len(images) <= 64
    for i, (key, im) in enumerate(images):
        x, y = (i % 8) * tile, (i // 8) * tile
        atlas.alpha_composite(im.resize((tile, tile), Image.Resampling.LANCZOS), (x, y))
        ET.SubElement(elements, 'Element', name=key+'.tex', u1=str(x/atlas.width),
                      u2=str((x+tile)/atlas.width), v1=str(1-(y+tile)/atlas.height), v2=str(1-y/atlas.height))
    dest.mkdir(parents=True, exist_ok=True)
    source = RUNTIME/(name+'.png'); atlas.save(source)
    ET.ElementTree(root).write(dest/(name+'.xml'), encoding='utf-8', xml_declaration=True)
    subprocess.run([str(tools/'tools/bin/TextureConverter.exe'), '--swizzle', '--format', 'bc3',
                    '--platform', 'opengl', '--premultiply', '-i', str(source), '-o', str(dest/(name+'.tex'))],
                   check=True, capture_output=True, timeout=60)
    validate_ktex((dest/(name+'.tex')).read_bytes(), name)
    return root, atlas

def build(tools, inventory_only=False):
    RUNTIME.mkdir(parents=True, exist_ok=True)
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
    cards = vm.eval('require("nw/cards")'); definitions = vm.eval('require("nw/definitions").spells')
    ids = list(cards.order.values()); codes = dict(cards.codes.items())
    rows = {x['id']:x for x in json.loads((OUT/'manifest.json').read_text(encoding='utf8'))['cards']}
    assert set(rows) <= set(ids)
    frames = prepare_frames(); albums = {}; icons = {}; classes = {}; sources = {}
    for ident in ids:
        if ident in rows:
            row = rows[ident]; source = ROOT/row['source']
            assert hashlib.sha256(source.read_bytes()).hexdigest() == row['source_sha256'], ident
            if not inventory_only: albums[ident] = Image.open(OUT/'album'/f'{ident}.png').convert('RGBA')
            icons[ident] = Image.open(OUT/f'inventory_{INVENTORY_SIZE}'/f'{ident}.png').convert('RGBA')
            classes[ident] = row['primary_class']; sources[ident] = row['source']
        else:
            # Hidden/legacy IDs remain loadable, using their existing art inside the new frame.
            kind = 'modifier' if definitions[ident].kind == 'modifier' else 'control' if ident in ('trigger_hit','trigger_timer') else 'basic'
            source = ORIGINALS/(ident+'.png')
            if not inventory_only:
                art, _ = fitted_subject(source, frames[kind][3], False)
                image = frames[kind][1].copy(); image.alpha_composite(art); image.alpha_composite(frames[kind][2])
                albums[ident] = image
            small, safe = frames[kind][4:6]
            glyph, _ = fitted_subject(source, safe.resize((1024,1024), Image.Resampling.NEAREST), False)
            image = small.copy(); image.alpha_composite(glyph.resize(image.size, Image.Resampling.LANCZOS))
            icons[ident] = image.resize((INVENTORY_SIZE,INVENTORY_SIZE), Image.Resampling.LANCZOS)
            classes[ident] = kind; sources[ident] = source.relative_to(ROOT).as_posix()

    # Preserve the existing inventory atlas name and each element name used by UI/recipes.
    extent=16*INVENTORY_SIZE
    atlas = Image.new('RGBA', (extent,extent)); xml = ET.Element('Atlas')
    ET.SubElement(xml,'Texture',filename='nw_icons.tex'); els = ET.SubElement(xml,'Elements')
    wand = Image.open(RUNTIME/'icon_wand_icon.png').convert('RGBA')
    for i, (ident, im) in enumerate(list(icons.items())+[('wand_icon',wand)]):
        x,y = i%16*INVENTORY_SIZE+(INVENTORY_SIZE-im.width)//2,i//16*INVENTORY_SIZE+(INVENTORY_SIZE-im.height)//2
        atlas.alpha_composite(im,(x,y)); im.save(RUNTIME/f'icon_{ident}.png')
        key = 'nw_wand' if ident=='wand_icon' else 'nw_spell_'+ident
        ET.SubElement(els,'Element',name=key+'.tex',u1=str(x/extent),u2=str((x+im.width)/extent),v1=str(1-(y+im.height)/extent),v2=str(1-y/extent))
    assert len(icons)+1<=256
    atlas.save(RUNTIME/'nw_icons.png'); dest=ROOT/'mod/images/inventoryimages'
    ET.ElementTree(xml).write(dest/'nw_icons.xml',encoding='utf-8',xml_declaration=True)
    subprocess.run([str(tools/'tools/bin/TextureConverter.exe'),'--swizzle','--format','bc3','--platform','opengl','--premultiply',
                    '-i',str(RUNTIME/'nw_icons.png'),'-o',str(dest/'nw_icons.tex')],check=True,capture_output=True,timeout=60)
    validate_ktex((dest/'nw_icons.tex').read_bytes(),'nw_icons')
    print('inventory:',len(icons),'cards',flush=True)
    if inventory_only:
        path=ROOT/'test_reports/card_resources.json'
        report=json.loads(path.read_text(encoding='utf8'))
        report.update(inventory_pixels=INVENTORY_SIZE,inventory_atlas=[extent,extent])
        path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
        print('PASS: inventory only; ground resources preserved')
        return

    # Native symbols share paper layers and bottom blocks across every spell.
    from build_split_card_ground import compile_ground
    archives=compile_ground(tools,albums,classes,codes)
    lines=['-- Generated by tools/build_card_resources.py. Stable spell IDs preserve saves.', 'local M={page_size='+str(PAGE_SIZE)+',cards={']
    for ident in ids:
        lines.append('    ["'+ident+'"]={shape="'+KINDS[classes[ident]]+'",primary_class="'+classes[ident]+'"},')
    lines+=['}}','return M','']
    (ROOT/'mod/scripts/nw/card_visuals.lua').write_text('\n'.join(lines),encoding='utf8')
    report={'public_cards':len(rows),'compatible_cards':len(ids)-len(rows),'inventory_cards':len(ids),'album_runtime_export':False,'inventory_pixels':INVENTORY_SIZE,'inventory_atlas':[extent,extent],
            'shared_paper_assets':12,'shared_shadow_assets':3,'shared_pile_layouts':201,
            'ground_page_size':PAGE_SIZE,'archives':archives,'sources':sources,'runtime_connected':True}
    (ROOT/'test_reports/card_resources.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('PASS: approved card resources installed into mod/')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--tools',type=Path,default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools"))
    parser.add_argument('--inventory-only',action='store_true');args=parser.parse_args()
    build(args.tools,args.inventory_only)
