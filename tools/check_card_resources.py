"""Focused checks against shipped card textures and compiled animation clips."""
import json
import zipfile
from xml.etree import ElementTree as ET
from PIL import Image, ImageDraw
from lupa.lua51 import LuaRuntime
from build_art_assets import ROOT
from native_animation import NativeAnimation, read_build, read_animation, texture
from animation_atlas import validate_animation_archive, validate_ktex

vm=LuaRuntime(unpack_returned_tuples=True)
vm.globals().package.path=(ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
syntax=vm.eval('function(s,n) local f,e=loadstring(s,n);assert(f,e) end')
for path in (ROOT/'mod').rglob('*.lua'): syntax(path.read_text(encoding='utf8'),str(path))
vm.execute((ROOT/'tests/test_card_visuals.lua').read_text(encoding='utf8'))
vm.execute((ROOT/'tests/test_arsenal.lua').read_text(encoding='utf8'))
cards=vm.eval('require("nw/cards")'); visual=vm.eval('require("nw/card_visuals")')
def load_bank(path):
    validate_animation_archive(path)
    obj=NativeAnimation.__new__(NativeAnimation)
    with zipfile.ZipFile(path) as z:
        obj.build=read_build(z.read('build.bin'));obj.clips=read_animation(z.read('anim.bin'))
        obj.atlases=[texture(z.read(name)) for name in obj.build['atlases']]
    obj.cache={}
    return obj

shared=load_bank(ROOT/'mod/anim/nw_card_piles.zip')
layout_data=json.loads((ROOT/'assets_src/spell_cards_composed/v4_split_piles/manifest.json').read_text(encoding='utf8'))
layouts={row['key']:row for row in layout_data['layouts']}
assert len(layouts)==201 and len(shared.clips)==201
shared_names=set(shared.build['names'].values())
# Three standalone papers, three pile papers, six blocks, three shadows and a face placeholder.
assert shared_names==set(layout_data['materials'])|{'face'}
for clip in shared.clips:
    expected=layouts[clip['name']]['elements']
    elements=clip['frames'][0]['elements']
    assert len(elements)==len(expected)
    for element,(symbol,x,y) in zip(elements,expected):
        assert shared.build['names'][element[0]]==symbol
        assert abs(element[7]-x)<.001 and abs(element[8]-y)<.001
renderers={};clips_checked=0
for page in sorted({(c-1)//visual.page_size for c in cards.codes.values()}):
    obj=load_bank(ROOT/'mod/anim'/f'nw_card_faces_{page}.zip');renderers[page]=obj
    clips={x['name']:x for x in obj.clips}
    for ident,code in cards.codes.items():
        if (code-1)//visual.page_size!=page:continue
        if visual.cards[ident].art_id:
            assert visual.cards[visual.cards[ident].art_id].shape == visual.cards[ident].shape
            continue  # Explicit temporary native-symbol alias, not a missing clip.
        elements=clips['card_'+str(code)]['frames'][0]['elements']
        assert len(elements)==1 and obj.build['names'][elements[0][0]]=='face_'+ident
        clips_checked+=1
    assert len(clips)==sum(1 for ident,c in cards.codes.items() if (c-1)//visual.page_size==page and not visual.cards[ident].art_id)
# Confirm every client selector points at a compiled clip, including retired IDs.
ground=vm.eval('require("nw/ground_card")')
for ident,code in cards.codes.items():
    for n in (1,2,3,4,8,9,25):
        for packed in range(27):
            for separated in (False,True):
                name,resolved=ground.pose(code,n,packed,separated)
                assert name in layouts and resolved==ident

atlas_path=ROOT/'mod/images/inventoryimages/nw_icons.tex'
validate_ktex(atlas_path.read_bytes(),'nw_icons')
elements=ET.parse(atlas_path.with_suffix('.xml')).findall('./Elements/Element')
assert {e.attrib['name'] for e in elements}=={'nw_spell_'+i+'.tex' for i in cards.order.values()}|{'nw_wand.tex'}
rows=json.loads((ROOT/'assets_src/spell_cards_composed/v1/manifest.json').read_text(encoding='utf8'))['cards']
for row in rows:
    actual=Image.open(ROOT/'assets_src/art_v1/runtime'/('icon_'+row['id']+'.png'))
    approved=Image.open(ROOT/'assets_src/spell_cards_composed/v1/inventory_128'/(row['id']+'.png'))
    assert actual.size==(128,128),row['id']
    assert actual.tobytes()==approved.tobytes(),row['id']
for path in (ROOT/'mod/images/cards').glob('*.tex'):validate_ktex(path.read_bytes(),path.name)

# Render real compiled symbols, including the same cross-build face override
# used by AnimState. This catches placement/atlas errors hidden by source previews.
from PIL import ImageFont
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
review=Image.new('RGB',(1200,1480),'#333c35');draw=ImageDraw.Draw(review)
examples=[('fire','single_R'),('speed_up','single_H'),('repeat_2','single_N'),
          ('fire_hit','two_RH'),('fire_hit','three_RHR'),('fire_hit','medium_RHR_plain'),
          ('fire_hit','medium_RHR_hex'),('fire_hit','large_RHR_plain'),('fire_hit','large_RHR_one_hex'),
          ('fire_hit','large_RHR_hex_adjacent'),('fire_hit','large_RHR_hex_separated'),('speed_up','large_HNR_hex_separated')]
for index,(ident,name) in enumerate(examples):
    code=cards.codes[ident];faces=renderers[(code-1)//visual.page_size]
    out=Image.new('RGBA',(256,256))
    for element in reversed(shared.clip(name)['frames'][0]['elements']):
        key,frame,_,a,b,c,d,x,y,_=element
        assert (a,b,c,d)==(1,0,0,1)
        source=shared.build['names'][key]
        image,(sx,sy)=faces.symbol('face_'+ident) if source=='face' else shared.symbol(key,frame)
        image=Image.frombytes('RGBa',image.size,image.tobytes()).convert('RGBA')
        piece=Image.new('RGBA',out.size)
        piece.alpha_composite(image,(128+sx,136+sy))
        out.alpha_composite(piece.transform(out.size,Image.Transform.AFFINE,(1,0,-x,0,1,-y),Image.Resampling.BICUBIC))
    x=index%3*400;y=index//3*370
    out=out.resize((400,400),Image.Resampling.LANCZOS)
    review.paste(out,(x,y-30),out)
    draw.text((x+15,y+325),name,font=font,fill='#eee5cf')
review.save(ROOT/'test_reports/card_resources_compiled.png')
report={'passed':True,'public_icons_matched':len(rows),'inventory_elements':len(elements),'ground_clips':clips_checked,'shared_layouts':len(layouts),'shared_paper_assets':12,'shared_shadows':3,
        'lua_syntax':'passed','slot_order_and_compatibility':'passed','texture_headers_and_sampler_pages':'passed','full_game_tests':'not run'}
(ROOT/'test_reports/card_resources_validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print(report)
