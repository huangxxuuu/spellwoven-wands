"""Check actual runtime atlas/compiled resources; render a game-size assembly review."""
import hashlib
import io
import json
import math
import struct
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets_src/art_v1'
RUNTIME=ART/'runtime'
manifest=json.loads((ART/'manifest.json').read_text())
atlas=Image.open(RUNTIME/'nw_icons.png').convert('RGBA')
assert atlas.size==(2048,2048)
elements=ET.parse(ROOT/'mod/images/inventoryimages/nw_icons.xml').findall('./Elements/Element')
assert len(elements)==221 and len({e.attrib['name'] for e in elements})==221
inventory_count=len(elements)
rects=set();hashes={}
for e in elements:
    a=e.attrib
    size=64 if a['name']=='nw_wand.tex' else 128
    x,y=round(float(a['u1'])*atlas.width),round((1-float(a['v2']))*atlas.height)
    assert round((float(a['u2'])-float(a['u1']))*atlas.width)==size
    assert round((float(a['v2'])-float(a['v1']))*atlas.height)==size
    assert (x,y) not in rects;rects.add((x,y))
    tile=atlas.crop((x,y,x+size,y+size))
    assert tile.getchannel('A').getextrema()==(0,255)
    id='wand_icon' if a['name']=='nw_wand.tex' else a['name'][9:-4]
    source=Image.open(RUNTIME/f'icon_{id}.png').convert('RGBA')
    assert source.size==(size,size) and source.tobytes()==tile.tobytes()
    hashes.setdefault(hashlib.sha256(tile.tobytes()).hexdigest(),set()).add(id)
# The retired, unavailable weak_homing card supplies the new rotation glyph.
# All currently obtainable cards must still have distinct artwork.
assert not [ids for ids in hashes.values() if len(ids)>1]
for name in ['nw_parts','nw_objects']:
    with zipfile.ZipFile(ROOT/f'mod/anim/{name}.zip') as z:
        assert z.testzip() is None
        assert z.read('build.bin')[:4]==b'BILD' and z.read('anim.bin')[:4]==b'ANIM'
        assert any(p.endswith('.tex') for p in z.namelist())
assert (ROOT/'mod/images/inventoryimages/nw_icons.tex').read_bytes()[:4]==b'KTEX'
with zipfile.ZipFile(ROOT/'mod/anim/nw_spell_world.zip') as z:
    assert z.testzip() is None
    for name in (b'shieldofterror_standing',b'lighter_standing',b'dir_31'):
        assert name in z.read('anim.bin'), ('missing compiled weapon clip',name)
# Check the actual compiled vertices. Frame w/h alone only move the pivot.
with zipfile.ZipFile(ROOT/'mod/anim/nw_objects.zip') as z:
    stream=io.BytesIO(z.read('build.bin'))
def unpack(fmt):
    return struct.unpack('<'+fmt,stream.read(struct.calcsize('<'+fmt)))
def string():
    return stream.read(unpack('I')[0]).decode('ascii')
assert stream.read(4)==b'BILD'
version,symbol_count,_=unpack('III')
assert version==6
string()
for _ in range(unpack('I')[0]): string()
ranges={}
for _ in range(symbol_count):
    key,n=unpack('II')
    for _ in range(n):
        *_,start,count=unpack('IIffffII')
        ranges[key]=(start,count)
verts=[unpack('ffffff')[:2] for _ in range(unpack('I')[0])]
names={}
for _ in range(unpack('I')[0]):
    key,=unpack('I')
    names[string()]=key
start,count=ranges[names['workbench']]
xs,ys=zip(*verts[start:start+count])
assert (min(xs),max(xs),min(ys),max(ys))==(-128,128,-216,40),'workbench footprint origin'
for name,w,h in [('blast_extent',256,256),('blast_burst',256,256)]:
    start,count=ranges[names[name]]
    xs,ys=zip(*verts[start:start+count])
    assert min(xs)>=-w/2 and max(xs)<=w/2 and min(ys)>=-h/2 and max(ys)<=h/2,name
    if name=='blast_extent':
        assert (min(xs),max(xs),min(ys),max(ys))==(-128,128,-128,128)
