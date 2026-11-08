"""Preview the real guide constructor with compiled textures and substitute fonts, without launching DST."""
from functools import lru_cache
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile
from PIL import Image, ImageDraw, ImageFont
from lupa.lua51 import LuaRuntime
from native_animation import GAME, texture

ROOT = Path(__file__).resolve().parents[1]

BACKEND = '''
UIFONT="ui";MOVE_LEFT=1;MOVE_RIGHT=2;MOVE_UP=3;MOVE_DOWN=4
Class=function(base,ctor)
    local c={_ctor=ctor};c.__index=c
    return setmetatable(c,{__index=base,__call=function(cls,...)
        local self=setmetatable({},cls);ctor(self,...);return self
    end})
end
local function widget(kind)
    local w={kind=kind,children={},x=0,y=0,tint={1,1,1,1},inst={IsValid=function() return true end}}
    function w:AddChild(child) self.children[#self.children+1]=child;child.parent=self;return child end
    function w:Kill() self.dead=true end
    function w:MoveToBack()
        for i,child in ipairs(self.parent.children) do if child==self then table.remove(self.parent.children,i);break end end
        table.insert(self.parent.children,1,self)
    end
    function w:SetPosition(x,y) self.x=x;self.y=y end
    function w:GetPosition() return {x=self.x,y=self.y} end
    function w:SetScale() end
    function w:SetSize(width,height) if self.kind=="text" then self.fontsize=width else self.w=width;self.h=height end end
    function w:SetRegionSize(width,height) self.w=width;self.h=height end
    function w:SetTint(...) self.tint={...} end
    w.SetColour=w.SetTint
    function w:SetString(value) self.text=value end
    function w:SetClickable() end
    function w:SetHoverText(text,params) self.tip=text;self.tipparams=params end
    function w:EnableWordWrap() end
    function w:SetFocusChangeDir() end
    function w:ForceImageSize(width,height) self.image:SetSize(width,height) end
    function w:SetImageNormalColour(colour) self.image.tint=colour end
    function w:SetImageFocusColour() end
    function w:SetOnClick(fn) self.onclick=fn end
    return w
end
package.loaded["widgets/widget"]={_ctor=function(self)
    for k,v in pairs(widget("widget")) do if self[k]==nil then self[k]=v end end
end}
package.loaded["widgets/image"]=function(atlas,name)
    local w=widget("image");w.atlas=atlas;w.texture=name;return w
end
package.loaded["widgets/imagebutton"]=function(atlas,name)
    local w=widget("button");w.image=w:AddChild(require("widgets/image")(atlas,name));return w
end
package.loaded["widgets/text"]=function(font,size,text)
    local w=widget("text");w.fontsize=size;w.text=text;return w
end
package.loaded["widgets/spinner"]=function(options,width,height,textinfo)
    local w=widget("spinner");w.options=options
    w.text=w:AddChild(require("widgets/text")(textinfo.font,textinfo.size,options[1].text))
    w.leftimage=w:AddChild(require("widgets/image")("images/ui.xml","arrow2_left.tex"))
    w.rightimage=w:AddChild(require("widgets/image")("images/ui.xml","arrow2_right.tex"))
    for _,arrow in ipairs({w.leftimage,w.rightimage}) do arrow:SetSize(height,height) end
    w.leftimage:SetPosition(-width/2+height/2,0);w.rightimage:SetPosition(width/2-height/2,0)
    function w:SetSelectedIndex(index) self.index=index;self.text:SetString(self.options[index].text) end
    function w:SetTextColour(...) self.text:SetColour(...) end
    function w:SetWrapEnabled() end
    function w:SetOnChangedFn(fn) self.onchanged=fn end
    function w:SetSelected(value)
        for i,option in ipairs(self.options) do if option.data==value then self:SetSelectedIndex(i);self.onchanged(value);return end end
    end
    return w
end
package.loaded["screens/popupdialog"]=function(title,_,buttons)
    local w=widget("screen");w.proot=w:AddChild(widget("root"))
    w.bg=w.proot:AddChild(require("widgets/image")("images/fepanels.xml","wideframe.tex"))
    w.title=w.proot:AddChild(require("widgets/text")(UIFONT,32,title))
    w.menu=w.proot:AddChild(widget("menu"))
    for i,button in ipairs(buttons) do
        local item=w.menu:AddChild(require("widgets/imagebutton")("images/frontend.xml","button_long.tex"))
        item:ForceImageSize(170,52);item:SetPosition((i-1)*200,0)
        item:AddChild(require("widgets/text")(UIFONT,22,button.text));item:SetOnClick(button.cb)
    end
    return w
end
local stored
TheSim={GetPersistentString=function(_,_,cb) cb(stored~=nil,stored) end,
    SetPersistentString=function(_,_,value,_,cb) stored=value;cb() end}
local active
TheFrontEnd={PushScreen=function(_,screen) active=screen end,PopScreen=function() active=nil end}
VisitURL=function() end
'''


