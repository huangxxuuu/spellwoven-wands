"""Build real-size spell sprites and animation clips; artwork is independent of card icons."""
import math
from xml.etree import ElementTree as E
from PIL import Image,ImageOps,ImageDraw
from build_art_assets import ROOT,ORIGINALS,frame,compile_bank
from pathlib import Path
src=ROOT/'assets_src/spell_revision'
bank='nw_spell_world'
build=E.Element('Build',name=bank); animations=E.Element('Anims'); images={}
def symbol(key,im):
    images[key]=im
    frame(build,key,key,im.size)
def tile(key,w,h,source=None):
    im=Image.open(source or src/(key+'.png')).convert('RGBA')
    return ImageOps.contain(im.crop(im.getchannel('A').point(lambda a:255 if a>14 else 0).getbbox()),(w,h),Image.Resampling.LANCZOS)
def clip(name,poses,fps=24):
    a=E.SubElement(animations,'anim',name=name,root=bank,framerate=str(fps))
    for pose in poses:
        f=E.SubElement(a,'frame',x='0',y='-100',w='1024',h='1024')
        corners=[]
        for layer,(key,x,y,theta,sx,sy) in enumerate(pose):
            c,s=math.cos(theta),math.sin(theta)
            w,h=images[key].size
            for px in (-w/2,w/2):
                for py in (-h/2,h/2):
                    corners.append((x+c*sx*px-s*sy*py,y+s*sx*px+c*sy*py))
            E.SubElement(f,'element',name=key,frame='0',layername=key,z_index=str(layer),m_a=str(c*sx),m_b=str(s*sx),m_c=str(-s*sy),m_d=str(c*sy),m_tx=str(x),m_ty=str(y))
        xs,ys=zip(*corners)
        f.attrib.update(x=str((min(xs)+max(xs))/2),y=str((min(ys)+max(ys))/2),
                        w=str(max(xs)-min(xs)+2),h=str(max(ys)-min(ys)+2))
for name in ['gust','slime','heal_bolt','heavy','land_hook','spore_ball','flint_lance','grow_orb','star_vortex','glass_disc','tri_electric','end_beam','soundwave','bee_swarm']:
    # Heavy Energy Orb uses the same cracked-shell artwork as its spell card.
    source=ORIGINALS/'heavy.png' if name=='heavy' else None
    symbol('body_'+name,tile(name,118,84,source))
# Frost's ice tip points northeast in the source, like the arrow, not the flame.
for name,srcname,angle in [('arrow','arrow',45),('fire','fire',-135),('frost','frost',45),('scatter','pellet',0)]:
    im=tile(name,116,92,ORIGINALS/(srcname+'.png')).rotate(-angle,Image.Resampling.BICUBIC,expand=True)
    symbol('body_'+name,im.crop(im.getbbox()))
symbol('body',images['body_gust'])
for n in range(32):
    clip('dir_'+str(n),[[('body',0,0,n*math.tau/32,1,1)]])
    # Keep the hoe's head above its handle in both horizontal directions.
    # Left-facing artwork is already correct; reflect across the flight axis
    # on the right instead of turning the whole cutout upside down.
    a=n*math.tau/32
    clip('hoe_dir_'+str(n),[[('body',0,0,a,1,-1 if math.cos(a)>0 else 1)]])
symbol('hook_line',images['body_gust'])
for n in range(32):
    a=n*math.tau/32
    clip('hook_dir_'+str(n),[[('body',0,0,a,1,1),('hook_line',0,0,a+math.pi,1,1)]])
# Axe grip is the pivot. Fit the farthest painted point to the gameplay reach.
axe=tile('axe',190,190,ORIGINALS/'axe.png').rotate(-28,Image.Resampling.BICUBIC,expand=True)
axe=axe.crop(axe.getbbox())
symbol('axe_whirl',axe)
w,h=axe.size
px,py=w*.08,h*.58
radius=max(math.hypot(x-px,y-py) for x in (0,w) for y in (0,h))
scale=1.15*150/radius
poses=[]
for i in range(13):
    a=-math.pi+i*math.tau/12
    ox,oy=(w/2-px)*scale,(h/2-py)*scale
    poses.append([('axe_whirl',math.cos(a)*ox-math.sin(a)*oy,math.sin(a)*ox+math.cos(a)*oy,a,scale,scale)])