rimanims=ET.parse(RUNTIME/'nw_objects/animation.xml').find("anim[@name='blast']")
assert all(f.find("element[@name='blast_extent']").attrib['m_a']=='1' for f in rimanims)
# All loose materials must share the ground origin and their actual hit rectangle.
with zipfile.ZipFile(ROOT/'mod/anim/nw_supplies.zip') as supplies:
    stream=io.BytesIO(supplies.read('build.bin'))
    assert stream.read(4)==b'BILD'
    _,num_symbols,_=unpack('III')
    string()
    for _ in range(unpack('I')[0]): string()
    material_ranges={}
    for _ in range(num_symbols):
        key,n=unpack('II')
        for _ in range(n):
            *_,start,count=unpack('IIffffII')
            material_ranges[key]=(start,count)
    vertices=[unpack('ffffff')[:2] for _ in range(unpack('I')[0])]
    keys={}
    for _ in range(unpack('I')[0]):
        key,=unpack('I');keys[string()]=key
    stream=io.BytesIO(supplies.read('anim.bin'))
    assert stream.read(4)==b'ANIM'
    clips=unpack('IIIII')[-1]
    expected={'nw_dust','nw_beast_core','nw_overlord_core','nw_blank'}
    tested=set()
    for _ in range(clips):
        clip=string()
        frames=unpack('BIfI')[-1]
        for _ in range(frames):
            cx,cy,w,h=unpack('ffff')
            stream.read(4*unpack('I')[0])
            for _ in range(unpack('I')[0]):
                sym,_,_,a,b,c,d,tx,ty,_=unpack('IIIfffffff')
                if clip in expected:
                    assert sym==keys[clip]
                    start,count=material_ranges[sym]
                    xy=[(a*x+c*y+tx,b*x+d*y+ty) for x,y in vertices[start:start+count]]
                    assert all(abs(x-cx)<=w/2+.01 and abs(y-cy)<=h/2+.01 for x,y in xy),clip
                    assert abs(cx)<.01 and abs(cy+h/2)<=5 and w==h==128,clip+' ground/click bounds'
                    assert abs(tx)<.01 and abs(ty)<.01,clip+' unexpected animation translation'
                    tested.add(clip)
    assert tested==expected
    print("PASS: all four material meshes fit their 128px click bounds around bottom-centred pivots")
# Read compiled part geometry as the engine does, including the actual sprite
# dimensions rather than just the XML Frame w/h metadata.
with zipfile.ZipFile(ROOT/'mod/anim/nw_parts.zip') as z:
    stream=io.BytesIO(z.read('build.bin'))
assert stream.read(4)==b'BILD'
version,symbol_count,_=unpack('III')
string()
for _ in range(unpack('I')[0]): string()
ranges={}
for _ in range(symbol_count):
    key,n=unpack('II')
    for _ in range(n):
        *_,start,count=unpack('IIffffII')
        ranges[key]=(start,count)
verts=[unpack('ffffff')[:2] for _ in range(unpack('I')[0])]
names={}
for _ in range(unpack('I')[0]):
    key,=unpack('I');names[string()]=key
def interval(name,offset):
    start,count=ranges[names[name]]
    ys=[v[1]*.5+offset for v in verts[start:start+count]]
    return min(ys),max(ys)
colors=['red','blue','green']
shapes=[f'head_{kind}_{tips}' for kind in ('crystal','plain') for tips in (1,2,3)]
heads=[f'{shape}_{color}' for shape in shapes for color in colors]
tails=[f'tail_{shape}_{color}' for shape in ('drop','diamond','round') for color in colors]
# Verify the actual animation matrices shipped to the engine (not only XML).
with zipfile.ZipFile(ROOT/'mod/anim/nw_parts.zip') as z:
    stream=io.BytesIO(z.read('anim.bin'))
