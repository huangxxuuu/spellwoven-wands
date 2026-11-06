"""Extract survival hand-weapon reference data and its inventory art from the installed DST bundles."""
import argparse, re, struct, zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
tools=argparse.ArgumentParser()
tools.add_argument('--game',type=Path,default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
game=tools.parse_args().game
bundles=game/'data/databundles'
scripts=zipfile.ZipFile(bundles/'scripts.zip')
images=zipfile.ZipFile(bundles/'images.zip')
def script(path):
    return scripts.read('scripts/'+path).decode('utf8').replace('\r','')
catalog=script('screens/redux/scrapbookdata.lua')
lang=dict(re.findall(r'msgctxt "STRINGS.NAMES\.([^"]+)"\nmsgid "[^"]*"\nmsgstr "([^"]*)"',script('languages/chinese_s.po')))
items={}
for row in catalog.splitlines():
    pid=re.search(r'prefab="([^"]+)"',row)
    dmg=re.search(r'weapondamage="?([\d.]+)',row)
    if not (pid and dmg and 'type="item"' in row):continue
    key=pid[1];damage=float(dmg[1])
    if damage<=0 or 'subcat="slingshotammo"' in row or key.startswith(('saddle_','blowdart_','slingshot','cannonball_')):continue
    if 'weaponrange=' in row and key not in ('whip','bullkelp_root','pocketwatch_weapon','houndstooth_blowpipe'):continue
    if key=='houndstooth_blowpipe':damage=10 # empty weapon's melee mode
    items[key]=(damage,re.search(r'tex="([^"]+)"',row)[1],re.findall(r'"(\w+)"',(re.search(r'toolactions=\{([^}]+)',row) or ['', ''])[1]))
tuning=script('tuning.lua')
# The scrapbook rounds these two variable-damage entries to "59-89".
for key in ('spear_wathgrithr_lightning','spear_wathgrithr_lightning_charged'):
    factor=re.search(r'\b'+key.upper()+r'_DAMAGE\s*=\s*wilson_attack\s*\*\s*([\d.]+)',tuning)[1]
    _,icon,actions=items[key]
    items[key]=(34*float(factor),icon,actions)
lance=re.search(r'YOTH_LANCE_ATTACK_DAMAGE\s*=\s*([^,\n]+)',tuning)[1]
for id,damage in [('propsign',1),('carnivalgame_golfclub',17),('yoth_knightstick',17),('yoth_lance',34*float(lance.split('*')[1]) if 'wilson_attack' in lance else float(lance))]:
    items[id]=(damage,id+'.tex',[])
pillow_stats=dict(re.findall(r'^    (\w+) =\n    \{\n        strengthmult = ([\d.]+)',script('prefabs/pillow_defs.lua'),re.M))
for mat in pillow_stats:
    key='handpillow_'+mat
    items[key]=(0,key+'.tex',[])
entries={}
for i in range(1,5):
    atlas='images/inventoryimages'+str(i)
    root=ET.fromstring(images.read(atlas+'.xml'))
    tex=images.read(atlas+'.tex')
    header=struct.unpack_from('<I',tex,4)[0];levels=(header>>13)&31
    w,h,_,size=struct.unpack_from('<HHHI',tex,8);offset=8+10*levels
    fmt=(header>>4)&31
    pixels=Image.frombytes('RGBA',(w,h),tex[offset:offset+size],'bcn',{0:1,2:3}[fmt]).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    for e in root.findall('./Elements/Element'):
        a=e.attrib
        if a['name'] in [v[1] for v in items.values()]:
            entries[a['name']]=pixels.crop(tuple(round(n) for n in (float(a['u1'])*w,(1-float(a['v2']))*h,float(a['u2'])*w,(1-float(a['v1']))*h)))
destination=ROOT/'mod/scripts/nw/weapon_catalog.lua'
if destination.exists():
    previous=re.findall(r'^    \{"([^"]+)"',destination.read_text('utf8'),re.M)
    current=sorted(items.keys()-{'spear','glasscutter','axe'})
    if previous!=current:
        raise ValueError('Native roster changed. Preserve the published card codes before updating the catalog.')
rows=['-- Stable card order. Append future native weapons rather than renumbering saved cards.','return {']
for key,(damage,tex,acts) in sorted(items.items()):
    if key in ('axe','glasscutter','spear'):continue # already carry stable IDs
    if key.startswith(('farm_hoe','golden_farm_hoe','fumarole_farm_hoe','merm_tool')):acts.append('TILL')
    if key in ('pitchfork','goldenpitchfork'):acts.append('TERRAFORM')
    tag='thrust' if any(t in key for t in ['spear','lance','trident','pitchfork','cane','whip']) else 'slash'
    props=','.join('"'+a+'"' for a in acts if a in ('HAMMER','DIG','CHOP','MINE','TILL','SCYTHE','TERRAFORM','NET'))
    override=',"'+tex+'"' if tex!=key+'.tex' else ''
    rows.append('    {"%s","%s",%g,"%s",{%s}%s},'%(key,lang.get(key.upper(),'道具招牌' if key=='propsign' else key),damage,tag,props,override))
    if tex not in entries:raise ValueError((key,tex))
    im=entries[tex].convert('RGBA')
    im.save(ROOT/f'assets_src/art_v1/originals/edge_{key}.png')
rows.append('}')
destination.write_text('\n'.join(rows)+'\n','utf8')
print('Exported',len(rows)-3,'additional weapons. Lance baseline:',lance)
