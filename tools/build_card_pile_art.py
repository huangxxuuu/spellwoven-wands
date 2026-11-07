"""Export the approved four-tier paper piles as reusable transparent art.

This uses existing approved frame artwork and deterministic compositing; it does
not call image generation, modify inventory art, compile archives or install mods.
"""
from functools import lru_cache
from itertools import product
from pathlib import Path
import hashlib
import json
import math

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets_src/spell_cards_composed/v1'
OUT = ROOT / 'assets_src/spell_cards_composed/v3_pile_materials'
SCALE = 3
SIZE = 256 * SCALE
ANCHOR = (128,136)
KINDS = {'R':'basic','H':'modifier','N':'control'}
TAILS = {
    'medium': {'plain':'RRR','hex':'RHR'},
    'large': {'plain':'RRRRRR','one_hex':'RRHRRR',
              'hex_adjacent':'RHHRRR','hex_separated':'HRRRRH'},
}
LABELS = {'single':'单张','two':'2 张','three':'3 张','medium':'4–8 张','large':'9 张以上',
          'plain':'下部无六边形','hex':'下部含六边形','one_hex':'下部一个六边形',
          'hex_adjacent':'下部双六边形相邻','hex_separated':'下部双六边形分隔','exact':'逐层真实'}
FRAMES = {s:Image.open(SOURCE/'frames'/f'{k}.png').convert('RGBA') for s,k in KINDS.items()}

def font(n):
    return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',n)

def positions(sequence):
    n=len(sequence)
    step=4.2 if n<=3 else 3.2 if n<=6 else 2.7
    result=[]
    for i,s in enumerate(sequence):
        start=i
        while start>0 and s=='H' and sequence[start-1]=='H':start-=1
        x=(8 if start%2 else -8) if s=='H' and start else 0
        y=i*step+(9 if s=='H' and i else 0)
        result.append((x,y))
    # All source PNGs use the centre of the bottom paper as the ground anchor.
    bx,by=result[-1]
    return [(x-bx,y-by) for x,y in result]

def project(im,x,y):
    src=np.array([[96,64],[928,64],[928,960],[96,960]],float)*im.width/1024
    dst=(np.array([[72,88],[184,88],[213,184],[43,184]],float)+[x,y])*SCALE
    a,b=[],[]
    for (u,v),(sx,sy) in zip(dst,src):
        a += [[u,v,1,0,0,0,-sx*u,-sx*v],[0,0,0,u,v,1,-sy*u,-sy*v]]
        b += [sx,sy]
    return im.transform((SIZE,SIZE),Image.Transform.PERSPECTIVE,np.linalg.solve(np.array(a),np.array(b)),Image.Resampling.BICUBIC)

@lru_cache(maxsize=128)
def paper(shape,x,y):
    return project(FRAMES[shape],x,y)

def render(sequence):
    poses=positions(sequence)
    layers=[paper(s,round(x,3),round(y,3)) for s,(x,y) in zip(sequence,poses)]
    mask=Image.new('L',(SIZE,SIZE))
    for layer in layers:mask=ImageChops.lighter(mask,layer.getchannel('A'))
    shadow=Image.new('RGBA',(SIZE,SIZE),(8,10,7,0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(2*SCALE)).point(lambda a:round(a*.45)))
    out=Image.new('RGBA',(SIZE,SIZE));out.alpha_composite(shadow,(0,2*SCALE))
    for i in range(len(layers)-1,-1,-1):
        layer=layers[i]
        # Each side wall follows its own actual silhouette. Never fill H with R.
        edge=Image.new('RGBA',out.size,'#3c3229');edge.putalpha(layer.getchannel('A'))
        out.alpha_composite(edge,(0,round(1.25*SCALE)))
        if i:
            tint=Image.new('RGBA',out.size,(53,42,29,0))
            tint.putalpha(layer.getchannel('A').point(lambda a:round(a*.16)))
            layer=Image.alpha_composite(layer,tint)
        out.alpha_composite(layer)
    return out

def variants():
    for shape in KINDS:yield 'single','exact',shape,shape
    for n,tier in [(2,'two'),(3,'three')]:
        for letters in product(KINDS,repeat=n):
            seq=''.join(letters);yield tier,'exact',seq,seq
    for tier,tails in TAILS.items():
        for letters in product(KINDS,repeat=3):
            prefix=''.join(letters)
            for style,tail in tails.items():yield tier,style,prefix,prefix+tail

