"""Shared paper layers + six lower blocks, composed by native animation symbols."""
import argparse
import json
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageFilter
from lupa.lua51 import LuaRuntime
from build_art_assets import ROOT, compile_bank, frame, anim
from build_card_pile_art import SOURCE, FRAMES, TAILS, SCALE, SIZE, project, positions, variants, font
from animation_atlas import validate_animation_archive

OUT=ROOT/'assets_src/spell_cards_composed/v4_split_piles'
BANK='nw_card_piles'
PAGE_SIZE=48
ANCHOR=(128,136)

def single_paper(shape,standalone=False):
    face=project(FRAMES[shape],0,0)
    edge=Image.new('RGBA',face.size,'#3c3229');edge.putalpha(face.getchannel('A'))
    # Standalone cards need a readable paper core at game scale. Pile layers
    # keep their original thickness and spacing, avoiding an inflated stack.
    depth=round((2.5 if standalone else 1.25)*SCALE)
    out=Image.new('RGBA',face.size);out.alpha_composite(edge,(0,depth))
    core=Image.new('RGBA',face.size,'#ad9670' if standalone else '#8e7b5e')
    core.putalpha(face.getchannel('A'))
    out.alpha_composite(core,(0,depth-2))
    tint=Image.new('RGBA',face.size,(53,42,29,0))
    tint.putalpha(face.getchannel('A').point(lambda a:round(a*.16)))
    out.alpha_composite(Image.alpha_composite(face,tint))
    return out

def place(canvas,picture,offset):
    # Fractional offsets match the runtime matrices, including 2.7 px paper steps.
    x,y=offset
    canvas.alpha_composite(picture.transform(canvas.size,Image.Transform.AFFINE,
        (1,0,-x*SCALE,0,1,-y*SCALE),Image.Resampling.BICUBIC))

def make_materials():
    layers={'paper_'+s:single_paper(s) for s in FRAMES}
    layers.update({'single_paper_'+s:single_paper(s,standalone=True) for s in FRAMES})
    for tier,tails in TAILS.items():
        for style,tail in tails.items():
            seq='RRR'+tail
            coords=positions(seq)
            out=Image.new('RGBA',(SIZE,SIZE))
            for i in range(len(seq)-1,2,-1):place(out,layers['paper_'+seq[i]],coords[i])
            layers['base_'+tier+'_'+style]=out
    for shape in FRAMES:
        mask=project(FRAMES[shape],0,0).getchannel('A')
        shadow=Image.new('RGBA',(SIZE,SIZE),(8,10,7,0))
        shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(2*SCALE)).point(lambda a:round(a*.45)))
        layers['shadow_'+shape]=shadow
    return layers

def layouts():
    rows=[]
    for tier,style,prefix,seq in variants():
        key=tier+'_'+prefix+('' if style=='exact' else '_'+style)
        coords=positions(seq)
        elements=[('face',*coords[0])]
        paper_prefix='single_paper_' if tier=='single' else 'paper_'
        elements += [(paper_prefix+s,*coords[i]) for i,s in enumerate(prefix)]
        if tier in TAILS:elements.append(('base_'+tier+'_'+style,0,0))
        # One contact shadow below the entire pile, never one dark seam per group.
        shadow=seq[-1]
        elements.append(('shadow_'+shadow,0,2))
        rows.append(dict(key=key,tier=tier,prefix=prefix,style=style,sequence=seq,elements=elements))
    return rows

def compose(row,layers,face=None):
    out=Image.new('RGBA',(SIZE,SIZE))
    for symbol,x,y in reversed(row['elements']):
        if symbol=='face':
            picture=project(face if face is not None else FRAMES[row['prefix'][0]],0,0)
        else:picture=layers[symbol]
        place(out,picture,(x,y))
    return out

