"""Native Spinner/Button contract and measured localised filter-strip layout."""
import io
import os
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
import zipfile
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class CraftingFiltersWidgetTest(unittest.TestCase):
    def test_native_controls_and_tag_layout(self):
        bundle = GAME / "data/databundles"
        if not (bundle / "scripts.zip").exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        with zipfile.ZipFile(bundle / "fonts.zip") as fonts:
            with zipfile.ZipFile(io.BytesIO(fonts.read("fonts/belisaplumilla50.zip"))) as font:
                root = ET.fromstring(font.read("font.fnt"))
        advance = {int(c.get("id")): float(c.get("xadvance")) for c in root.findall("chars/char")}
        def measure(text, size):
            return sum((advance.get(ord(c), 52) - 2) * size / 50 for c in text)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().measure = measure
        lua.globals().package.path = str(ROOT / "mod/scripts/?.lua").replace("\\", "/") + ";" + lua.globals().package.path
        lua.execute(r"""
Class=function(base,ctor)
    local c={_ctor=ctor,_base=base};c.__index=c
    return setmetatable(c,{__index=base,__call=function(_,...) local o=setmetatable({},c);ctor(o,...);return o end})
end
local vector={__add=function(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end}
Vector3=function(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},vector) end
UIFONT='bp50';HEADERFONT='hammerhead';BUTTONFONT='buttonfont';NEWFONT='spirequal';DEFAULTFONT='opensans'
CONTROL_ACCEPT=1;CONTROL_PREVVALUE=2;CONTROL_NEXTVALUE=3;CONTROL_PRIMARY=4
MOVE_UP=1;MOVE_DOWN=2;MOVE_LEFT=3;MOVE_RIGHT=4;ANCHOR_MIDDLE=0
STRINGS={UI={HELP={SELECT='Select',PREVVALUE='Previous',NEXTVALUE='Next'}}}
ValidateLineNumber=function() end;ClickMouseoverSoundReduction=function() return 1 end
TheInput={GetControllerID=function() return 0 end,ResolveVirtualControls=function(_,c) return c end,
    GetLocalizedControl=function() return 'A' end,ControllerAttached=function() return false end}
TheFrontEnd={GetFadeLevel=function() return 0 end,GetSound=function() return {PlaySound=function() end} end}
local Widget=Class(nil,function(self,name)
    self.name=name;self.children={};self.enabled=true;self.focus=false;self.shown=true
    self.pos=Vector3();self.local_scale=Vector3(1,1,1);self.focus_flow={}
end)
function Widget:AddChild(child) self.children[#self.children+1]=child;child.parent=self;return child end
function Widget:SetPosition(x,y,z) self.pos=type(x)=='table' and x or Vector3(x,y,z) end
function Widget:GetLocalPosition() return self.pos end
function Widget:SetScale(x,y,z) self.local_scale=Vector3(x,y or x,z or 1) end
function Widget:MoveToBack() end
function Widget:SetClickable() end
function Widget:OnControl() return false end
function Widget:OnGainFocus() end
function Widget:OnLoseFocus() end
function Widget:OnEnable() end
function Widget:OnDisable() end
function Widget:IsEnabled() return self.enabled end
function Widget:IsDisabledState() return not self.enabled end
function Widget:IsFocusedState() return self.focus end
function Widget:IsNormalState() return self.enabled and not self.focus and not self.selected end
function Widget:Enable() self.enabled=true;self:OnEnable() end
function Widget:Disable() self.enabled=false;self:OnDisable() end
function Widget:Show() self.shown=true end
function Widget:Hide() self.shown=false end
function Widget:SetFocus() self.focus=true;self:OnGainFocus() end
function Widget:ClearFocus() self.focus=false;self:OnLoseFocus() end
function Widget:SetFocusChangeDir(d,w) self.focus_flow[d]=w end
function Widget:SetHoverText(text) self.hovertext=text end
function Widget:StopUpdating() end
local Text=Class(Widget,function(self,font,size) Widget._ctor(self,'text');self.font=font;self.size=size;self.string='' end)
function Text:SetVAlign() end
function Text:SetFont(f) self.font=f end
function Text:SetSize(s) self.size=s end
function Text:SetColour(...) self.colour={...} end
function Text:SetString(s) self.string=s end
function Text:GetString() return self.string end
function Text:SetTruncatedString(s) self.string=s end
function Text:GetRegionSize() return measure(self.string,self.size),self.size end
local Image=Class(Widget,function(self,a,t) Widget._ctor(self,'image');self:SetTexture(a,t) end)
function Image:SetTexture(a,t) self.atlas=a;self.texture=t;self.w=32;self.h=32 end
function Image:ScaleToSize(w,h) self:SetScale(w/self.w,h/self.h,1) end
function Image:SetSize(w,h) self.w=w;self.h=h end
function Image:GetSize() return self.w,self.h end
function Image:SetTint(...) self.tint={...} end
package.loaded['widgets/widget']=Widget;package.loaded['widgets/text']=Text;package.loaded['widgets/image']=Image
package.loaded['widgets/threeslice']={};package.loaded.fonts={}
""")
        with zipfile.ZipFile(bundle / "scripts.zip") as archive:
            for name in ("button", "textbutton", "imagebutton", "spinner"):
                code = archive.read(f"scripts/widgets/{name}.lua").decode()
                lua.globals().package.loaded[f"widgets/{name}"] = lua.execute(code)
        lua.execute(r"""
local changes=0;local clicked
local options={{text='All Recipes',data='all'},{text='Basic Spells',data='basic'},
    {text='Spell Modifiers',data='modifier'},{text='Cast Controls',data='control'}}
local filters=require('widgets/nw_craftingfilters')(options,function() changes=changes+1 end,function(id) clicked=id end)
filters:SetChoice('basic');assert(changes==0 and filters.spinner:GetSelectedData()=='basic')
filters.spinner:Next(true);assert(changes==1 and filters.spinner:GetSelectedData()=='modifier')
filters:SetChoices({options[1],options[2]});filters:SetChoice('all')
filters.spinner:Next(true);assert(filters.spinner:GetSelectedData()=='basic')
filters.spinner:Next(true);assert(filters.spinner:GetSelectedData()=='all','empty classes must be skipped')
local tags={}
for _,text in ipairs({'Ranged','Instant','Ground','Notes','Modifier','Multi','Path','Copy'}) do tags[#tags+1]={id=text,text=text,description='Full '..text} end
filters:SetNavigation('above','below')
filters:SetTags(tags,{Ranged=true,Ground=true})
assert(#filters.tagbuttons==8 and filters.tags.local_scale.x==1)
local width=0
for _,button in ipairs(filters.tagbuttons) do width=width+button.nw_width end
assert(width<=420 and width>=250,'native font measurements must keep labels within the strip')
local first=filters.tagbuttons[1]
assert(first.underline.shown and not filters.tagbuttons[2].underline.shown)
assert(first.hovertext==nil,'mouse hover must not show tag tooltips')
assert(filters.spinner.focus_flow[MOVE_DOWN]==first)
assert(first.focus_flow[MOVE_LEFT]==filters.tagbuttons[8] and first.focus_flow[MOVE_DOWN]=='below')
first:SetFocus();assert(filters:HasFilterFocus())
assert(first:OnControl(CONTROL_ACCEPT,true));assert(first:OnControl(CONTROL_ACCEPT,false));assert(clicked=='Ranged')
filters:SetTags(tags,{Ground=true})
assert(filters.tagbuttons[1]==first and first.focus and not first.underline.shown,'toggling must retain focus and button identity')
filters:SetTags({},{});assert(filters.spinner.focus and filters.spinner.focus_flow[MOVE_DOWN]=='below')
-- Fourteen short labels fit across two full rows without sacrificing arrow space.
local two_rows={}
for i=1,14 do two_rows[i]={id='two'..i,text='范围'} end
filters:SetTags(two_rows,{two8=true})
assert(#filters.pages==1 and #filters.tagrows==2 and #filters.tagbuttons==14)
assert(not filters.prevpage.shown and not filters.nextpage.shown)
local second=filters.tagrows[2][1]
assert(second.pos.y==-32 and second.underline.shown)
assert(filters.tagrows[1][1].focus_flow[MOVE_DOWN].pos.y==-32)
assert(second.focus_flow[MOVE_UP].pos.y==0 and second.focus_flow[MOVE_DOWN]=='below')
second:SetFocus()
second:OnControl(CONTROL_ACCEPT,true);second:OnControl(CONTROL_ACCEPT,false)
assert(clicked=='two8')
filters:SetTags(two_rows,{})
assert(filters.tagrows[2][1]==second and second.focus and not second.underline.shown)
two_rows[15]={id='two15',text='范围'}
filters:SetTags(two_rows,{})
assert(#filters.pages==2 and #filters.tagrows==2,'overflow must paginate two rows together')
assert(filters.tagrows[2][1].focus_flow[MOVE_LEFT]==filters.prevpage)
assert(filters.nextpage.focus_flow[MOVE_DOWN]==filters.tagrows[2][#filters.tagrows[2]])
filters:SetPage(2)
assert(#filters.tagbuttons==3 and #filters.tagrows==1)
local many={}
for i=1,30 do many[i]={id='tag'..i,text='Tag number '..i} end
filters:SetTags(many,{tag20=true})
assert(#filters.pages>1 and filters.prevpage.shown and filters.nextpage.shown)
local originalpage=filters.page
local function check_arrow(button)
    assert(math.abs(button.image.w*button.image.local_scale.x-20)<.0001,'arrow width must stay fixed')
    assert(math.abs(button.image.h*button.image.local_scale.y-24)<.0001,'arrow height must stay fixed')
    assert(button.pos.y==-24,'click must not displace the arrow')
end
for _,button in ipairs({filters.nextpage,filters.prevpage}) do
    check_arrow(button)
    button:SetFocus();check_arrow(button)
    for i=1,3 do
        assert(button:OnControl(CONTROL_ACCEPT,true));check_arrow(button)
        assert(button:OnControl(CONTROL_ACCEPT,false));check_arrow(button)
    end
    button:ClearFocus();check_arrow(button)
end
filters.nextpage:SetFocus()
filters.nextpage:OnControl(CONTROL_ACCEPT,true)
filters.nextpage:OnControl(CONTROL_ACCEPT,false)
filters.nextpage:ClearFocus();check_arrow(filters.nextpage)
assert(filters.page~=originalpage and filters.tags.local_scale.x==1)
filters:SetTags(many,{tag20=true})
assert(filters.page~=originalpage,'selection updates must retain the current tag page')
filters:SetPage(#filters.pages+1);assert(filters.page==1)
filters.nextpage:SetFocus()
filters:SetTags({{id='long' ,text=string.rep('Very long translated label ',5)}},{})
assert(filters.spinner.focus and not filters.nextpage.focus,'hidden paging arrow must return focus')
assert(filters.tags.local_scale.x==1,'a long label must not shrink row spacing or other labels')
assert(filters.tagbuttons[1].local_scale.x<1 and filters.tagbuttons[1].nw_width*filters.tagbuttons[1].local_scale.x<=420.0001)
-- Exercise every real station/category in both languages; all labels must be
-- reachable once, without overlap or clipped hit regions on either row.
for _,language in ipairs({'zh','en'}) do
    require('nw/locale').configure(language)
    for _,station in ipairs({'nw_workbench','nw_engraver'}) do
        for _,choice in ipairs(require('nw/crafting_filter').class_options(station)) do
            local list=require('nw/crafting_filter').tags(station,choice.data)
            filters:SetTags(list,{})
            local seen={};local count=0
            for page=1,#filters.pages do
                filters:SetPage(page)
                assert(#filters.tagrows<=2)
                for r,row in ipairs(filters.tagrows) do
                    local last=-filters.row_limit/2
                    for _,b in ipairs(row) do
                        local half=b.nw_width*b.local_scale.x/2
                        assert(b.pos.x-half>=last-.001 and b.pos.x+half<=filters.row_limit/2+.001)
                        assert(b.pos.y==-(r-1)*32 and b.shown and not seen[b])
                        assert(b.local_scale.x==1,'real labels should keep their normal font size')
                        last=b.pos.x+half;seen[b]=true;count=count+1
                    end
                end
            end
            assert(count==#list,'pagination must not lose or repeat real tags')
        end
    end
end
""")


if __name__ == '__main__':
    unittest.main()