clip('axe_whirl',poses,fps=31)
symbol('body_orange_bolt',tile('orange_bolt',150,100))
for name in ('fishingrod','farm_hoe'):
    im=tile(name,140,140,ORIGINALS/('edge_'+name+'.png'))
    if name=='farm_hoe':
        im=im.rotate(-45,Image.Resampling.BICUBIC,expand=True)
        im=ImageOps.flip(im.crop(im.getbbox()))
    symbol('body_'+name,im)
# Native inventory cutouts stay readable without an invisible rider animation.
lance=tile('yoth_lance',190,190,ORIGINALS/'edge_yoth_lance.png').rotate(-45,Image.Resampling.BICUBIC,expand=True)
symbol('body_yoth_lance',lance.crop(lance.getbbox()))
for name,w,h in [('shieldofterror',140,140),('lighter',85,100)]:
    im=tile(name,w,h,ORIGINALS/('edge_'+name+'.png'))
    if name=='shieldofterror':
        im=im.rotate(180) # The pair of mouth fangs belongs on the upper side.
    symbol('body_'+name,im)
    # "_upright" is a reserved Klei facing suffix and is stripped on compile.
    clip(name+'_standing',[[('body_'+name,0,0,0,1,1)]])
clip('lighter_spin',[[('body_lighter',0,0,i*math.tau/16,1,1)] for i in range(16)],fps=32)
# Spin around the midpoint between the curved blade and the lower grip,
# offset from the cutout's rectangular center. 12 frames at 30 fps = 2.5 turns/s.
symbol('scythe',tile('scythe',128,128,ORIGINALS/'edge_voidcloth_scythe.png'))
sw,sh=images['scythe'].size
ox,oy=.07*sw,-.08*sh
poses=[]
for i in range(12):
    a=i*math.tau/12
    poses.append([('scythe',math.cos(a)*ox-math.sin(a)*oy,math.sin(a)*ox+math.cos(a)*oy,a,1,1)])
clip('scythe_spin',poses,fps=30)
for name,size in [('crystal_mine',(160,91)),('sleep_crystal',(116,140)),('payload_egg',(90,114)),('rain_cloud',(350,155)),('shield',(54,54))]:
    symbol(name,tile(name,*size))
for j in range(3):
    im=Image.new('RGBA',(48,24));ImageDraw.Draw(im).arc((2,3,45,44),216,324,fill=(246,119+j*28,60,245),width=3)
    symbol('signal'+str(j),im)
drop=Image.new('RGBA',(6,25));ImageDraw.Draw(drop).line((4,1,1,20),fill=(145,203,233,178),width=3);symbol('drop',drop)
for name in ['crystal_mine','sleep_crystal','payload_egg','rain_cloud','shield_2','shield_1']:
    poses=[]
    for i in range(36):
        t=i/36;ph=t*math.tau
        if name.startswith('shield'):
            pose=[]
            for j in range(int(name[-1])):
                angle=ph+math.pi*j
                pose.append(('shield',90*math.cos(angle),-105+26*math.sin(angle),.08*math.sin(angle),.8+.15*math.sin(angle),1))
        elif name=='rain_cloud':
            pose=[(name,0,-230,0,1,1)]
            for j in range(14):
                u=(t*2+j*.371)%1
                pose.append(('drop',((j*79)%302)-151-u*13,-180+u*175,0,.7,1))
        else:
            sy=1+.026*math.sin(ph) if name=='payload_egg' else 1
            pose=[(name,0,-images[name].height*sy/2,0,1,sy)]
            if name=='crystal_mine':
                for j in range(int(t*4)%4):pose.append(('signal'+str(j),0,-100-j*8,0,.45+j*.23,.5+j*.2))
        poses.append(pose)
    clip(name,poses)
compile_bank(bank,build,animations,images,Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools"))