@lru_cache(None)
def sprite(atlas, name):
    path = ROOT / 'mod' / atlas
    if path.is_file():
        xml, data = path.read_bytes(), path.with_suffix('.tex').read_bytes()
    else:
        with ZipFile(GAME / 'data/databundles/images.zip') as archive:
            xml = archive.read(atlas)
            texpath = atlas.replace('.xml', '.tex')
            data = archive.read(texpath) if texpath in archive.namelist() else (GAME/'data'/texpath).read_bytes()
    sheet = texture(data)
    element = next(e for e in ET.fromstring(xml).find('Elements') if e.get('name') == name)
    x1, x2 = (round(float(element.get(k)) * sheet.width) for k in ('u1', 'u2'))
    y1, y2 = (round((1 - float(element.get(k))) * sheet.height) for k in ('v2', 'v1'))
    tile = sheet.crop((x1, y1, x2, y2))
    return Image.frombytes('RGBa', tile.size, tile.tobytes()).convert('RGBA')


def colour(tint):
    return tuple(round(tint[i] * 255) for i in range(1, 5))


def render(screen, language, hover=False):
    canvas = Image.new('RGBA', (960,720), '#242a27')
    draw = ImageDraw.Draw(canvas)
    draw.text((16,12), 'LUA LAYOUT + GAME TEXTURES / SUBSTITUTE FONT / NOT AN IN-GAME SCREENSHOT', fill='#bfc7bb')
    fontpath = 'C:/Windows/Fonts/msyh.ttc' if language == 'zh' else 'C:/Windows/Fonts/arial.ttf'
    def visit(node, x=480, y=360):
        if node.dead:
            return
        x += node.x or 0
        y -= node.y or 0
        if node.kind == 'image':
            w,h = round(node.w), round(node.h)
            if node.texture == 'square.tex':
                tile = Image.new('RGBA', (w,h), colour(node.tint))
            else:
                tile = sprite(node.atlas,node.texture).resize((w,h), Image.Resampling.LANCZOS)
            canvas.alpha_composite(tile,(round(x-w/2),round(y-h/2)))
        elif node.kind == 'text':
            font = ImageFont.truetype(fontpath, round(node.fontsize))
            lines = []
            for paragraph in (node.text or '').split('\n'):
                line=''
                parts=list(paragraph) if language=='zh' else paragraph.split(' ')
                for part in parts:
                    join='' if language=='zh' or not line else ' '
                    candidate=line+join+part
                    if node.w and line and draw.textlength(candidate,font=font)>node.w:
                        lines.append(line);line=part
                    else:
                        line=candidate
                lines.append(line)
            height=len(lines)*node.fontsize*1.2
            assert not node.h or height<=node.h+1, f'{language} text overflow: {node.text!r}: {height} > {node.h}'
            for i,line in enumerate(lines):
                draw.text((x,y-height/2+i*node.fontsize*1.2),line,font=font,fill=colour(node.tint),anchor='mt')
        for _,child in node.children.items():
            visit(child,x,y)
    visit(screen)
    if hover:
        direction=screen.direction
        p=direction.tipparams
        tile=sprite('images/frontend.xml','scribble_black.tex').resize((round(p.region_w*1.5),round(p.region_h*2)))
        canvas.alpha_composite(tile,(round(480-tile.width/2),round(370-tile.height/2)))
        text={'kind':'text','fontsize':p.font_size,'text':direction.tip,'w':p.region_w,'h':p.region_h,
              'tint':{1:1,2:1,3:1,4:1},'children':{},'x':0,'y':-10}
        # Reuse the same text layout/overflow check as ordinary Lua labels.
        visit(vm_table(text))
    return canvas.convert('RGB')


def vm_table(value):
    """Tiny attribute view for a preview-only tooltip, matching Lupa tables."""
    class Record(dict):
        def __getattr__(self,key): return self.get(key)
    return Record(value)


def main():
    vm=LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path=(ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
    vm.execute(BACKEND)
    locale=vm.eval('require("nw/locale")')
    guide=vm.eval('require("nw/quickguide")')
    direction=vm.eval('require("nw/cast_direction")')
    output=ROOT/'test_reports'
    output.mkdir(exist_ok=True)
    for language in ('zh','en'):
        locale.configure(language,language)
        screen=guide.open()
        assert sum(child.kind=='spinner' for _,child in screen.proot.children.items())==1
        screen.direction.SetSelected(screen.direction,'target');assert direction.get()=='target'
        render(screen,language).save(output/f'quickguide_{language}_target.png')
        screen.direction.SetSelected(screen.direction,'mouse');assert direction.get()=='mouse'
        render(screen,language).save(output/f'quickguide_{language}_mouse.png')
        render(screen,language,hover=True).save(output/f'quickguide_{language}_mouse_hover.png')
        reopened=guide.open();assert direction.get()=='mouse'
        assert reopened.direction.index==2 and reopened.direction.tip==screen.direction.tip
    print(f'PASS guide constructor, choice callbacks, reopen, and bilingual text fit; previews: {output}')


if __name__=='__main__':
    main()