def sheet(rows,title,path,cols=3,faces=False):
    cw,ch=400,300;header=95
    image=Image.new('RGB',(cols*cw,header+math.ceil(len(rows)/cols)*ch),'#252b28')
    d=ImageDraw.Draw(image);d.text((22,16),title,font=font(27),fill='#eee5cf')
    d.text((22,55),'正式透明素材合成预览 · R 矩形 / H 六边形 / N 凹口 · 从顶到底',font=font(16),fill='#bdbda8')
    for i,row in enumerate(rows):
        x=i%cols*cw;y=header+i//cols*ch
        d.rounded_rectangle((x+10,y,x+cw-10,y+ch-12),radius=12,fill='#333c35')
        im=Image.open(OUT/row['master']).convert('RGBA')
        if faces:
            ident={'R':'fire_hit','H':'speed_up','N':'repeat_2'}[row['prefix'][0]]
            top=Image.open(SOURCE/'album'/f'{ident}.png').convert('RGBA')
            im.alpha_composite(project(top,*row['top_offset_256']))
        im=im.resize((390,390),Image.Resampling.LANCZOS)
        image.paste(im,(x+5,y-60),im)
        label=LABELS[row['tier']]+' · '+row['prefix']
        d.text((x+22,y+233),label,font=font(20),fill='#b9d69a')
        d.text((x+22,y+263),LABELS[row['style']],font=font(16),fill='#bdbda8')
    image.save(path)

