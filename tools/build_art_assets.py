"""Compile generated art at game resolution, preserving all original images."""
import argparse
import colorsys
import json
import math
import subprocess
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET
from PIL import Image, ImageOps, ImageDraw, ImageChops, ImageFilter
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'assets_src/art_v1'
ORIGINALS=SOURCE/'originals'
RUNTIME=SOURCE/'runtime'
WAND_ART=ROOT/'assets_src/art_v2'
BODY_HEIGHTS={'short':48,'medium':104,'long':168}
HEAD_HEIGHT=144
TAIL_HEIGHT=48

def resize(id,size,stretch=False,prefer_icon=False):
    redraw=SOURCE/'icon_redraws'/f'{id}.png'
    path=redraw if (prefer_icon or size==(64,64)) and redraw.exists() else ORIGINALS/f'{id}.png'
    im=Image.open(path).convert('RGBA')
    assert im.getchannel('A').getextrema()[0]==0, f'{id}: expected real transparency'
    # Generated cutouts can contain almost invisible alpha dust far outside the
    # silhouette. It must not determine the crop and shrink a shaft to one pixel.
    im.putalpha(im.getchannel('A').point(lambda a: 0 if a<=8 else a))
    bbox=im.getchannel('A').getbbox();assert bbox,id
    im=im.crop(bbox)
    if stretch: return im.resize(size,Image.Resampling.LANCZOS)
    im=ImageOps.contain(im,(size[0]-8,size[1]-8),Image.Resampling.LANCZOS)
    out=Image.new('RGBA',size)
    out.alpha_composite(im,((size[0]-im.width)//2,(size[1]-im.height)//2))
    return out

def frame(parent,name,image,size,pivot=(0,0)):
    symbol=ET.SubElement(parent,'Symbol',name=name)
    ET.SubElement(symbol,'Frame',framenum='0',duration='1',image=image,x=str(pivot[0]),y=str(pivot[1]),w=str(size[0]),h=str(size[1]))

def anim(parent,name,bank,elements):
    a=ET.SubElement(parent,'anim',name=name,root=bank,framerate='30')
    f=ET.SubElement(a,'frame',x='0',y='0',w='256',h='256')
    for z,(symbol,x,y) in enumerate(elements):
        ET.SubElement(f,'element',name=symbol,frame='0',layername=symbol,z_index=str(z),m_a='1',m_b='0',m_c='0',m_d='1',m_tx=str(x),m_ty=str(y))

def compile_bank(name,build,anims,images,tools):
    folder=RUNTIME/name;folder.mkdir(parents=True,exist_ok=True)
    for id,im in images.items(): im.save(folder/f'{id}.png')
    ET.ElementTree(build).write(folder/'build.xml',encoding='utf-8',xml_declaration=True)
    ET.ElementTree(anims).write(folder/'animation.xml',encoding='utf-8',xml_declaration=True)
    intermediate=ROOT/'dist/intermediate'/f'{name}.zip';intermediate.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(intermediate,'w',zipfile.ZIP_DEFLATED) as z:
        for id in images: z.write(folder/f'{id}.png',f'{id}.png')
        for file in ['build.xml','animation.xml']: z.write(folder/file,file)
    result=subprocess.run([str(tools/'buildtools/windows/Python27/python.exe'),str(tools/'tools/scripts/buildanimation.py'),str(intermediate),'--outputdir',str(ROOT/'mod'),'--scale','1','--force'],cwd=tools,capture_output=True,timeout=90)
    (ROOT/f'test_reports/{name}_build.log').write_bytes(result.stdout+result.stderr)
    assert result.returncode==0,f'{name}: check build log'
    with zipfile.ZipFile(ROOT/f'mod/anim/{name}.zip') as z:
        assert z.read('anim.bin')[:4]==b'ANIM' and z.read('build.bin')[:4]==b'BILD'

def icon(id,size=64):
    base, _, event = id.rpartition('_')
    if base in ('spark','arrow','heavy','scatter','fire','frost') and event in ('hit','timer'):
        out=Image.new('RGBA',(size,size))
        base_size=round(55*size/64)
        half=size//2
        out.alpha_composite(resize(base,(base_size,base_size),prefer_icon=True),(0,0))
        out.alpha_composite(resize('imprint_'+event,(half,half)),(size-half,size-half))
        return out
    return resize(id,(size,size),prefer_icon=True)

def motion(anims,name,symbol,poses):
    a=ET.SubElement(anims,'anim',name=name,root='nw_objects',framerate='30')
    for x,y,angle,sx,sy in poses:
        c,s=math.cos(angle),math.sin(angle)
        bound='960' if name=='blast' else '512'
        f=ET.SubElement(a,'frame',x='0',y='0',w=bound,h=bound)
        ET.SubElement(f,'element',name=symbol,frame='0',layername=symbol,z_index='0',
                      m_a=str(c*sx),m_b=str(s*sx),m_c=str(-s*sy),m_d=str(c*sy),m_tx=str(x),m_ty=str(y))

def card_face(art,size=64):
    # Keep the larger painted master for ground cards and downsample for inventory.
    plate=Image.new('RGBA',(192,192))
    d=ImageDraw.Draw(plate)
    for box,r,color in [((20,2,172,190),13,'#241d21'),((25,7,167,185),10,'#bd9861'),
                        ((29,11,163,181),8,'#583c38'),((34,16,158,176),6,'#382d37')]:
        d.rounded_rectangle(box,r,fill=color)
    for x,y in [(37,19),(155,19),(37,173),(155,173)]:
        d.polygon([(x,y-5),(x+4,y),(x,y+5),(x-4,y)],fill='#ead29a')
    plate=plate.resize((size,size),Image.Resampling.LANCZOS)
    glyph=art.crop(art.getchannel('A').getbbox())
    glyph=ImageOps.contain(glyph,(40*size//64,46*size//64),Image.Resampling.LANCZOS)
    plate.alpha_composite(glyph,((size-glyph.width)//2,(size-glyph.height)//2))
    return plate

CARD_CANVAS=(230,172)
CARD_DEPTHS={'card':4,'pile_small':10,'pile_medium':17,'pile_large':27}

def ground_face(icon):
    # Draw the face as a foreshortened quadrilateral for the fixed camera.
    face=icon.crop(icon.getchannel('A').getbbox()).resize((182,106),Image.Resampling.LANCZOS)
    out=Image.new('RGBA',CARD_CANVAS)
    for y in range(face.height):
        width=round(124+58*y/(face.height-1))
        line=face.crop((0,y,face.width,y+1)).resize((width,1),Image.Resampling.LANCZOS)
        out.alpha_composite(line,((out.width-width)//2,32+y))
    return out

def paper_edges(shape,depth):
    shadow=Image.new('RGBA',CARD_CANVAS)
    shadow.paste((31,23,32,135),(7,5,7+shape.width,5+shape.height),shape)
    out=shadow.filter(ImageFilter.GaussianBlur(3))
    # Bottom edge stays on the ground. The top of the stack rises with depth.
    colors=['#312933','#dbc7a5','#ad967c','#f6e5c9']
    for layer in range(depth):
        colour=colors[0] if layer==0 else colors[1+(layer%3)]
        out.paste(colour,(0,-layer,CARD_CANVAS[0],CARD_CANVAS[1]-layer),shape)
    top=Image.new('L',CARD_CANVAS)
    top.paste(shape,(0,-depth))
    out.putalpha(ImageChops.subtract(out.getchannel('A'),top))
    return out

def build_ground_cards(cards,tools):
    # Two single-page builds preserve the full-size source faces. Each clip names
    # its actual face, so there is no symbol override or sampler change at runtime.
    faces={id:ground_face(card_face(icon(id,192),192)) for id in cards.order.values()}
    edges={pose:paper_edges(faces['spark'].getchannel('A'),depth) for pose,depth in CARD_DEPTHS.items()}
    for page in range((max(cards.codes.values())-1)//128+1):
        bank=f'nw_ground_cards_{page}'
        build=ET.Element('Build',name=bank);clips=ET.Element('Anims');images={}
        def add(name,im):
            box=im.getbbox()
            images[name]=im.crop(box)
            pivot=((box[0]+box[2]-im.width)/2,(box[1]+box[3]-im.height)/2)
            frame(build,name,name,images[name].size,pivot)
        for pose,edge in edges.items(): add('edge_'+pose,edge)
        for id,face in faces.items():
            code=cards.codes[id]
            if (code-1)//128!=page: continue
            symbol='face_'+id
            add(symbol,face)
            for pose,depth in CARD_DEPTHS.items():
                anim(clips,f'{pose}_{code}',bank,[(symbol,0,-depth),('edge_'+pose,0,0)])
        compile_bank(bank,build,clips,images,tools)
        with zipfile.ZipFile(ROOT/f'mod/anim/{bank}.zip') as z:
            assert len([n for n in z.namelist() if n.endswith('.tex')])==1,bank

def socket_x(im,top):
    alpha=im.getchannel('A')
    lo,hi=alpha.point(lambda a:255 if a>50 else 0).getbbox()[1::2]
    band=alpha.crop((0,lo if top else hi-5,im.width,lo+5 if top else hi))
    weights=[sum(band.crop((x,0,x+1,band.height)).getdata()) for x in range(im.width)]
    return sum((x+.5)*w for x,w in enumerate(weights))/sum(weights)

# Bake all three palettes from one painting so joins and inked outlines stay
# identical. Only the gem or lacquer hue is mapped; the brass collar stays warm.
PALETTE={'red':.985,'blue':.60,'green':.38}

def paint(tile,source,target):
    out=tile.copy()
    pixels=[]
    for r,g,b,a in tile.getdata():
        h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
        distance=abs((h-source+.5)%1-.5)
        mask=min(1,max(0,(.095-distance)/.045))*min(1,max(0,(s-.10)/.19))
        if a and mask:
            nr,ng,nb=colorsys.hsv_to_rgb((target+(h-source+.5)%1-.5)%1,s,v)
            r,g,b=[round(old+(new*255-old)*mask) for old,new in zip((r,g,b),(nr,ng,nb))]
        pixels.append((r,g,b,a))
    out.putdata(pixels)
    return out

def add_ornament(images,sheet,box,name,base_hue):
    tile=sheet.crop(box)
    alpha=tile.getchannel('A').point(lambda a:0 if a<24 else a)
    tile.putalpha(alpha);tile=tile.crop(alpha.getbbox())
    is_head=name.startswith('head_')
    size=(176,HEAD_HEIGHT) if is_head else (80,TAIL_HEIGHT)
    a=tile.getchannel('A')
    rim_y=round(tile.height*(.94 if is_head else .06))
    rim=a.crop((0,rim_y,tile.width,rim_y+1)).point(lambda v:255 if v>50 else 0).getbbox()
    socket_scale=26/(rim[2]-rim[0])
    if is_head:
        crown_scale=({1:104,2:128,3:144}[int(name[-1])])/tile.width
        center=(rim[0]+rim[2])/2
        mesh=[]
        for y in range(0,HEAD_HEIGHT,4):
            edges=[]
            for p in (y/HEAD_HEIGHT,(y+4)/HEAD_HEIGHT):
                t=max(0,min(1,(p-.72)/.20))
                scale=crown_scale+(socket_scale-crown_scale)*t
                edges.append((center-size[0]/(2*scale),p*tile.height,center+size[0]/(2*scale)))
            a,b=edges
            mesh.append(((0,y,size[0],y+4),(a[0],a[1],b[0],b[1],b[2],b[1],a[2],a[1])))
        tile=tile.transform(size,Image.Transform.MESH,mesh,Image.Resampling.BICUBIC)
    else:
        width=min(size[0]-8,round(tile.width*socket_scale))
        tile=tile.resize((width,size[1]),Image.Resampling.LANCZOS)
    for color,hue in PALETTE.items():
        im=Image.new('RGBA',size)
        im.alpha_composite(paint(tile,base_hue,hue),((size[0]-tile.width)//2,size[1]-tile.height if is_head else 0))
        images[name+'_'+color]=im

def planted_clip(animations,length,layout,scale):
    # Place the tail slightly inside the ground at the entity's pickup point.
    angle=math.radians(20)
    c,s=scale*math.cos(angle),scale*math.sin(angle)
    tx,ty=layout['tail']
    tip_y=ty+TAIL_HEIGHT/4-4
    parts=[]
    for slot in ('body','tail','head'):
        x,y=layout[slot]
        parts.append((slot,c*(x-tx)-s*(y-tip_y),s*(x-tx)+c*(y-tip_y)))
    # Klei's lower z_index is nearer the camera: grass occludes the tip.
    anim(animations,'ground_'+length,'nw_parts',
         [('contact_grass',2.5,-2.15),*parts,('contact_shadow',1,1)])
    f=animations[-1].find('frame')
    half_body=(layout['tail'][1]-TAIL_HEIGHT/4+4)
    sizes={'head':(196,HEAD_HEIGHT),'body':(72,half_body*4),'tail':(100,TAIL_HEIGHT)}
    bounds=[(-38,-24,38,24)]
    for slot,x,y in parts:
        w,h=sizes[slot]
        rx,ry=(abs(c)*w+abs(s)*h)/4,(abs(s)*w+abs(c)*h)/4
        bounds.append((x-rx,y-ry,x+rx,y+ry))
    left,top=min(b[0] for b in bounds),min(b[1] for b in bounds)
    right,bottom=max(b[2] for b in bounds),max(b[3] for b in bounds)
    f.attrib.update(x=str((left+right)/2),y=str((top+bottom)/2),
                    w=str(math.ceil(right-left)+16),h=str(math.ceil(bottom-top)+16))
    for el in f.findall('element'):
        if el.get('name') in layout:
            el.attrib.update(m_a=str(c/2),m_b=str(s/2),m_c=str(-s/2),m_d=str(c/2))

def wand_parts(vm,manifest,tools):
    v=vm.eval('require("nw/visual")')
    sheet=Image.open(WAND_ART/'heads.png').convert('RGBA')
    tails=Image.open(WAND_ART/'tails.png').convert('RGBA')
    images={'anchor':Image.new('RGBA',(4,4))}
    # A tight, translucent contact shadow, below the native grass and the tail.
    shade=Image.new('L',(76,24))
    ImageDraw.Draw(shade).ellipse((5,6,70,18),fill=115)
    shadow=Image.new('RGBA',shade.size,(30,22,27))
    shadow.putalpha(shade.filter(ImageFilter.GaussianBlur(2.5)))
    images['contact_shadow']=shadow
    specs={}
    for i,tail in enumerate(('drop','round','diamond')):
        x1,x2=i*sheet.width//3,(i+1)*sheet.width//3
        add_ornament(images,sheet,(x1,0,x2,sheet.height//2-12),'head_crystal_'+str(i+1),.985)
        add_ornament(images,sheet,(x1,sheet.height//2,x2,sheet.height),'head_plain_'+str(i+1),.985)
        add_ornament(images,tails,(i*tails.width//3,0,(i+1)*tails.width//3,tails.height),'tail_'+tail,.985)
    for style in range(1,v.styles+1):
        for length,height in BODY_HEIGHTS.items():
            name=f'body_{style:02}_{length}'
            im=Image.open(WAND_ART/'shafts'/f'{name}.png').convert('RGBA')
            assert im.size==(72,height),name
            images[name]=im
    # Align the actual inked socket, even when the drawing is asymmetric.
    for name,im in list(images.items()):
        if name.startswith(('head_','tail_')):
            out=Image.new('RGBA',(im.width+20,im.height))
            out.alpha_composite(im,(round(out.width/2-socket_x(im,name.startswith('tail_'))),0))
            images[name]=out
    build=ET.Element('Build',name='nw_parts');animations=ET.Element('Anims')
    for name,im in images.items():
        frame(build,name,name,im.size)
        specs[name]={'pixels':im.size,'world_size':tuple(n//2 for n in im.size),'center':(0,0)}
    manifest['parts']=specs
    frame(build,'contact_grass','anchor',images['anchor'].size)
    for alias,id in [('head','head_crystal_1_red'),('body','body_01_short'),('tail','tail_drop_red')]:
        frame(build,alias,id,images[id].size)
    for length in ['short','medium','long']:
        half=images['body_01_'+length].height/4
        # All PNGs are centered on their actual vertices. Join the two collars
        # four world pixels inside the ends of the shaft at every length.
        layout={'head':(0,-half-HEAD_HEIGHT/4+4),'body':(0,0),'tail':(0,half+TAIL_HEIGHT/4-4)}
        manifest['layouts'][length]=layout
        scale=v.scale[length]
        planted_clip(animations,length,layout,scale)
        for pose in ['floating','held']:
            factor=scale*v.held_multiplier if pose=='held' else 1
            anim(animations,pose+'_'+length,'nw_parts',
                 [(k,layout[k][0]*factor,layout[k][1]*factor) for k in ('body','tail','head')])
            f=animations[-1].find('frame')
            f.set('h',str(math.ceil(2*(half+HEAD_HEIGHT/2)*factor)))
            f.set('w',str(math.ceil(max(256,196*factor))))
            for el in f.findall('element'):
                el.set('m_a',str(.5*factor));el.set('m_d',str(.5*factor))
    compile_bank('nw_parts',build,animations,images,tools)
    for start in range(0,v.count,v.per_style):
        wand_icon_page(v,start,images,specs,manifest['layouts'],tools)

def wand_icon_page(v,start,images,specs,layouts,tools):
    page=Path(v.atlas(start)).stem
    atlas=Image.new('RGBA',(2048,1024))
    xml=ET.Element('Atlas');ET.SubElement(xml,'Texture',filename=page+'.tex');els=ET.SubElement(xml,'Elements')
    for i in range(v.per_style):
        code=start+i
        head,length,tail,body=v.parts(code)
        im=Image.new('RGBA',(192,256))
        for slot,part in [('head',head),('tail',tail),('body',body)]:
            sprite=images[part].resize(specs[part]['world_size'],Image.Resampling.LANCZOS)
            dx,dy=layouts[length][slot]
            im.alpha_composite(sprite,(round(96+dx-sprite.width/2),round(128+dy-sprite.height/2)))
        # Thicken perpendicular to the shaft, before rotating into the slot.
        im=im.crop(im.getchannel('A').getbbox())
        im=im.resize((round(im.width*1.32),im.height),Image.Resampling.LANCZOS)
        im=im.rotate(-36,Image.Resampling.BICUBIC,expand=True)
        im=im.crop(im.getchannel('A').getbbox())
        extent={'short':56,'medium':60,'long':63}[length]
        im=ImageOps.contain(im,(extent,extent),Image.Resampling.LANCZOS)
        x=(i%32)*64;y=(i//32)*64
        atlas.alpha_composite(im,(x+(64-im.width)//2,y+(64-im.height)//2))
        ET.SubElement(els,'Element',name=v.icon(code)+'.tex',u1=str(x/atlas.width),u2=str((x+64)/atlas.width),
                      v1=str(1-(y+64)/atlas.height),v2=str(1-y/atlas.height))
    dest=ROOT/'mod/images/inventoryimages'
    atlas.save(RUNTIME/(page+'.png'))
    ET.ElementTree(xml).write(dest/(page+'.xml'),encoding='utf-8',xml_declaration=True)
    subprocess.run([str(tools/'tools/bin/TextureConverter.exe'),'--swizzle','--format','bc3','--platform','opengl',
        '--premultiply','-i',str(RUNTIME/(page+'.png')),'-o',str(dest/(page+'.tex'))],check=True,capture_output=True)

GARDEN_NAMES=('spore_sentry','vital_ring','heavy_shot','trident_cast','chord_d','repeat_4',
              'bud','sprout','idle','aim','fire','wilt')

def garden_tiles():
    sheet=Image.open(SOURCE/'garden_sheet.png').convert('RGBA')
    w,h=sheet.width//4,sheet.height//3
    tiles={}
    for i,name in enumerate(GARDEN_NAMES):
        x,y=(i%4)*w,(i//4)*h
        tile=sheet.crop((x,y,x+w,y+h))
        tile.putalpha(tile.getchannel('A').point(lambda a: 0 if a<=12 else a))
        tiles[name]=tile
        if i<6: tile.save(ORIGINALS/f'{name}.png')
    return tiles

def garden_animations(build,anims,images,tiles):
    # Common ground pivot and scale keep the roots planted through all poses.
    for name in GARDEN_NAMES[6:]:
        tile=tiles[name]
        box=tile.getchannel('A').getbbox()
        art=tile.crop(box)
        art.thumbnail((round(art.width*.50),round(art.height*.50)),Image.Resampling.LANCZOS)
        key='plant_'+name
        images[key]=art
        frame(build,key,key,art.size,(0,-art.height/2))
    for name,poses in {
        'spore_grow': [('bud',5),('sprout',7),('idle',6)],
        'spore_idle': [('idle',15),('aim',5),('idle',10)],
        'spore_fire': [('aim',6),('fire',4),('idle',4)],
        'spore_wilt': [('wilt',9)]}.items():
        anim(anims,name,'nw_objects',[('plant_'+poses[0][0],0,0)])
        clip=anims[-1]
        clip.remove(clip[0])
        for pose,duration in poses:
            for i in range(duration):
                f=ET.SubElement(clip,'frame',x='0',y='-80',w='260',h='220')
                ET.SubElement(f,'element',name='plant_'+pose,frame='0',layername='plant',z_index='0',
                              m_a='1',m_d='1',m_c='0',m_b='0',m_tx='0',m_ty='0')
    # The physical spine is taken from the firing pose, in its actual flight orientation.
    thorn=tiles['fire'].crop((306,128,361,151))
    thorn=thorn.crop(thorn.getchannel('A').getbbox())
    images['garden_thorn']=thorn
    frame(build,'garden_thorn','garden_thorn',thorn.size)
    anim(anims,'spore_thorn','nw_objects',[('garden_thorn',0,0)])
    ring=tiles['vital_ring']
    ring=ring.crop(ring.getchannel('A').getbbox())
    ring=ring.resize((300,300),Image.Resampling.LANCZOS)
    strength=Image.new('L',ring.size,135)
    ImageDraw.Draw(strength).ellipse((50,50,250,250),fill=32)
    ring.putalpha(ImageChops.multiply(ring.getchannel('A'),strength.filter(ImageFilter.GaussianBlur(8))))
    images['garden_ring']=ring
    frame(build,'garden_ring','garden_ring',ring.size)
    motion(anims,'vital_pulse','garden_ring',[(0,0,0,1.96+.04*math.cos(i*math.tau/30),
        1.96+.04*math.cos(i*math.tau/30)) for i in range(30)])
    for f in anims[-1]: f.set('w','650');f.set('h','650')
    # Isolate the turquoise note from the harp illustration, for the world effect.
    note=tiles['chord_d'].crop((227,48,350,190))
    images['garden_note']=note
    frame(build,'garden_note','garden_note',note.size)
    motion(anims,'chord_note','garden_note',[(0,-42-i*2,math.sin(i*.2)*.14,
        .7-i*.018,.7-i*.018) for i in range(20)])

def arsenal_art(arsenal):
    from PIL import ImageFont
    sheet=Image.open(SOURCE/'target_sheet.png').convert('RGBA')
    for filename,names in [('target_creatures.png',('hostile','friendly')),
                           ('target_world.png',('neutral','building','nature'))]:
        portraits=Image.open(SOURCE/filename).convert('RGBA')
        for i,name in enumerate(names):
            portraits.crop((round(i*portraits.width/len(names)),0,
                            round((i+1)*portraits.width/len(names)),portraits.height)).save(ORIGINALS/f'target_{name}.png')
    # Keep the painted cell coordinates independent of the live card roster.
    for name,i in {'players_other':6,'self':7}.items():
        x,y=i%4,i//4
        sheet.crop((round(x*sheet.width/4),round(y*sheet.height/2),
                    round((x+1)*sheet.width/4),round((y+1)*sheet.height/2))).save(ORIGINALS/f'target_{name}.png')
    for c in arsenal.cards.values():
        note=arsenal.notes[c.id]
        if not note: continue
        src='note_a' if note.instrument=='ocarina' else 'chord_d'
        im=resize(src,(160,160))
        font=ImageFont.truetype('C:/Windows/Fonts/georgiab.ttf',62)
        ImageDraw.Draw(im).text((155,157),note.label,font=font,anchor='rs',fill='#fff1b9',stroke_width=5,stroke_fill='#332325')
        im.save(ORIGINALS/f'{c.id}.png')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--tools',type=Path,default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools"));args=parser.parse_args()
    RUNTIME.mkdir(parents=True,exist_ok=True)
    vm=LuaRuntime(unpack_returned_tuples=True);vm.globals().package.path=str(ROOT/'mod/scripts/?.lua').replace('\\','/')+';'+vm.globals().package.path
    ids=list(vm.eval('require("nw/cards").order').values())
    manifest={'version':1,'purpose':'generated hand-inked art, compiled at game sizes','inventory_pixels':[64,64],'parts':{},'layouts':{}}
    wand_parts(vm,manifest,args.tools)
    tiles=garden_tiles()
    expansion=list(vm.eval('require("nw/expansion")').values())
    for i,card in enumerate(expansion):
        if i%16==0: sheet=Image.open(SOURCE/f'expansion_{i//16}.png').convert('RGBA')
        x,y=i%4,i%16//4
        tile=sheet.crop((round(x*sheet.width/4),round(y*sheet.height/4),
                         round((x+1)*sheet.width/4),round((y+1)*sheet.height/4)))
        tile.save(ORIGINALS/f'{card.id}.png')
    arsenal=vm.eval('require("nw/arsenal")');arsenal_art(arsenal)
    portrait=Image.open(ROOT/'assets_src/spell_revision/target_friendly.png').convert('RGBA')
    # Reuse the neutral target's actual inked ring and all four sight marks.
    reticle=Image.open(ORIGINALS/'target_neutral.png').convert('RGBA')
    w,h=reticle.size
    blank=ImageDraw.Draw(reticle)
    blank.ellipse((w*.155,h*.155,w*.845,h*.845),fill=(0,0,0,0))
    portrait=ImageOps.contain(portrait,(round(w*.55),round(h*.55)),Image.Resampling.LANCZOS)
    reticle.alpha_composite(portrait,((w-portrait.width)//2,(h-portrait.height)//2))
    reticle.save(ORIGINALS/'target_friendly.png')
    glyphs={id:icon(id) for id in ids}
    iconimages={id:card_face(glyphs[id]) for id in ids}
    iconimages['wand_icon']=resize('wand_icon',(64,64))
    atlas=Image.new('RGBA',(1024,1024));xml=ET.Element('Atlas');ET.SubElement(xml,'Texture',filename='nw_icons.tex');elements=ET.SubElement(xml,'Elements')
    for i,(id,im) in enumerate(iconimages.items()):
        x,y=(i%16)*64,(i//16)*64;atlas.alpha_composite(im,(x,y));im.save(RUNTIME/f'icon_{id}.png')
        name='nw_wand.tex' if id=='wand_icon' else f'nw_spell_{id}.tex'
        ET.SubElement(elements,'Element',name=name,u1=str(x/atlas.width),u2=str((x+64)/atlas.width),v1=str(1-(y+64)/atlas.height),v2=str(1-y/atlas.height))
    atlas.save(RUNTIME/'nw_icons.png')
    dest=ROOT/'mod/images/inventoryimages';dest.mkdir(parents=True,exist_ok=True)
    ET.ElementTree(xml).write(dest/'nw_icons.xml',encoding='utf-8',xml_declaration=True)
    subprocess.run([str(args.tools/'tools/bin/TextureConverter.exe'),'--swizzle','--format','bc3','--platform','opengl','--premultiply','-i',str(RUNTIME/'nw_icons.png'),'-o',str(dest/'nw_icons.tex')],check=True,capture_output=True,timeout=30)
    build=ET.Element('Build',name='nw_objects');anims=ET.Element('Anims');images={}
    build_ground_cards(vm.eval('require("nw/cards")'),args.tools)
    for id in ids:
        name='nw_spell_'+id;images[name]=glyphs[id];frame(build,name,name,(32,32))
    images['nw_pellet']=resize('pellet',(96,40));frame(build,'nw_pellet','nw_pellet',(38,16))
    # Native fence_electric_field uses 150 animation pixels per world unit.
    fx_layout=vm.eval('require("nw/fx_layout")')
    diameter=int(fx_layout.blast_pixels)
    blast_size=(diameter,diameter)
    circle=(0,0,diameter-1,diameter-1)
    burst=resize('blast_fx',blast_size)
    disk=Image.new('L',blast_size);ImageDraw.Draw(disk).ellipse(circle,fill=255)
    burst.putalpha(ImageChops.multiply(burst.getchannel('A'),disk))
    images['blast_burst']=burst
    rim=Image.new('RGBA',blast_size)
    for start in range(0,360,45):
        ImageDraw.Draw(rim).arc(circle,start,start+42,fill=(255,206,127,220),width=2)
    images['blast_extent']=rim
    for name in ('blast_burst','blast_extent'):
        frame(build,name,name,blast_size)
    frame(build,'weapon_slot','nw_spell_thrust',(52,52))
    motion(anims,'blast','blast_burst',[(0,0,0,v,v) for v in (.12,.29,.57,.82,1,.98,.87,.64,.30)])
    # Keep the hit boundary stationary while the center of the blast animates.
    for f in anims.find("anim[@name='blast']").findall('frame'):
        ET.SubElement(f,'element',name='blast_extent',frame='0',layername='blast_extent',z_index='1',
                      m_a='1',m_b='0',m_c='0',m_d='1',m_tx='0',m_ty='0')
    motion(anims,'heal','nw_spell_heal_ally',[(0,-i,0,v,v) for i,v in enumerate((.4,.85,1.3,1.5,1.4,1.2,1,.7,.4))])
    motion(anims,'thrust','weapon_slot',[(x,0,math.pi/2,.65,.65) for x in (0,18,43,63,58,46,28,5)])
    motion(anims,'slash','weapon_slot',[(0,0,math.radians(v),.85,.85) for v in (40,65,98,124,140,142,143,145,146)])
    motion(anims,'whirl','weapon_slot',[(0,0,i*2*math.pi/12,.75,.75) for i in range(13)])
    frame(build,'sprite','nw_spell_spark',(32,32))
    anim(anims,'projectile','nw_objects',[('sprite',0,0)])
    # Rotate the source's side view to +X; the entity supplies the world heading.
    for id,deg in {'spark':-135,'arrow':45,'scatter':0,'heavy':0,'fire':-135,'frost':45}.items():
        motion(anims,'flight_'+id,'sprite',[(0,0,math.radians(deg),1,1)])
    for id,pixels,size in [('workbench',(256,256),(256,256)),('target_dummy',(128,192),(80,120))]:
        images[id]=resize(id,pixels)
        # On the 256px workbench painting, the four feet surround (128,216).
        pivot=(0,-88) if id=='workbench' else (0,-size[1]/2)
        frame(build,id,id,size,pivot);anim(anims,id,'nw_objects',[(id,0,0)])
        if id=='workbench':
            anims[-1].find('frame').set('y',str(pivot[1]))
        manifest[id]={'pixels':pixels,'world_size':size}
    for card in expansion+list(arsenal.cards.values()):
        if card.id=='edge_voidcloth_scythe':
            # The extracted native scythe image is cropped and centered, without the inventory frame.
            motion(anims,'flight_'+card.id,'nw_spell_'+card.id,
                   [(0,0,math.tau*i/20,4,4) for i in range(20)])
        elif card.kind=='projectile' and not card.engraving:
            poses=[]
            for i in range(12):
                phase=math.tau*i/12
                angle=phase if card.id in ('glass_disc','star_vortex') else .055*math.sin(phase)
                scale=1.25+.10*math.sin(phase)
                poses.append((0,0,angle,scale,scale))
            motion(anims,'flight_'+card.id,'sprite',poses)
        elif card.kind=='field':
            poses=[]
            count=24 if card.id=='moon_fall' else 18
            for i in range(count):
                phase=math.tau*i/count
                # Roots stay fixed on crystals; cloud and insect silhouettes hover.
                height=-20
                if card.id in ('rain_cloud','storm_cloud','bee_swarm','fireflies'):
                    height=-80-7*math.sin(phase)
                elif card.id=='moon_fall': height=-190*(1-(i/(count-1))**2)
                angle=phase if card.id=='vortex' else .06*math.sin(phase)
                sx=2.4+.12*math.sin(phase);sy=2.4+.10*math.cos(phase)
                if card.id=='bog_whip':
                    sx=1+4*math.sin(i*math.pi/(count-1))
                    height=-20
                poses.append((0,height,angle,sx,sy))
            motion(anims,'field_'+card.id,'nw_spell_'+card.id,poses)
    motion(anims,'field_boundary','blast_extent',[(0,0,0,1,1)])
    garden_animations(build,anims,images,tiles)
    compile_bank('nw_objects',build,anims,images,args.tools)
    (SOURCE/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
    sheet=Image.new('RGB',(8*128,math.ceil(len(iconimages)/8)*120),(55,49,43));draw=ImageDraw.Draw(sheet)
    for i,(id,im) in enumerate(iconimages.items()):
        x,y=(i%8)*128,(i//8)*120;sheet.paste(im,(x+32,y+8),im);draw.text((x+4,y+80),id,fill='white')
    sheet.save(SOURCE/'inventory_64_review.png')
    print('PASS:',len(ids),'spell icons + wand, modular parts, inventory and combat animations')

if __name__=='__main__': main()