def export(layers,rows):
    from PIL import ImageDraw
    for name in ['master_768','runtime_256']:(OUT/name).mkdir(parents=True,exist_ok=True)
    for name,im in layers.items():
        assert im.getbbox() and im.getchannel('A').getextrema()[0]==0
        im.save(OUT/'master_768'/f'{name}.png')
        im.resize((256,256),Image.Resampling.LANCZOS).save(OUT/'runtime_256'/f'{name}.png')
    keys=['two_RH','three_RHR','medium_RHR_plain','medium_RHR_hex','large_RHR_plain',
          'large_RHR_one_hex','large_RHR_hex_adjacent','large_RHR_hex_separated','large_HNR_hex_separated']
    bykey={r['key']:r for r in rows}
    for showface,filename in [(False,'review_paper.png'),(True,'review_composed.png')]:
        review=Image.new('RGB',(1200,990),'#252b28');d=ImageDraw.Draw(review)
        d.text((20,15),'共享素材组合：3 张单卡 + 3 张纸层 + 6 张底堆 + 3 张阴影',font=font(25),fill='#eee5cf')
        for i,key in enumerate(keys):
            row=bykey[key];x=i%3*400;y=75+i//3*300
            d.rounded_rectangle((x+10,y,x+390,y+285),radius=12,fill='#333c35')
            face=None
            if showface:
                ident={'R':'fire_hit','H':'speed_up','N':'repeat_2'}[row['prefix'][0]]
                face=Image.open(SOURCE/'album'/f'{ident}.png').convert('RGBA')
            pic=compose(row,layers,face).resize((390,390),Image.Resampling.LANCZOS)
            review.paste(pic,(x+5,y-65),pic)
            d.text((x+20,y+245),key,font=font(17),fill='#b9d69a')
        review.save(OUT/filename)
    manifest=dict(paper_assets=12,shadow_assets=3,layout_count=len(rows),anchor_256=ANCHOR,
                  materials=list(layers),layouts=rows,main_faces='Existing spell art, separate override symbol',
                  notes='Layouts are transforms and references only, not 201 baked textures.')
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    cards=''.join(f'<figure><img src="master_768/{name}.png"><figcaption>{name}</figcaption></figure>' for name in layers)
    (OUT/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>共享卡堆素材</title><style>body{max-width:1200px;margin:24px auto;background:#252b28;color:#eee5cf;font:18px sans-serif}p{line-height:1.7}.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}figure{background:#333c35;margin:0;padding:12px}figure img{width:100%}img.board{width:100%}a{color:#b9d69a}</style><h1>运行时组合：12 张主体素材 + 3 张接地阴影</h1><p>上部使用三种真实纸层，最多叠三张；下部选择中档两种、厚档四种模板。顶牌主图单独覆盖。只有一个牌堆实体，所有图片属于同一个动画。201 种排列仅存位移和引用，不再各自保存整张贴图。</p><p>下面列出全部15张共享透明素材；下方为按运行时相同图层顺序组合的效果。</p><div class="grid">'''+cards+'''</div><img class="board" src="review_paper.png"><img class="board" src="review_composed.png"><p><a href="manifest.json">图层与定位清单</a></p></html>''',encoding='utf8')

def compile_ground(tools,albums,classes,codes):
    layers=make_materials();rows=layouts();export(layers,rows)
    build=ET.Element('Build',name=BANK);clips=ET.Element('Anims');images={}
    def add(build,images,name,im):
        im=im.resize((256,256),Image.Resampling.LANCZOS)
        box=im.getbbox();images[name]=im.crop(box)
        frame(build,name,name,images[name].size,((box[0]+box[2])/2-128,(box[1]+box[3])/2-136))
    for name,im in layers.items():add(build,images,name,im)
    # The runtime overrides this symbol with the selected spell's existing face.
    im=images['paper_R'];box=layers['paper_R'].resize((256,256),Image.Resampling.LANCZOS).getbbox()
    frame(build,'face','paper_R',im.size,((box[0]+box[2])/2-128,(box[1]+box[3])/2-136))
    for row in rows:anim(clips,row['key'],BANK,row['elements'])
    compile_bank(BANK,build,clips,images,tools)
    archives=[validate_animation_archive(ROOT/'mod/anim'/f'{BANK}.zip')]
    for page in sorted({(code-1)//PAGE_SIZE for code in codes.values()}):
        bank='nw_card_faces_'+str(page);build=ET.Element('Build',name=bank);clips=ET.Element('Anims');images={}
        for ident,code in codes.items():
            if (code-1)//PAGE_SIZE!=page:continue
            symbol='face_'+ident
            add(build,images,symbol,project(albums[ident],0,0))
            anim(clips,'card_'+str(code),bank,[(symbol,0,0)])
        compile_bank(bank,build,clips,images,tools)
        archives.append(validate_animation_archive(ROOT/'mod/anim'/f'{bank}.zip'))
        print('compiled shared face page',page,flush=True)
    manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
    manifest.update(runtime_compiled=True,face_pages=len(archives)-1,spell_faces=len(codes))
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    return archives

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--art-only',action='store_true')
    parser.add_argument('--tools',type=Path,default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools"))
    args=parser.parse_args()
    if args.art_only:export(make_materials(),layouts());print(OUT);return
    from compose_spell_cards import fitted_subject,prepare_frames
    vm=LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path=(ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
    cards=vm.eval('require("nw/cards")');visual=vm.eval('require("nw/card_visuals")')
    codes=dict(cards.codes.items());frames=prepare_frames();albums={};classes={}
    for ident in codes:
        classes[ident]=visual.cards[ident].primary_class
        path=SOURCE/'album'/f'{ident}.png'
        if path.exists():albums[ident]=Image.open(path).convert('RGBA')
        else:
            kind=classes[ident]
            art,_=fitted_subject(ROOT/'assets_src/art_v1/originals'/f'{ident}.png',frames[kind][3],False)
            im=frames[kind][1].copy();im.alpha_composite(art);im.alpha_composite(frames[kind][2]);albums[ident]=im
    archives=compile_ground(args.tools,albums,classes,codes)
    path=ROOT/'test_reports/card_resources.json'
    report=json.loads(path.read_text(encoding='utf8'))
    report.update(archives=archives,shared_paper_assets=12,shared_shadow_assets=3,shared_pile_layouts=201)
    path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    print('PASS: shared piles and face builds compiled',flush=True)

if __name__=='__main__':main()