assert stream.read(4)==b'ANIM'
version,_,_,_,clip_count=unpack('IIIII')
clips={}
for _ in range(clip_count):
    clip=string()
    facing,root,fps,frames=unpack('BIfI')
    assert frames==1
    _,_,_,height=unpack('ffff')
    events,=unpack('I');stream.read(events*4)
    elements={}
    for _ in range(unpack('I')[0]):
        symbol,_,_,a,b,c,d,x,y,_=unpack('IIIfffffff')
        elements[symbol]=(a,d,x,y,b,c)
    clips[clip]=(height,elements)
for length,layout in manifest['layouts'].items():
    height,planted=clips['ground_'+length]
    scale={'short':1.88,'medium':1.72,'long':1.60}[length]
    co=math.cos(math.radians(20))*scale
    si=math.sin(math.radians(20))*scale
    assert set(planted)=={names[k] for k in (*layout,'contact_shadow','contact_grass')}
    tx,ty=layout['tail']
    for slot,(x,y) in layout.items():
        expected=(co/2,co/2,co*(x-tx)-si*(y-ty-8),si*(x-tx)+co*(y-ty-8),si/2,-si/2)
        assert all(abs(a-b)<.001 for a,b in zip(planted[names[slot]],expected)),(slot,length)
    assert planted[names['contact_grass']][2]==2.5
    assert abs(planted[names['contact_grass']][3]+2.15)<.001
    preview_height,preview=clips['preview_'+length]
    assert set(preview)=={names[k] for k in layout},'preview must omit grass and shadow'
    assert preview_height<=100.001
    # Check actual compiled vertices for every interchangeable part, including
    # broken crowns: all must fit the centered 88 x 100 header cell.
    for slot in layout:
        a,d,x,y,b,c=preview[names[slot]]
        ga,gd,gx,gy,gb,gc=planted[names[slot]]
        ratio=a/ga
        assert all(abs(v-w*ratio)<.001 for v,w in ((b,gb),(c,gc),(d,gd)))
        variants=[name for name in names if name.startswith(slot+'_')
                  and (slot!='body' or name.endswith('_'+length))]
        for name in variants:
            start,count=ranges[names[name]]
            for vx,vy in verts[start:start+count]:
                px,py=a*vx+c*vy+x,b*vx+d*vy+y
                assert -44.01<=px<=44.01 and -50.01<=py<=50.01,(length,name,px,py)
    for pose in ['floating','held']:
        height,elements=clips[pose+'_'+length]
        sx=sy=1 if pose=='floating' else scale*1.2
        assert len(elements)==3
        for sym,(dx,dy) in layout.items():
            actual=elements[names[sym]]
            expected=(.5*sx,.5*sy,dx*sx,dy*sy,0,0)
            assert all(abs(a-b)<.001 for a,b in zip(actual,expected)),(pose,length,sym,actual)
        for style in range(1,10):
            body=f'body_{style:02}_{length}'
            b0,b1=interval(body,0)
            compiled_input=Image.open(RUNTIME/'nw_parts'/f'{body}.png')
            approved=Image.open(ROOT/'assets_src/art_v2/shafts'/f'{body}.png')
            assert compiled_input.size==approved.size and compiled_input.tobytes()==approved.tobytes()
            reference=Image.open(ROOT/'assets_src/art_v2/shafts'/f'body_{style:02}_long.png')
            w,h=compiled_input.size
            assert compiled_input.crop((0,0,w,20)).tobytes()==reference.crop((0,0,w,20)).tobytes()
            assert compiled_input.crop((0,h-20,w,h)).tobytes()==reference.crop((0,reference.height-20,w,reference.height)).tobytes()
            for head in heads:
                assert interval(head,layout['head'][1])[1]*sy>=b0*sy-1, (pose,head,body,'gap')
            for tail in tails:
                assert interval(tail,layout['tail'][1])[0]*sy<=b1*sy+1, (pose,tail,body,'gap')
        if pose=='held':
            top=interval(heads[0],layout['head'][1])[0]*sy
            bottom=interval(tails[0],layout['tail'][1])[1]*sy
            assert max(-top,bottom)<=height/2
            expected_height={'short':112,'medium':140,'long':172}[length]
            assert abs((bottom-top)/sy-expected_height)<1,'overall wand length changed'
            for sym in layout:
                ga,_,_,_,gb,_=planted[names[sym]]
                assert abs(1.2*math.hypot(ga,gb)-elements[names[sym]][0])<.001,(length,sym,'held/ground scale')
            print('Compiled',pose,length,'height',round(bottom-top,1))