def gallery(rows):
    data=json.dumps(rows,ensure_ascii=False).replace('</','<\\/')
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>正式卡堆素材</title>
<style>body{margin:24px;background:#252b28;color:#eee5cf;font:17px sans-serif}p{max-width:1100px;line-height:1.7}a{color:#b9d69a}select,button{padding:8px;margin:4px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:14px}.card{background:#333c35;border-radius:12px;padding:12px}.card img{width:100%}.card p{margin:8px 0}small{color:#bdbda8}</style>
<h1>四档卡堆 · 正式透明美术素材</h1>
<p>198 种牌堆 + 3 种配套单卡底纸。768×768 透明母版与 256×256 运行时备选稿。顶牌为空白纸框，后续叠加现有主图；前三层完整保留 R/H/N 轮廓。下部模板仅表示档位，不代表实际容器顺序。已修正相邻双六边形，中间不夹矩形。</p>
<p>素材定位点统一为 256 坐标下的 (128,136)，对应最底层纸的接地中心。顶牌偏移和源坐标写入 manifest.json。图片已包含透视，接入时不要重复投影。地面绘制层、拾取定位、变体选择和同步仍需在运行时代码中接入；本次未修改 Mod。</p>
<p><a href="review_art.png">空白素材总览</a> · <a href="review_composed.png">叠加主图预览</a> · <a href="review_small.png">2、3 张的全部排列</a> · <a href="review_sizes.png">大小与背景检查</a> · <a href="manifest.json">接入清单</a></p>
<select id="tier"><option value="">所有数量档位</option><option value="two">2 张</option><option value="three">3 张</option><option value="medium">4–8 张</option><option value="large">9 张以上</option><option value="single">单张底纸</option></select>
<select id="shape"><option value="">所有顶牌</option><option>R</option><option>H</option><option>N</option></select><button id="bg">切换浅底</button><p id="count"></p><div class="grid" id="grid"></div>
<script>const rows=DATA;const tier=document.querySelector('#tier'),shape=document.querySelector('#shape');function render(){const selected=rows.filter(r=>(!tier.value||r.tier===tier.value)&&(!shape.value||r.prefix[0]===shape.value));document.querySelector('#count').textContent=selected.length+' 个素材';document.querySelector('#grid').innerHTML=selected.map(r=>`<article class="card"><a href="${r.master}"><img loading="lazy" src="${r.master}"></a><p>${r.id}</p><small>${r.sequence}</small><p><a href="${r.runtime}">256 PNG</a> · <a href="${r.master}">768 PNG</a></p></article>`).join('')}tier.onchange=shape.onchange=render;document.querySelector('#bg').onclick=()=>document.querySelectorAll('.card').forEach(c=>c.style.background=c.style.background?'':'#b8b5a4');render();</script></html>'''
    (OUT/'index.html').write_text(page.replace('DATA',data),encoding='utf8')

def main():
    for name in ['master_768','runtime_256']:(OUT/name).mkdir(parents=True,exist_ok=True)
    rows=[]
    for tier,style,prefix,seq in variants():
        ident=f'{tier}_{prefix}_{style}'
        im=render(seq)
        box=im.getbbox()
        assert box and min(box[:2])>0 and max(box[2:])<SIZE,ident+' clipped'
        master=f'master_768/{ident}.png';runtime=f'runtime_256/{ident}.png'
        im.save(OUT/master);im.resize((256,256),Image.Resampling.LANCZOS).save(OUT/runtime)
        rows.append(dict(id=ident,tier=tier,style=style,prefix=prefix,sequence=seq,
                         master=master,runtime=runtime,top_offset_256=positions(seq)[0],
                         alpha_bbox_768=list(box),sha256=hashlib.sha256((OUT/master).read_bytes()).hexdigest()))
        if len(rows)%30==0:print(f'exported {len(rows)}',flush=True)
    assert len(rows)==201 and len({r['id'] for r in rows})==201
    for row in rows:
        seq=row['sequence']
        if row['tier'] in ('two','three'):assert len(seq)==(2 if row['tier']=='two' else 3)
        if row['style']=='hex_adjacent':assert seq[3:].count('H')==2 and 'HH' in seq[3:]
        if row['style']=='hex_separated':assert seq[3:].count('H')==2 and 'HH' not in seq[3:]
        if row['style']=='plain':assert 'H' not in seq[3:]
    counts={tier:sum(r['tier']==tier for r in rows) for tier in ['single','two','three','medium','large']}
    sources={s:{'path':str(SOURCE/'frames'/f'{k}.png'),'sha256':hashlib.sha256((SOURCE/'frames'/f'{k}.png').read_bytes()).hexdigest()} for s,k in KINDS.items()}
    manifest=dict(version=1,runtime_modified=False,generated_with='tools/build_card_pile_art.py',
                  method='deterministic composition of approved paper/frame artwork',counts=counts,
                  master_size=SIZE,runtime_size=256,anchor_256=ANCHOR,ground_quad_256=[[72,88],[184,88],[213,184],[43,184]],
                  tails=TAILS,sources=sources,variants=rows,
                  runtime_notes={'ordering':'first occupied slots, never reorder container contents',
                  'large_multiple_hex':'server selects adjacent/separated once; persist selection across reloads',
                  'grounding':'use ground draw layer, pivot at anchor; avoid a second perspective transform'})
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    sample_ids=['two_RH_exact','three_RHR_exact','medium_RHR_plain','medium_RHR_hex',
                'large_RHR_plain','large_RHR_one_hex','large_RHR_hex_adjacent','large_RHR_hex_separated','large_HNR_hex_separated']
    byid={r['id']:r for r in rows};samples=[byid[i] for i in sample_ids]
    sheet(samples,'正式素材 · 四档厚度与六边形分布',OUT/'review_art.png')
    sheet(samples,'叠加现有主图 · 四档牌堆',OUT/'review_composed.png',faces=True)
    sheet([r for r in rows if r['tier'] in ('two','three')],'2 张、3 张 · 全部真实轮廓组合',OUT/'review_small.png',cols=6)
    review=Image.new('RGB',(1200,740),'#252b28');d=ImageDraw.Draw(review)
    d.text((20,15),'256 / 128 / 64 像素与深浅背景检查',font=font(28),fill='#eee5cf')
    for j,(size,bg) in enumerate([(256,'#333c35'),(128,'#b8b5a4'),(64,'#333c35')]):
        y=70+j*220;d.rectangle((0,y,1200,y+215),fill=bg)
        for i,row in enumerate([samples[k] for k in [1,3,6,7]]):
            im=Image.open(OUT/row['master']).resize((size,size),Image.Resampling.LANCZOS)
            review.paste(im,(i*300+(300-size)//2,y+(180-size)//2),im)
            d.text((i*300+15,y+184),f'{size}px · '+LABELS[row['style']],font=font(15),fill='#171b17' if j==1 else '#eee5cf')
    review.save(OUT/'review_sizes.png');gallery(rows)
    (OUT/'validation.json').write_text(json.dumps({'counts':counts,'total':201,'transparent_exports':402,
        'all_alpha_bounds_inside_canvas':True,'adjacent_and_separated_sequences_checked':True,
        'runtime_modified':False},ensure_ascii=False,indent=2),encoding='utf8')
    print('PASS',OUT,counts,flush=True)

if __name__=='__main__':main()
