"""Compose selected art, frames, payload badges and true-footprint paper piles.

Writes review/export assets only; never modifies source art or game resources.
"""
from pathlib import Path
from collections import Counter
from urllib.parse import unquote
import json
import math
import html
import hashlib
import argparse
from functools import lru_cache
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'assets_src/spell_cards_composed/v1'
CAT = ROOT/'assets_src/spell_card_subjects/v3_full_catalog'
RETRY = ROOT/'assets_src/spell_card_subjects/v4_retry_three'
SUBJECTS = ROOT/'assets_src/spell_card_subjects'
S = 1024
RES = Image.Resampling.LANCZOS
INVENTORY_BADGE_POS = (180,180)  # Logical 45,45; keep the whole badge inside 64px.
INVENTORY_RESERVE = (44*16,44*16,64*16,64*16)
KINDS = {'basic':'R','modifier':'H','control':'N'}
LABELS = {'basic':'基础法术','modifier':'法术修饰','control':'施法控制'}
SHAPES = {
 'R':[(4,0),(48,0),(52,4),(52,52),(48,56),(4,56),(0,52),(0,4)],
 'H':[(26,0),(52,12),(52,44),(26,56),(0,44),(0,12)],
 'N':[(4,0),(18,0),(18,8),(34,8),(34,0),(48,0),(52,4),(52,52),(48,56),(4,56),(0,52),(0,4)],
}
CONTROL = set('double triple trident_cast wild_double two_way cast_four hex_cast imprint_hit imprint_timer repeat_2 repeat_3 repeat_4'.split())
FAMILIES = set('spark arrow heavy scatter fire frost'.split())
BADGES = {'hit':'碰撞载荷','timer':'定时载荷','break':'被击破载荷'}
BADGE_ART = {'hit':CAT/'projectiles_controls/imprint_hit.png', 'timer':CAT/'projectiles_controls/imprint_timer.png', 'break':CAT/'fields/payload_egg.png'}

def dump(path, value):
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def save(im, path):
 path.parent.mkdir(parents=True,exist_ok=True);im.save(path)

def font(size):
 return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',size)

def mask_for(points, size):
 im=Image.new('L',(size,size));ImageDraw.Draw(im).polygon(points,fill=255);return im

def inset_polygon(points, distance):
 # Offset each edge towards the paper, including the three concave notch edges.
 # Scaling towards the center incorrectly paints over the notch's vertical rim.
 edges=[]
 for i,(x,y) in enumerate(points):
  nx,ny=points[(i+1)%len(points)];dx,dy=nx-x,ny-y;length=math.hypot(dx,dy)
  edges.append((x-dy/length*distance,y+dx/length*distance,dx,dy))
 result=[]
 for i,(x,y,dx,dy) in enumerate(edges):
  px,py,pdx,pdy=edges[i-1];cross=pdx*dy-pdy*dx
  assert abs(cross)>1e-8,'Adjacent edges must not be parallel'
  t=((x-px)*dy-(y-py)*dx)/cross
  result.append((px+t*pdx,py+t*pdy))
 return result

def simple_plate(kind, size=256):
 # Independent simplified inventory frame: no downsampled fine engraving.
 # Fill more of the inventory slot: 60x62 logical pixels, with a narrow outer margin.
 pts=[((2+x*60/52)*size/64,(1+y*62/56)*size/64) for x,y in SHAPES[KINDS[kind]]]
 def contour(scale):
  if kind=='control':return inset_polygon(pts,(1-scale)*30*size/64)
  return [(size/2+(x-size/2)*scale,size/2+(y-size/2)*scale) for x,y in pts]
 im=Image.new('RGBA',(size,size));d=ImageDraw.Draw(im)
 for scale,color in [(1,'#292727'),(.962,'#AD9A7D'),(.94,'#51463F'),(.89,'#282727'),(.87,'#DED6C5')]:
  d.polygon(contour(scale),fill=color)
 inner=mask_for(contour(.87),size)
 a=np.zeros((size,size,4),dtype=np.uint8)
 for y in range(size):a[y,:,:]=[round(229-12*y/size),round(224-14*y/size),round(212-16*y/size),255]
 im.paste(Image.fromarray(a),(0,0),inner)
 return im,inner

