"""Render the real Lua frame rectangles from compiled KTEX atlas pixels."""
from pathlib import Path
import struct
import zipfile
from xml.etree import ElementTree as ET
from PIL import Image, ImageDraw
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
def decode(data):
    assert data[:4]==b'KTEX'
    offset=8;levels=[]
    mipmaps=(struct.unpack_from('<I',data,4)[0]>>13)&31
    assert 1<=mipmaps<=16
    for _ in range(mipmaps):
        w,h,pitch,size=struct.unpack_from('<HHHI',data,offset)
        levels.append((w,h,size));offset+=10
    assert offset+sum(n for _,_,n in levels)==len(data)
    w,h,size=levels[0]
    return Image.frombytes('RGBA',(w,h),data[offset:offset+size],'bcn',3).transpose(Image.Transpose.FLIP_TOP_BOTTOM)

def atlas(xml,texture):
    im=decode(texture);regions={}
    for e in ET.fromstring(xml).find('Elements'):
        x1,x2=[round(float(e.get(k))*im.width) for k in ('u1','u2')]
        y1,y2=[round((1-float(e.get(k)))*im.height) for k in ('v2','v1')]
        tile=im.crop((x1,y1,x2,y2))
        # KTEX is premultiplied; Pillow's alpha_composite expects straight alpha.
        tile.putdata([(min(255,r*255//a),min(255,g*255//a),min(255,b*255//a),a)
            if a else (0,0,0,0) for r,g,b,a in tile.getdata()])
        regions[e.get('name')]=tile
    return regions

def mod_atlas(name):
    p=ROOT/'mod/images'
    return atlas((p/(name+'.xml')).read_bytes(),(p/(name+'.tex')).read_bytes())
wood=mod_atlas('nw_frame');icons=mod_atlas('nw_hud')
with zipfile.ZipFile("E:/SteamLibrary/steamapps/common/Don't Starve Together/data/databundles/images.zip") as z:
    slots=atlas(z.read('images/hud.xml'),z.read('images/hud.tex'))

vm=LuaRuntime(unpack_returned_tuples=True)
vm.globals().package.path=str(ROOT/'mod/scripts/?.lua').replace('\\','/')+';'+vm.globals().package.path
vm.execute('''
Class=function(base,ctor)
    local c={_ctor=ctor};c.__index=c
    return setmetatable(c,{__index=base,__call=function(cls,...)
        local s=setmetatable({},cls);ctor(s,...);return s end})
end
local W=Class(nil,function(self) self.children={} end)
function W:AddChild(c) self.children[#self.children+1]=c;return c end
function W:SetSize(w,h) self.w=w;self.h=h end
function W:SetPosition(x,y) self.x=x;self.y=y end
package.loaded['widgets/widget']=W
package.loaded['widgets/image']=Class(W,function(self,a,t) W._ctor(self);self.texture=t end)
''')
Frame=vm.eval('require("widgets/nw_wandframe")')
for count in range(2,13):
    width=count*76+40;height=142
    frame=Frame();frame.SetSize(frame,width,height)
    canvas=Image.new('RGBA',(width,height))
    coverage=Image.new('L',(width,height));mark=ImageDraw.Draw(coverage)
    for _,p in frame.pieces.items():
        x=round(width/2+p.x-p.w/2);y=round(height/2-p.y-p.h/2)
        w,h=round(p.w),round(p.h)
        assert x>=0 and y>=0 and x+w<=width and y+h<=height
        mark.rectangle((x,y,x+w-1,y+h-1),fill=255)
        canvas.alpha_composite(wood[p.texture].resize((w,h),Image.Resampling.BILINEAR),(x,y))
    assert coverage.getextrema()==(255,255),'gap in frame coverage'
    for x in (2,5,width-6,width-3):
        for y in range(18,height-18):
            r,g,b,a=canvas.getpixel((x,y))
            assert not (r>210 and g>210 and b>210 and a>180),'white side stripe'
    if count in (2,7,12):
        origin=height/2+16
        for i in range(count):
            x=round(width/2+(i-(count-1)/2)*76-37)
            canvas.alpha_composite(slots['inv_slot.tex'].resize((74,74)),(x,round(origin-37)))
        def paste(name,w,h,x,y):
            canvas.alpha_composite(icons[name].resize((w,h),Image.Resampling.LANCZOS),
                (round(width/2+x-w/2),round(origin-y-h/2)))
        paste('readonly.tex',26,26,-66,56)
        paste('ring_60.tex',28,28,66,56);paste('cast.tex',18,18,66,56)
        d=ImageDraw.Draw(canvas);cx,cy=width/2,origin-56
        for w,h,col in ((92,18,'#090605'),(88,14,'#8f6633'),(85,11,'#090f1f'),(83,9,'#197ad9')):
            d.rectangle((cx-w/2,cy-h/2,cx+w/2-1,cy+h/2-1),fill=col)
        globals()['preview_'+str(count)]=canvas

board=Image.new('RGBA',(1024,570),'#787468')
d=ImageDraw.Draw(board)
d.text((24,12),'COMPILED TEXTURES + ACTUAL LUA FRAME LAYOUT (not an in-game screenshot)',fill='white')
for i,count in enumerate((2,7,12)):
    im=globals()['preview_'+str(count)]
    d.text((24,47+i*174),str(count)+' slots',fill='white')
    board.alpha_composite(im,((board.width-im.width)//2,67+i*174))
out=ROOT/'assets_src/hud/frame_runtime_preview.png';board.convert('RGB').save(out)
print('PASS compiled wooden frame: 2-12 capacities, full coverage, no white sides;',out)
