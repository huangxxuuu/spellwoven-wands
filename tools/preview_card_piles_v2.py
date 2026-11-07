"""Design study only: composite existing approved card art; never build/install mod assets."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
from compose_spell_cards import OUT as SOURCE, ground

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets_src/spell_cards_composed/v2_pile_study'
SCALE = 3
SIZE = 256 * SCALE
COLORS = {'bg':'#252b28', 'panel':'#333c35', 'text':'#eee5cf', 'muted':'#bdbda8', 'accent':'#b9d69a'}
KINDS = {'R':'basic', 'H':'modifier', 'N':'control'}
IDS = {'R':'fire_hit', 'H':'speed_up', 'N':'repeat_2'}

def font(n):
    return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', n)

def project(im, dx=0, dy=0):
    src = np.array([[96,64],[928,64],[928,960],[96,960]], float)
    dst = (np.array([[72,88],[184,88],[213,184],[43,184]], float) + [dx,dy]) * SCALE
    a, b = [], []
    for (x,y),(u,v) in zip(dst,src):
        a += [[x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]]
        b += [u,v]
    return im.transform((SIZE,SIZE), Image.Transform.PERSPECTIVE,
                        np.linalg.solve(np.array(a),np.array(b)), Image.Resampling.BICUBIC)

FRAMES = {k:(Image.open(SOURCE/'frames'/f'{k}.png').convert('RGBA'),) for k in KINDS.values()}
FACES = {s:Image.open(SOURCE/'album'/f'{ident}.png').convert('RGBA') for s,ident in IDS.items()}

def pile(seq):
    # Paper thickness and fan distance are separate: readable edges, no solid slabs.
    n = len(seq)
    step = 4.2 if n <= 3 else 3.2 if n <= 6 else 2.7
    layers = []
    for i,s in enumerate(seq):
        # Consecutive hexagons share a lateral offset, so their rims form a pair.
        first_hex = i
        while first_hex > 0 and s == 'H' and seq[first_hex-1] == 'H':
            first_hex -= 1
        dx = (8 if first_hex % 2 else -8) if s == 'H' and first_hex else 0
        dy = i*step - (n-1)*step/2 + (9 if s == 'H' and i else 0)
        face = FACES[s] if i == 0 else FRAMES[KINDS[s]][0]
        layers.append(project(face,dx,dy))
    out = Image.new('RGBA',(SIZE,SIZE))
    shadowmask = Image.new('L',out.size)
    for p in layers:
        shadowmask = ImageChops.lighter(shadowmask,p.getchannel('A'))
    shadow = Image.new('RGBA',out.size,(8,10,7,0))
    shadow.putalpha(shadowmask.filter(ImageFilter.GaussianBlur(2*SCALE)).point(lambda a:round(a*.45)))
    out.alpha_composite(shadow,(0,2*SCALE))
    for i in range(n-1,-1,-1):
        p = layers[i]
        edge = Image.new('RGBA',out.size,'#3c3229');edge.putalpha(p.getchannel('A'))
        out.alpha_composite(edge,(0,round(1.25*SCALE)))
        if i:
            tint = Image.new('RGBA',out.size,(53,42,29,0))
            tint.putalpha(p.getchannel('A').point(lambda a:round(a*.16)))
            p = Image.alpha_composite(p,tint)
        out.alpha_composite(p)
    return out

def draw_text(d,xy,text,size=20,fill=None):
    d.text(xy,text,font=font(size),fill=fill or COLORS['text'])

def board(title,subtitle,cases,cols=3):
    cw,ch=440,355
    rows=(len(cases)+cols-1)//cols
    im=Image.new('RGB',(cols*cw+48,rows*ch+150),COLORS['bg']);d=ImageDraw.Draw(im)
    draw_text(d,(24,18),title,30);draw_text(d,(24,65),subtitle,18,COLORS['muted'])
    for i,(name,note,seq,old) in enumerate(cases):
        x=24+(i%cols)*cw;y=112+(i//cols)*ch
        d.rounded_rectangle((x,y,x+cw-14,y+ch-14),radius=14,fill=COLORS['panel'])
        pic=ground(FACES[seq[0]],FRAMES,seq,depth=2,size=SIZE) if old else pile(seq)
        pic=pic.resize((410,410),Image.Resampling.LANCZOS)
        im.paste(pic,(x+8,y-77),pic)
        draw_text(d,(x+16,y+253),name,21,COLORS['accent'])
        for j,line in enumerate(note.split('\n')):draw_text(d,(x+16,y+286+j*23),line,16,COLORS['muted'])
    return im

def grounding():
    im=Image.new('RGB',(1368,660),COLORS['bg']);d=ImageDraw.Draw(im)
    draw_text(d,(24,18),'落地与遮挡：定位点移到接地面中心',30)
    draw_text(d,(24,65),'遮挡关系示意；人物为示意轮廓。正式渲染必须让人物始终盖住卡牌。',18,COLORS['muted'])
    for i,(title,front) in enumerate([('当前：前沿定位，卡牌挡住脚部',True),('建议：中心定位，人物绘制在卡牌上方',False)]):
        x=24+i*672;y=115
        d.rounded_rectangle((x,y,x+648,y+510),radius=14,fill=COLORS['panel'])
        draw_text(d,(x+18,y+18),title,22,COLORS['accent'])
        p=ground(FACES['R'],FRAMES,'RHR',depth=2,size=SIZE) if front else pile('RHR')
        p=p.resize((580,580),Image.Resampling.LANCZOS)
        # Abstract actor drawn on its own layer, avoiding any changes to screenshots.
        actor=Image.new('RGBA',im.size);ad=ImageDraw.Draw(actor)
        cx=x+300;cy=y+260
        ad.ellipse((cx-33,cy-150,cx+33,cy-83),fill='#bba38b',outline='#1a201d',width=4)
        ad.polygon([(cx-36,cy-76),(cx+35,cy-76),(cx+52,cy+18),(cx-48,cy+18)],fill='#6a8c80',outline='#1a201d',width=4)
        for off in (-27,23):
            ad.line((cx+off,cy+12,cx+off,cy+76),fill='#1a201d',width=17)
            ad.ellipse((cx+off-13,cy+68,cx+off+24,cy+83),fill='#1a201d')
        if front: im.paste(actor,(0,0),actor)
        im.paste(p,(x+36,y+2),p)
        if not front: im.paste(actor,(0,0),actor)
        anchor=(x+326,y+460) if front else (x+326,y+310)
        d=ImageDraw.Draw(im);ax,ay=anchor
        d.line((ax-10,ay,ax+10,ay),fill='#e6b76a',width=3);d.line((ax,ay-10,ax,ay+10),fill='#e6b76a',width=3)
        draw_text(d,(x+18,y+470),'十字：定位点；卡牌位于地面层，阴影紧贴底部。' if not front else '普通物体排序 + 底边定位，容易出现遮挡。',17,COLORS['muted'])
    return im

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    cases=[
        ('旧版 · 三张 R / H / R','六边形被矩形覆盖，仅剩一个尖角','RHR',True),
        ('建议 · 三张 R / H / R','六边形侧前方错开，露出连续斜边','RHR',False),
        ('建议 · 三张 H / R / H','每张保持真实轮廓；纸边轻薄','HRH',False),
        ('2 张 · 矩形 + 六边形','恰好两层，不额外画虚构的第三层','RH',False),
        ('3 张 · 凹口 + 六边形 + 矩形','前三层保留 R / H / N 的真实轮廓','NHR',False),
        ('3 张 · 六边形 + 凹口 + 矩形','凹口存在于轮廓中；被压住时自然遮挡','HNR',False),
    ]
    board('小牌堆与六边形露出对照','R = 矩形，H = 六边形，N = 顶部凹口；顺序从顶到底。现有卡面合成，非游戏截图。',cases).save(OUT/'01_small_and_hex.png')
    cases=[
        ('2 张 · 轻薄','示例 R / H；真实两层','RH',False),
        ('3 张 · 轻薄','示例 R / H / R；真实三层','RHR',False),
        ('4–8 张 · 下部无六边形','前三层 R / H / R；下部矩形纸层','RHRRRR',False),
        ('4–8 张 · 下部含六边形','前三层不变；下部加入六角折边','RHRRHR',False),
        ('9+ 张 · 下部无六边形','前三层不变；下部加厚，保持平放','RHRRRRRRR',False),
        ('9+ 张 · 下部仅 1 张六边形','下部一个六角层，避免暗示多个','RHRRRHRRR',False),
        ('9+ 张 · 多六边形 A：靠拢','两张直接相邻、对齐，中间不夹矩形','RHRRHHRRR',False),
        ('9+ 张 · 多六边形 B：分隔','两张被较厚的矩形纸层隔开','RHRHRRRRH',False),
        ('换顶牌 · 同一规则','顶牌更换为六边形，分档规则不变','HNRHRRRRH',False),
    ]
    board('四档厚度与下部纸层方案','4 张起：前三层按实际顺序；第四层以后是数量档位示意，不逐张复刻。',cases).save(OUT/'02_tiers.png')
    grounding().save(OUT/'03_grounding.png')
    # Individual transparent assets make the study reusable in the next runtime implementation.
    for seq in sorted({c[2] for c in cases} | {'RHR','HRH','NHR','HNR'}):pile(seq).save(OUT/(seq+'.png'))
    (OUT/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>地面卡堆方案</title><style>body{margin:24px auto;max-width:1368px;background:#252b28;color:#eee5cf;font:18px sans-serif}img{width:100%;display:block;margin:24px 0}p{line-height:1.7}a{color:#b9d69a}</style><h1>地面卡牌与牌堆 · 方案预览</h1><p>复用现有已确认主图，脚本合成。未修改或安装游戏资源。小牌堆逐层真实；大牌堆前三层真实，下部按数量和六边形分布简化。固定随机外观，避免刷新跳变。</p><p>落地实现建议：采用地面绘制层，定位点移至接地面中心；现有贴图已经透视，不能再直接套一次地面投影。拾取范围与定位同步检查。前三张保留矩形、六边形、凹口的真实轮廓，下面只做纸层示意；被遮挡的凹口不强行露出。第四张起统计六边形：4–8 张分无／有，9 张起分无／1 张／多张；多张的靠拢与分隔样式由服务器选择并保存，不在刷新时重抽。正式接入时保持下部连续纸边，不因模板改变真实容器顺序或数量。</p><img src="01_small_and_hex.png"><img src="02_tiers.png"><img src="03_grounding.png"></html>''',encoding='utf8')
    (OUT/'manifest.json').write_text(json.dumps({'runtime_modified':False,'source':str(SOURCE),'tiers':['2','3','4-8','9+'],'hex_offset':[8,9],'ground_quad':[[72,88],[184,88],[213,184],[43,184]],'review_images':['01_small_and_hex.png','02_tiers.png','03_grounding.png']},ensure_ascii=False,indent=2),encoding='utf8')
    print(OUT)

if __name__=='__main__':main()