def prepare_frames():
 frames={}
 for kind in KINDS:
  source=ROOT/'assets_src/spell_card_frames/v3_refined_magic/refined_magic_collector_basic.png' if kind=='basic' else OUT/f'frames/{kind}.raw.png'
  im=Image.open(source).convert('RGBA');a=im.getchannel('A')
  box=a.point(lambda v:255 if v>=16 else 0).getbbox();im=im.crop(box).resize((832,896),RES)
  # Export normalization only: opaque paper, transparent exterior. Originals stay untouched.
  alpha=im.getchannel('A').point(lambda v:0 if v<=8 else 255 if v>=128 else v)
  im.putalpha(alpha);plate=Image.new('RGBA',(S,S));plate.alpha_composite(im,(96,64))
  arr=np.asarray(plate)
  bright=((arr[:,:,:3].min(2)>145)&(arr[:,:,3]>128)).astype('uint8')*255
  interior=Image.fromarray(bright).copy();ImageDraw.floodfill(interior,(512,512),128)
  interior=interior.point(lambda v:255 if v==128 else 0)
  assert interior.getbbox() and interior.getpixel((512,512))==255
  safe=interior.filter(ImageFilter.MinFilter(25))
  paper=plate.copy();paper.putalpha(interior)
  rim=plate.copy();rim.putalpha(ImageChops.subtract(plate.getchannel('A'),interior))
  save(plate,OUT/f'frames/{kind}.png');save(paper,OUT/f'layers/{kind}.paper.png');save(rim,OUT/f'layers/{kind}.rim.png');save(safe,OUT/f'layers/{kind}.safe.png')
  small,small_inner=simple_plate(kind)
  frames[kind]=(plate,paper,rim,safe,small,small_inner)
 return frames

def badge_subject(kind):
 im=Image.open(BADGE_ART[kind]).convert('RGBA')
 box=im.getchannel('A').point(lambda a:255 if a>=8 else 0).getbbox()
 return im.crop(box)

