"""Native DST Hoverer regression for the dedicated cast hint.

Widget/text metrics, screen/input services and action selection are shells.
The installed game's complete Hoverer constructor/OnUpdate/UpdatePosition and
production cast_hover/cast_key/world_input run unchanged. Approximate text
bounds test layout math; glyph rendering and live HUD scale need visual QA.
"""
import os
from pathlib import Path
import re
import unittest
from zipfile import ZipFile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOD = Path(os.environ.get("NW_CAST_TEST_MOD_ROOT", ROOT / "mod"))
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class NativeCastHoverTest(unittest.TestCase):
    def runtime(self):
        archive_path = GAME / "data/databundles/scripts.zip"
        if not archive_path.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = (MOD / "scripts/?.lua").as_posix() + ";" + lua.globals().package.path
        with ZipFile(archive_path) as archive:
            hover_source = archive.read("scripts/widgets/hoverer.lua").decode()
            strings = archive.read("scripts/strings.lua").decode()
            constants = archive.read("scripts/constants.lua").decode()
        for name in ("CONTROL_PRIMARY", "CONTROL_SECONDARY", "CONTROL_CUSTOM_START"):
            value = re.search(r"^" + name + r"\s*=\s*(\d+)", constants, re.M)
            self.assertIsNotNone(value, f"native constant {name} missing")
            lua.globals()[name] = int(value.group(1))
        lua.execute(r'''
UIFONT="native_ui_font";DIALOGFONT="native_dialog_font"
NORMAL_TEXT_COLOUR={1,1,1,1};WET_TEXT_COLOUR={.5,.5,1,1}
math.clamp=function(v,lo,hi) return math.max(lo,math.min(hi,v)) end
Vector3=function(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
Class=function(base,ctor)
    local cls={_base=base,_ctor=ctor};cls.__index=cls
    setmetatable(cls,{__index=base,__call=function(_,...) local self=setmetatable({},cls);ctor(self,...);return self end})
    return cls
end
local Widget={}
Widget.__index=Widget
function Widget._ctor(self,name)
    self.name=name;self.shown=true;self.children={};self.pos=Vector3();self.scale=Vector3(1,1,1)
end
function Widget:AddChild(child) self.children[#self.children+1]=child;return child end
function Widget:SetPosition(x,y,z) self.pos=type(x)=="table" and Vector3(x.x,x.y,x.z) or Vector3(x,y,z) end
function Widget:GetPosition() return self.pos end
function Widget:SetScale(x,y,z) self.scale=type(x)=="table" and x or Vector3(x,y or x,z or x) end
function Widget:GetScale() return self.scale end
function Widget:Show() self.shown=true end
function Widget:Hide() self.shown=false end
function Widget:IsVisible() return self.shown end
function Widget:SetClickable() end
function Widget:StartUpdating() end
function Widget:SetSize(w,h) self.width=w;self.height=h end
local Text=Class(Widget,function(self,font,size,text)
    Widget._ctor(self,"text");self.font=font;self.size=size;self.string=text or ""
end)
function Text:SetString(text) self.string=text or "" end
function Text:GetString() return self.string end
function Text:SetSize(size) self.size=size end
function Text:SetColour() end
function Text:GetRegionSize()
    local width,lines=0,0
    for line in (self.string.."\n"):gmatch("(.-)\n") do
        local line_width=0
        for glyph in line:gmatch("[\1-\127\194-\244][\128-\191]*") do
            local ratio=#glyph>1 and 1 or (glyph=="I" or glyph=="i" or glyph=="l") and .22
                or (glyph=="W" or glyph=="M") and .95 or .55
            line_width=line_width+self.size*ratio
        end
        width=math.max(width,line_width);lines=lines+1
    end
    return width,self.size*1.1*lines
end
local Image=Class(Widget,function(self,atlas,texture) Widget._ctor(self,"image");self.atlas=atlas;self.texture=texture end)
function Image:SetTexture(atlas,texture) self.atlas=atlas;self.texture=texture end
package.loaded["constants"]={};package.loaded["widgets/widget"]=Widget;package.loaded["widgets/text"]=Text;package.loaded["widgets/image"]=Image
package.loaded["nw/locale"]={language="en"}
STRINGS={UI={CONTROLSSCREEN={INPUTS={{}}},HUD={CANCEL="Cancel"}}}
''')
        input_strings = strings[strings.index("INPUTS", strings.index("CONTROLSSCREEN")):]
        for code in (107, 1000, 1001, 1002, 1005, 1006):
            match = re.search(r"\[" + str(code) + r'\]\s*=\s*("[^"\n]*")', input_strings)
            self.assertIsNotNone(match, f"native input string {code} missing")
            lua.execute(f"STRINGS.UI.CONTROLSSCREEN.INPUTS[1][{code}]={match.group(1)}")
        lua.execute(r'''
local names=STRINGS.UI.CONTROLSSCREEN.INPUTS[1]
binding="mouse:1002";synced=true;equipped=true;using_mouse=true;actions_visible=true
secondary=1001;can_cast=true;mode_ready=true;native_kind="blink";tooltip=nil;mouse={x=960,y=540}
reads=0
ACTIONS={NW_CAST={},BLINK={},INSPECT={},CASTAOE={}}
local wand={components={nw_wand={}},IsValid=function() return true end}
local inv={GetEquippedItem=function() return equipped and wand or nil end,GetActiveItem=function() end}
EQUIPSLOTS={HANDS="hands"}
IsPaused=function() return false end
TheWorld={ismastersim=true}
TheSim={GetScreenSize=function() return 1920,1080 end}
TheInputProxy={GetLocalizedControl=function(_,device,control,localized,raw)
    assert(device==0 and localized==false and raw==true)
    assert(type(control)=="number" and control>=0 and control<CONTROL_CUSTOM_START and control==math.floor(control),
        "native mapping API requires a real control ID")
    return 1,1,control==CONTROL_SECONDARY and secondary or 1000
end}
TheInput={GetControllerID=function() return 0 end,
    ResolveVirtualControls=function(_,control) return control end,
    GetLocalizedControl=function(_,_,control) return names[control==CONTROL_SECONDARY and secondary or 1000] end,
    GetScreenPosition=function() return mouse end,
    GetHUDEntityUnderMouse=function() end,
    AddMoveHandler=function(_,fn) move=fn;return {} end,
    OnControl=function() error("hover changed input") end,
    OnRawKey=function() error("hover dispatched a key") end,
    OnMouseButton=function() error("hover dispatched a mouse button") end}
package.loaded["nw/cast_binding"]={ready=function() return synced end,get=function() return binding end,
    set=function() error("hover wrote binding") end}
local function act(action,name)
    return {action=action,doer=p,GetActionString=function() reads=reads+1;return name end,
        Do=function() error("hover performed action") end}
end
local pc={handler={},UsingMouse=function() return using_mouse end,
    IsEnabled=function() return true end,IsAOETargeting=function() return false end,
    GetHoverTextOverride=function() end,
    GetLeftMouseAction=function() return act(ACTIONS.INSPECT,"Inspect") end,
    GetRightMouseAction=function()
        return act(native_kind=="cast" and ACTIONS.NW_CAST or ACTIONS.BLINK,native_kind=="cast" and "Cast" or "Soul Hop")
    end,
    DoAction=function() error("hover executed controller action") end}
p={components={playercontroller=pc},replica={inventory=inv},HUD={controls={
    GetTooltip=function() return tooltip end,GetTooltipPos=function() end,GetTooltipColour=function() return NORMAL_TEXT_COLOUR end}},
    IsActionsVisible=function() return actions_visible end,HasTag=function() return false end}
pc.inst=p;ThePlayer=p;active=p.HUD
TheFrontEnd={GetActiveScreen=function() return active end}
local Cast=require("nw/cast_action")
Cast.input_action=function(player,native)
    assert(player==p,"hint read a different player's actions")
    if native then return act(ACTIONS.BLINK,"Soul Hop") end
    if can_cast and mode_ready then return act(ACTIONS.NW_CAST,"Cast") end
    return act(ACTIONS.BLINK,"Soul Hop")
end
''')
        lua.globals().NativeHoverer = lua.execute(hover_source)
        lua.execute(r'''
h=NativeHoverer(p)
original_right=p.components.playercontroller.GetRightMouseAction
require("nw/cast_hover").install(h)
function update()
    for _=1,3 do h:OnUpdate() end
    h:UpdatePosition(mouse.x,mouse.y)
    assert(p.components.playercontroller.GetRightMouseAction==original_right,"hint must not replace controller action selection")
end
function has(widget,value) return widget.shown and widget:GetString():find(value,1,true)~=nil end
function hint(value)
    update()
    assert(h.nw_cast_text.font==UIFONT and h.nw_cast_text.size==30,"use native hover font and size")
    assert(has(h.nw_cast_text,value),"custom hint lacks expected input label: "..value)
    assert(has(h.nw_cast_text,"Cast"),"custom hint lacks cast action")
end
function hidden() update();assert(not h.nw_cast_text.shown,"custom cast hint should be hidden") end
''')
        return lua

    def test_native_glyphs_and_fallback(self):
        lua = self.runtime()
        lua.execute(r'''
for _,code in ipairs({1002,1005,1006,107}) do
    binding=(code>=1000 and "mouse:" or "key:")..code
    hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][code])
    assert(has(h.secondarytext,"Soul Hop"),"dedicated hint replaced native soul hop")
end
binding="mouse:1007";hint(require("nw/cast_key").label(binding))
assert(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1007]==nil,"fallback case needs no native glyph")
assert(reads>0 and binding=="mouse:1007" and secondary==1001,"hover must only read actions and input")
''')

    def test_secondary_binding_and_no_duplicates(self):
        lua = self.runtime()
        lua.execute(r'''
binding="mouse:1001";native_kind="cast";hidden()
assert(has(h.secondarytext,"Cast"),"matching native cast hint should be retained")
secondary=1002;native_kind="blink";hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1001])
assert(has(h.secondarytext,"Soul Hop") and has(h.secondarytext,STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1002]),
    "remapped game secondary must retain middle-button soul hop")
native_kind="cast";hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1001])
assert(has(h.secondarytext,"Soul Hop") and not has(h.secondarytext,"Cast"),
    "stale native NW_CAST label must not mislabel remapped secondary as casting")
secondary=1001;native_kind="blink";hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1001])
assert(not h.secondarytext.shown,"one physical key must not claim cast and soul hop simultaneously")
can_cast=false;hidden()
assert(has(h.secondarytext,"Soul Hop"),"cooling/empty wand must retain native soul hop")
''')

    def test_world_input_visibility(self):
        lua = self.runtime()
        lua.execute(r'''
hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1002])
can_cast=false;hidden();can_cast=true
equipped=false;hidden();equipped=true
synced=false;hidden();synced=true
mode_ready=false;hidden();mode_ready=true
active={};hidden();active=p.HUD
tooltip="HUD tooltip";hidden();tooltip=nil
p._nw_binding_capture={};hidden();p._nw_binding_capture=nil
p._nw_editing=true;hidden();p._nw_editing=nil
p._nw_hud_dragging={};hidden();p._nw_hud_dragging=nil
actions_visible=false;hidden();actions_visible=true
using_mouse=false;hidden();using_mouse=true
hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1002])
''')

    def test_native_early_return_and_forcehide(self):
        lua = self.runtime()
        lua.execute(r'''
hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1002])
using_mouse=false;h:OnUpdate();assert(not h.nw_cast_text.shown,"native early return left custom hint visible")
using_mouse=true;h:Hide();h.forcehide=true;hidden()
h.forcehide=false;hint(STRINGS.UI.CONTROLSSCREEN.INPUTS[1][1002])
assert(h.shown,"native hoverer must show again")
''')

    def test_keyboard_caps_and_same_native_key(self):
        lua = self.runtime()
        lua.execute(r'''
local C=require("nw/constants/ui").keyhint
for _,item in ipairs({{107,"K"},{286,"F5"},{9,"Tab"},{32,"Space"},{8,"Backspace"}}) do
    binding="key:"..item[1]
    hint(item[2])
    assert(h.nw_cast_text.key_text:GetString()==item[2] and h.nw_cast_text.cap_left.shown)
    assert(h.nw_cast_text.key_text.size==30*C.key_size_ratio,"cap label must keep the specified size")
    assert(h.nw_cast_text.key_text.font==DIALOGFONT,"keycap uses the readable native dialog font")
    assert(h.nw_cast_text.suffix_text:GetString()=="Cast" and h.nw_cast_text.suffix_text.size==30)
end
binding="key:107";secondary=107;native_kind="cast";hint("K")
assert(not h.secondarytext.shown and h.nw_cast_text.cap_left.shown,
    "matching native keyboard cast must use one custom keycap row")
secondary=1001;native_kind="blink"
STRINGS.UI.CONTROLSSCREEN.INPUTS[1][258]="III"
STRINGS.UI.CONTROLSSCREEN.INPUTS[1][259]="WWW"
binding="key:258";hint("III");assert(h.nw_cast_text.variant=="small")
binding="key:259";hint("WWW");assert(h.nw_cast_text.variant=="wide")
binding="key:8";hint("Backspace");assert(h.nw_cast_text.variant=="wide")
require("nw/locale").language="zh";hint("退格")
assert(h.nw_cast_text.variant=="wide" and h.nw_cast_text.key_text.size==30*C.key_size_ratio*C.chinese_key_size_scale,
    "localized label uses the configured Chinese size and measured cap width")
''')

    def test_window_edges_and_hud_scale(self):
        lua = self.runtime()
        lua.execute(r'''
binding="key:8"
local function rect(text)
    local pos,scale,child=h:GetPosition(),h:GetScale(),text:GetPosition()
    local width,height=text:GetRegionSize()
    local x,y=pos.x+child.x*scale.x,pos.y+child.y*scale.y
    return {left=x-width*scale.x/2,right=x+width*scale.x/2,bottom=y-height*scale.y/2,top=y+height*scale.y/2}
end
for _,scale in ipairs({.65,1,1.6}) do
    h:SetScale(scale)
    for _,x in ipairs({0,960,1920}) do for _,y in ipairs({0,540,1080}) do
        mouse={x=x,y=y};update()
        local boxes={}
        for _,text in ipairs({h.text,h.secondarytext,h.nw_cast_text}) do
            assert(text.shown,"layout needs all three native/custom lines")
            local box=rect(text);boxes[#boxes+1]=box
            assert(box.left>=0 and box.right<=1920 and box.bottom>=0 and box.top<=1080,
                "hover line clipped at window edge or HUD scale")
        end
        for a=1,#boxes do for b=a+1,#boxes do
            local one,two=boxes[a],boxes[b]
            assert(one.top<=two.bottom or two.top<=one.bottom or one.right<=two.left or two.right<=one.left,
                "native and custom hover text overlap")
        end end
    end end
end
''')


if __name__ == "__main__":
    unittest.main()