from check_wand_icons import check as check_wand_icons
check_wand_icons()
# Each three-wand group holds colour constant; compare material across rows.
sheet=Image.new('RGBA',(840,790),(55,49,43,255));draw=ImageDraw.Draw(sheet)
for i,shape in enumerate(shapes):
    for j,color in enumerate(colors):
        length=('short','medium','long')[i%3]
        head=shape+'_'+color
        tail=tails[(i%3)*3+j]
        x,y=58+(i%3)*78+j*275,205+(i//3)*325
        for alias,id in [('head',head),('tail',tail),('body',f'body_{(i*3+j)%9+1:02}_{length}')]:
            spec=manifest['parts'][id];w,h=spec['world_size']
            dx,dy=manifest['layouts'][length][alias]
            im=Image.open(RUNTIME/'nw_parts'/f'{id}.png').resize((w,h),Image.Resampling.LANCZOS)
            sheet.alpha_composite(im,(round(x+dx-w/2),round(y+dy-h/2)))
        draw.text((x-22,y+65),str(i%3+1)+' draw',fill='white')
draw.text((16,18),'Non-shuffle / crystal tips',fill='white')
draw.text((16,343),'Shuffle / lacquered wood tips',fill='white')
draw.text((16,660),'Slow regeneration: teardrop or diamond    |    Fast regeneration: round',fill='white')
for i,tail in enumerate(tails):
    x=80+(i//3)*275+(i%3)*57
    im=Image.open(RUNTIME/'nw_parts'/f'{tail}.png')
    sheet.alpha_composite(im,(x-im.width//2,693))
    draw.text((x-20,758),tail.split('_')[1],fill='white')
sheet.convert('RGB').save(ART/'assembly_review.png')
print('PASS:',inventory_count,'inventory tiles;',8748,'composed wand icons; compiled sockets and both poses')

# Render one matched pair per shaft from the shipped matrices at the same zoom.
held_review=Image.new('RGBA',(780,382),(218,211,193,255))
labels=ImageDraw.Draw(held_review)
for i,length in enumerate(('short','medium','long')):
    for pose,ox,oy in [('held',76,251),('ground',139,322)]:
        elements=clips[pose+'_'+length][1]
        for slot,id in [('head','head_crystal_2_blue'),('tail','tail_round_blue'),('body','body_05_'+length)]:
            a,_,dx,dy,b,_=elements[names[slot]]
            size=math.hypot(a,b)
            part=Image.open(RUNTIME/'nw_parts'/f'{id}.png')
            part=part.resize((round(part.width*size),round(part.height*size)),Image.Resampling.LANCZOS)
            part=part.rotate(-math.degrees(math.atan2(b,a)),Image.Resampling.BICUBIC,expand=True)
            held_review.alpha_composite(part,(round(i*260+ox+dx-part.width/2),round(oy+dy-part.height/2)))
        labels.text((i*260+ox-10,360),pose,fill='#322a25')
    labels.text((i*260+106,8),length.upper(),fill='#322a25')
held_review.convert('RGB').save(ART/'held_size_review.png')

# Verify the actual compressed face pixels, animation bindings and all pile sizes.
from check_ground_cards import check_ground_cards
check_ground_cards()