@lru_cache(maxsize=16)
def badge(kind, size):
 # Reuse the approved spell illustration, uniformly scaled; no symbol redraw.
 n=288;im=Image.new('RGBA',(n,n));d=ImageDraw.Draw(im)
 pts=[(28,4),(260,4),(284,28),(284,260),(260,284),(28,284),(4,260),(4,28)]
 d.polygon(pts,fill='#E2DAC8');d.line(pts+[pts[0]],fill='#3C3631',width=20,joint='curve')
 subject=badge_subject(kind);subject.thumbnail((230,230),RES)
 im.alpha_composite(subject,((n-subject.width)//2,(n-subject.height)//2))
 return im.resize((size,size),RES)

def save_badge_svg(kind):
 save(badge_subject(kind),OUT/f'badges/{kind}.subject.png')
 svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18"><path d="M 1.8 .3 H 16.2 L 17.7 1.8 V 16.2 L 16.2 17.7 H 1.8 L .3 16.2 V 1.8 Z" fill="#E2DAC8" stroke="#3C3631" stroke-width="1.2"/><image href="'+kind+'.subject.png" x="1.8125" y="1.8125" width="14.375" height="14.375" preserveAspectRatio="xMidYMid meet"/></svg>'
 (OUT/f'badges/{kind}.svg').write_text(svg,encoding='utf8')

def art_source(row, entries):
 ident=row.get('base') or row['id']
 overrides=json.loads((SUBJECTS/'selected_overrides.json').read_text(encoding='utf8'))
 if ident in overrides:return SUBJECTS/overrides[ident]
 override=RETRY/f'{ident}.png'
 if ident in {'knockback','repeat_2','target_neutral'}:return override
 return (CAT/unquote(entries[ident]['image'])).resolve()

def fitted_subject(source,safe,reserve,reserve_box=None):
 im=Image.open(source).convert('RGBA');a=im.getchannel('A')
 box=a.point(lambda v:255 if v>=8 else 0).getbbox()
 im=im.crop(box)
 if reserve:
  safe=safe.copy();ImageDraw.Draw(safe).rectangle(reserve_box or (42*16,43*16,62*16,63*16),fill=0)
 # Search real silhouette against the frame interior instead of fitting the canvas.
 mask=np.asarray(safe.resize((256,256),Image.Resampling.NEAREST))>0
 alpha=im.getchannel('A');cx,cy=128,124 if reserve else 128
 lo,hi=0,min(240/im.width,240/im.height)
 for _ in range(15):
  scale=(lo+hi)/2;w=max(1,round(im.width*scale));h=max(1,round(im.height*scale));x=cx-w//2;y=cy-h//2
  visible=np.asarray(alpha.resize((w,h),Image.Resampling.BILINEAR))>=8
  ok=x>=0 and y>=0 and x+w<=256 and y+h<=256 and not np.any(visible&~mask[y:y+h,x:x+w])
  if ok:lo=scale
  else:hi=scale
 scale=lo*4*.985
 while True:
  w=max(1,round(im.width*scale));h=max(1,round(im.height*scale));x=cx*4-w//2;y=cy*4-h//2
  art=im.resize((w,h),RES);vis=np.asarray(art.getchannel('A'))>=8
  ok=not np.any(vis&~(np.asarray(safe)[y:y+h,x:x+w]>0))
  if ok:break
  scale*=.99
 layer=Image.new('RGBA',(S,S));layer.alpha_composite(art,(x,y))
 return layer,{'source_bbox':box,'position':[x,y],'fitted_size':[w,h],'uniform_scale':scale,'reserve_badge':reserve,'inside_safe_mask':ok}

def perspective(im,elevation=0,size=256):
 # A single homography transforms paper, subject, rim and badge together.
 src=np.array([[96,64],[928,64],[928,960],[96,960]],float)*im.width/1024
 dst=np.array([[72,70-elevation],[184,70-elevation],[213,202-elevation],[43,202-elevation]],float)*size/256
 mat=[];b=[]
 for (x,y),(u,v) in zip(dst,src):
  mat += [[x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]];b += [u,v]
 coeff=np.linalg.solve(np.array(mat),np.array(b))
 return im.transform((size,size),Image.Transform.PERSPECTIVE,coeff,Image.Resampling.BICUBIC)

def ground(top,frames,sequence='R',depth=2,size=256):
 # The last layer is anchored to the same contact height for every thickness.
 out=Image.new('RGBA',(size,size));m=Image.new('L',(size,size))
 for kind in sequence:
  blank=frames['modifier' if kind=='H' else 'basic'][0]
  m=ImageChops.lighter(m,perspective(blank,-depth,size).getchannel('A'))
 shadow=Image.new('RGBA',out.size,(26,23,21,0));shadow.putalpha(m.point(lambda a:round(a*.32)).filter(ImageFilter.GaussianBlur(size/128)))
 out.alpha_composite(shadow)
 for i in range(len(sequence)-1,-1,-1):
  elevation=(len(sequence)-1-i)*depth
  face=top if i==0 else frames['modifier' if sequence[i]=='H' else 'basic'][0]
  projected=perspective(face,elevation,size)
  # Extrusion uses only this layer's real footprint: H has no rectangular feet.
  for off in range(round(depth*size/256),0,-1):
   edge=Image.new('RGBA',out.size,('#4D4338' if off==round(depth*size/256) else '#B5A58C'))
   edge.putalpha(projected.getchannel('A'))
   out.alpha_composite(edge,(0,off))
  if i>0:
   # Overhanging upper paper shades exposed portions of the lower paper.
   upp=frames['modifier' if sequence[i-1]=='H' else 'basic'][0]
   cast=perspective(upp,elevation-1,size).getchannel('A')
   shade=Image.new('RGBA',out.size,(48,40,32,0));shade.putalpha(ImageChops.multiply(cast,projected.getchannel('A')).point(lambda a:round(a*.48)))
   projected.alpha_composite(shade)
  out.alpha_composite(projected)
 return out

def sheet(items, filename, cols=4, cell=(270,320)):
 w,h=cell;out=Image.new('RGB',(w*cols,h*math.ceil(len(items)/cols)), '#DFDAD1');d=ImageDraw.Draw(out)
 for i,(label,im) in enumerate(items):
  x=i%cols*w;y=i//cols*h
  thumb=im.copy();thumb.thumbnail((w-22,h-52),RES)
  out.paste(thumb,(x+(w-thumb.width)//2,y+8),thumb)
  d.text((x+w//2,y+h-31),label,font=font(15),fill='#292727',anchor='mm')
 save(out,OUT/filename)

def main(only_badges=False,only_cards=None):
 OUT.mkdir(parents=True,exist_ok=True)
 roster=json.loads((CAT/'roster.json').read_text(encoding='utf8'))
 for extension in (SUBJECTS/'v7_pitch_modifiers/cards.json',SUBJECTS/'v9_music_octave/cards.json',SUBJECTS/'v10_shrink_shot/cards.json',SUBJECTS/'v11_dark_fog_20261113/cards.json'):
  if extension.exists():
   extra=json.loads(extension.read_text(encoding='utf8'))
   if extra.get('runtime_registered'):
    roster += [dict(r,base=None,event=None,status='selected_extension',group='music_targets') for r in extra['cards']]
 entries={x['id']:x for x in json.loads((CAT/'catalog.json').read_text(encoding='utf8'))['items']}
 # Art-review labels can differ from historical runtime IDs without changing audio.
 label_file=SUBJECTS/'selected_labels.json'
 labels=json.loads(label_file.read_text(encoding='utf8')) if label_file.exists() else {}
 # Persist explicit per-ID mapping so future unknown cards cannot silently default.
 mapping={}
 for r in roster:
  if r['id'] in CONTROL:k='control'
  elif r['kind']=='modifier':k='modifier'
  elif r['kind'] in {'projectile','melee','field','instant','note'}:k='basic'
  else:raise ValueError(r['id'])
  badge_kind=r['event'] if r.get('base') else {'delay_seal':'timer','payload_egg':'break'}.get(r['id'])
  assert badge_kind in {None,'hit','timer','break'}
  mapping[r['id']]={'primary_class':k,'mechanism_badge':badge_kind}
 dump(OUT/'card_visuals.json',mapping)
 frames=prepare_frames()
 for b in BADGES:
  save(badge(b,288),OUT/f'badges/{b}.png');save_badge_svg(b)
 cards={};rows=[];cache={}
 previous={x['id']:x for x in json.loads((OUT/'manifest.json').read_text(encoding='utf8'))['cards']} if only_badges or only_cards else {}
 if only_cards:assert set(only_cards)<={r['id'] for r in roster},'Unknown card IDs'
 for r in roster:
  ident=r['id'];kind=mapping[ident]['primary_class'];b=mapping[ident]['mechanism_badge']
  if (only_badges and b is None) or (only_cards and ident not in only_cards):
   rows.append(previous[ident]);cards[ident]=Image.open(OUT/f'album/{ident}.png').convert('RGBA');continue
  source=art_source(r,entries);family=r.get('base') or ident;reserve=family in FAMILIES or b is not None
  key=(str(source),kind,reserve)
  if key not in cache:cache[key]=fitted_subject(source,frames[kind][3],reserve)
  art,fit=cache[key];plate,paper,rim,safe,small,small_inner=frames[kind]
  card=paper.copy();card.alpha_composite(art);card.alpha_composite(rim)
  if b:card.alpha_composite(badge(b,288),(688,704))
  save(card,OUT/f'album/{ident}.png');cards[ident]=card
  # Inventory frame is separately simplified; retain the same subject placement.
  smallkey=key+('inventory',)
  if smallkey not in cache:
   smallsafe=small_inner.resize((S,S),Image.Resampling.NEAREST).filter(ImageFilter.MinFilter(17))
   cache[smallkey]=fitted_subject(source,smallsafe,reserve,INVENTORY_RESERVE)
  smallart,smallfit=cache[smallkey]
  icon=small.copy();icon.alpha_composite(smallart.resize((256,256),RES))
  if b:icon.alpha_composite(badge(b,72),INVENTORY_BADGE_POS)
  for size in (128,64,32):save(icon.resize((size,size),RES),OUT/f'inventory_{size}/{ident}.png')
  save(ground(card,frames,KINDS[kind]),OUT/f'ground/{ident}.png')
  rows.append({'id':ident,'name':labels.get(ident,r['name']),**mapping[ident],'source':source.relative_to(ROOT).as_posix(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'origin':r['status'],'layout':fit,'inventory_layout':smallfit,'album':f'album/{ident}.png','inventory':f'inventory_64/{ident}.png','ground':f'ground/{ident}.png'})
  if len(rows)%30==0:print('composed',len(rows),flush=True)
 # Badge must sit mostly inside the card, with a small visible rim overlap.
 bm=np.asarray(badge('hit',288).getchannel('A'))>128
 cardmask=np.asarray(frames['basic'][0].getchannel('A'))[704:992,688:976]>128
 overlap=float(np.count_nonzero(bm&cardmask)/np.count_nonzero(bm));assert overlap>=.70,overlap
 # Same family is exactly the same subject layout, including its undecorated card.
 for base in FAMILIES:
  familyrows=[x for x in rows if x['id'] in [base,base+'_hit',base+'_timer']]
  assert len(familyrows)==3 and all(json.dumps([x['layout'],x['inventory_layout']],sort_keys=True)==json.dumps([familyrows[0]['layout'],familyrows[0]['inventory_layout']],sort_keys=True) for x in familyrows)
 assert Counter(x['mechanism_badge'] for x in rows)=={None:len(rows)-14,'hit':6,'timer':7,'break':1}
 topids={'R':'fire_hit','H':'speed_up','N':'repeat_2'};piles=[]
 for base in ('RR','HR','RH','HH'):
  for top in 'RHN':
   seq=top+base;ident=topids[top]
   for tier,depth in [('thin',2),('medium',3.5),('thick',5)]:
    im=ground(cards[ident],frames,seq,depth,size=512);save(im,OUT/f'piles/{seq}_{tier}.png')
    if tier=='thin':piles.append((seq,im))
 sheet(piles,'pile_matrix.png',3,(400,350))
 examples=['fire','frost','heavy','edge_farm_hoe','speed_up','repeat_2','fire_hit','fire_timer','delay_seal','payload_egg','imprint_hit','knockback']
 sheet([(next(x['name'] for x in rows if x['id']==i),cards[i]) for i in examples],'cards_review.png')
 sheet([(BADGES[b],badge(b,288)) for b in BADGES],'badges_review.png',3,(230,260))
 # Exact-size exports with count overlays only in this review image, never in assets.
 tiny=Image.new('RGB',(1100,330),'#38332E');d=ImageDraw.Draw(tiny)
 for n,i in enumerate(examples[:10]):
  x=n*108+8
  for y,size in [(36,64),(170,32)]:
   im=Image.open(OUT/f'inventory_{size}/{i}.png');tiny.paste(im,(x,y),im)
   d.text((x+size/2,y), '12',font=font(max(9,size//5)),fill='#FFF4DA',stroke_width=1,stroke_fill='#24201C',anchor='mt')
  d.text((x,260),i[:13],font=font(10),fill='#ECE3D3')
 save(tiny,OUT/'small_size_review.png')
 manifest={'cards':rows,'counts':dict(Counter(x['primary_class'] for x in rows)),'badges':dict(Counter(x['mechanism_badge'] or 'none' for x in rows)),'badge_bbox_64':[43,44,61,62],'badge_inside_fraction':overlap,'piles':{'combinations':12,'tiers':3,'ordered_bottom_layers':['RR','HR','RH','HH'],'runtime_connected':False},'validation':{'all_subjects_inside_inner_mask':True,'all_family_layouts_identical':True,'runtime_modified':False}}
 dump(OUT/'manifest.json',manifest)
 dump(OUT/'badges/sources.json',{k:{'source':v.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(v.read_bytes()).hexdigest(),'operations':['trim transparent margin','uniform scale','center on opaque badge plate'],'redrawn':False} for k,v in BADGE_ART.items()})
 build_html(rows)
 build_music_review(cards)
 print(json.dumps({'cards':len(rows),'classes':manifest['counts'],'badges':manifest['badges'],'badge_inside':overlap,'piles':36}))

def build_inventory(only_cards=None):
 # Local re-export from the original artwork; album/ground masters stay as approved.
 manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
 plates={kind:simple_plate(kind) for kind in KINDS}
 cache={};count=0
 for row in manifest['cards']:
  ident=row['id']
  if only_cards and ident not in only_cards:continue
  source=ROOT/row['source'];kind=row['primary_class'];b=row['mechanism_badge']
  assert hashlib.sha256(source.read_bytes()).hexdigest()==row['source_sha256'],ident
  reserve=row['layout']['reserve_badge'];key=(str(source),kind,reserve)
  plate,inner=plates[kind]
  if key not in cache:
   safe=inner.resize((S,S),Image.Resampling.NEAREST).filter(ImageFilter.MinFilter(17))
   cache[key]=fitted_subject(source,safe,reserve,INVENTORY_RESERVE)
  art,fit=cache[key];icon=plate.copy();icon.alpha_composite(art.resize((256,256),RES))
  if b:icon.alpha_composite(badge(b,72),INVENTORY_BADGE_POS)
  for size in (128,64,32):save(icon.resize((size,size),RES),OUT/f'inventory_{size}/{ident}.png')
  row['inventory_layout']=fit;count+=1
 manifest['inventory_export']={'logical_frame_bounds':[2,1,62,63],'badge_position':[45,45],'runtime_pixels':128}
 dump(OUT/'manifest.json',manifest)
 build_html(manifest['cards'])
 print('Re-exported inventory cards:',count)

def build_music_review(cards):
 spec=SUBJECTS/'v6_music_labels/base_notes.json'
 if not spec.exists():return
 groups=json.loads(spec.read_text(encoding='utf8'))['groups']
 parts=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>乐器基础音主图</title><style>body{background:#dedad2;color:#292727;font:16px/1.6 system-ui;margin:24px}.grid{display:flex;flex-wrap:wrap;gap:12px}article{text-align:center;background:#f6f2e9;padding:12px;border-radius:8px}img{width:220px}a{color:#34567b}</style><h1>乐器基础音 · 主图符号</h1><p>仅更新主图符号；游戏内音高与定义尚未调整。<a href="index.html">全部卡牌</a></p>']
 samples=[]
 for group in groups:
  parts.append('<h2>'+html.escape(group['name'])+'</h2><div class="grid">')
  for note in group['notes']:
   ident=note['id'];label=html.escape(note['label'])
   parts.append(f'<article><a href="album/{ident}.png"><img src="album/{ident}.png"></a><div>{label}</div></article>')
   samples.append((group['name'].split(' · ')[0]+' '+note['label'],cards[ident]))
  parts.append('</div>')
 parts.append('</html>')
 (OUT/'music_base_review.html').write_text(''.join(parts),encoding='utf8')
 sheet(samples,'music_base_review.png',4,(260,300))

def build_html(rows):
 data=json.dumps(rows,ensure_ascii=False).replace('<','\\u003c')
 page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>法术卡组合预览</title><style>
 body{margin:24px;background:#DEDAD2;color:#292727;font:15px/1.6 system-ui}header,nav{margin-bottom:18px}nav{position:sticky;top:0;background:#eee9df;padding:12px;z-index:2}select,input,button{padding:8px;margin-right:8px}a{color:#34567b}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(245px,1fr));gap:16px}.card{background:#f6f2e9;border-radius:10px;padding:12px}.picture{height:260px;display:flex;justify-content:center;align-items:center;background:var(--bg,#c4bcb0)}.picture img{width:var(--sz,256px);height:var(--sz,256px);object-fit:contain}.meta{color:#685e53;font-size:12px}.board{max-width:100%;display:block;margin:12px auto}.ground{width:96px;vertical-align:middle}h2{margin:8px 0;font-size:17px}
 </style><header><h1>法术卡 · 边框、主图与载荷角标</h1><p>182 张单卡；右下角轻压边框；原生数量仅在检查图中示意。卡堆按真实轮廓叠高，主图和角标一同透视。</p><a href="cards_review.png">组合检查图</a> · <a href="small_size_review.png">64/32px 与数量检查</a> · <a href="badges_review.png">三种角标</a> · <a href="manifest.json">制作清单</a> · <a href="#piles">卡堆组合</a></header>
 <nav><input id="q" placeholder="卡名 / id"><select id="kind"><option value="">全部主类</option><option value="basic">基础法术</option><option value="modifier">法术修饰</option><option value="control">施法控制</option></select><select id="badge"><option value="">全部角标</option><option value="hit">碰撞载荷</option><option value="timer">定时载荷</option><option value="break">被击破载荷</option><option value="none">无角标</option></select><select id="size"><option value="256">大图</option><option value="64">64px</option><option value="32">32px</option></select><button id="bg">切换深浅底</button><span id="count"></span></nav><main class="grid" id="grid"></main>
 <section id="piles"><h1>十二种卡堆组合</h1><p>字母顺序从顶到地面：R 基础矩形，H 修饰六角，N 控制凹口。底层控制卡按 R 轮廓处理。此处展示顶牌加两张底牌，未按类别挑选或重排真实卡堆。</p><img class="board" src="pile_matrix.png"><div class="grid" id="pilegrid"></div></section>
 <script>const rows=DATA;const names={basic:'基础法术',modifier:'法术修饰',control:'施法控制'},bn={hit:'碰撞载荷',timer:'定时载荷',break:'被击破载荷'};const q=document.querySelector('#q'),k=document.querySelector('#kind'),b=document.querySelector('#badge'),s=document.querySelector('#size');function render(){let items=rows.filter(x=>(!k.value||x.primary_class===k.value)&&(!b.value||(x.mechanism_badge||'none')===b.value)&&(!q.value||(x.name+x.id).toLowerCase().includes(q.value.toLowerCase())));document.querySelector('#count').textContent=items.length+' / 182';document.querySelector('#grid').innerHTML=items.map(x=>`<article class="card"><a class="picture" href="${x.album}"><img loading="lazy" src="${s.value==='256'?x.album:'inventory_'+s.value+'/'+x.id+'.png'}"></a><h2>${x.name}</h2><div class="meta">${x.id} · ${names[x.primary_class]}${x.mechanism_badge?' · '+bn[x.mechanism_badge]:''}</div><a href="${x.ground}"><img class="ground" loading="lazy" src="${x.ground}">地面单卡</a> · <a href="${x.album}">高清 PNG</a></article>`).join('')}[q,k,b].forEach(x=>x.addEventListener('input',render));s.addEventListener('change',()=>{document.documentElement.style.setProperty('--sz',s.value+'px');render()});let dark=false;document.querySelector('#bg').onclick=()=>{dark=!dark;document.documentElement.style.setProperty('--bg',dark?'#302c28':'#c4bcb0')};document.querySelector('#pilegrid').innerHTML=['RR','HR','RH','HH'].flatMap(base=>['R','H','N'].map(top=>top+base)).map(seq=>`<article class="card"><h2>${seq} · 三档厚度</h2>${['thin','medium','thick'].map(t=>`<a href="piles/${seq}_${t}.png"><img width="31%" loading="lazy" src="piles/${seq}_${t}.png"></a>`).join('')}</article>`).join('');render();</script></html>'''
 (OUT/'index.html').write_text(page.replace('182',str(len(rows))).replace('DATA',data),encoding='utf8')

if __name__=='__main__':
 parser=argparse.ArgumentParser();group=parser.add_mutually_exclusive_group();group.add_argument('--only-badges',action='store_true');group.add_argument('--cards',nargs='+');group.add_argument('--inventory-only',action='store_true')
 args=parser.parse_args()
 if args.inventory_only:build_inventory()
 else:main(args.only_badges,args.cards)
