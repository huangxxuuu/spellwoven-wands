-- Run the real widget constructor and input callbacks with a small UI backend.
-- In particular, world coordinates differ from local HUD coordinates here.
Class=function(base,ctor)
    local c={_ctor=ctor};c.__index=c
    return setmetatable(c,{__index=base,__call=function(cls,...)
        local self=setmetatable({},cls);ctor(self,...);return self
    end})
end
local Widget=Class(nil,function(self)
    self.children={};self.pos={x=0,y=0};self.scale={x=1,y=1};self.shown=true
    self.inst={IsValid=function() return not self.dead end,DoPeriodicTask=function() end}
end)
function Widget:AddChild(c) c.parent=self;self.children[#self.children+1]=c;return c end
function Widget:SetClickable(v) self.clickable=v end
function Widget:SetSize(w,h) self.size={w,h} end
function Widget:SetTint(...) self.tint={...} end
function Widget:SetTexture(a,t) self.texture=t end
function Widget:SetPosition(x,y) self.pos={x=x,y=y} end
function Widget:GetPosition() return self.pos end
function Widget:SetScale(x,y) self.scale={x=x,y=y or x} end
function Widget:GetScale()
    local p=self.parent and self.parent:GetScale() or {x=1,y=1}
    return {x=self.scale.x*p.x,y=self.scale.y*p.y}
end
function Widget:GetWorldPosition()
    local p=self.parent and self.parent:GetWorldPosition() or {x=0,y=0}
    local s=self.parent and self.parent:GetScale() or {x=1,y=1}
    return {x=p.x+self.pos.x*s.x,y=p.y+self.pos.y*s.y}
end
function Widget:Hide() self.shown=false;if self.OnHide then self:OnHide() end end
function Widget:Show() self.shown=true end
function Widget:StartUpdating() end
function Widget:Kill() self.dead=true end
function Widget:OnMouseButton() return false end
function Widget:OnControl() return false end
function Widget:SetHoverText(text)
    self.hovertext_root=self.hovertext_root or Widget();self.hovertext_root:Hide()
    self.hovertext_bg=self.hovertext_bg or Widget()
    self.hovertext={GetRegionSize=function() return 140,40 end,Hide=function() end}
end
local Image=Class(Widget,function(self,atlas,texture) Widget._ctor(self);self.texture=texture end)
package.loaded["widgets/widget"]=Widget;package.loaded["widgets/image"]=Image
local Button=Class(Widget,function(self) Widget._ctor(self) end)
function Button:ForceImageSize(w,h) self:SetSize(w,h) end
function Button:SetText(text) self.text=text end
function Button:SetTextSize(size) end
function Button:SetOnClick(fn) self.onclick=fn end
package.loaded["widgets/imagebutton"]=Button
local visited
VisitURL=function(url) visited=url end
package.loaded["widgets/nineslice"]=Class(Widget,function(self)
    Widget._ctor(self);self.mid_center=self:AddChild(Widget())
end)
local now,mx,my,down=0,0,0,false
local sw,sh=1280,720
GetTime=function() return now end
MOUSEBUTTON_RIGHT=2;CONTROL_SECONDARY=3;CONTROL_PRIMARY=4;EQUIPSLOTS={HANDS=1}
local load_cb,saves
saves={}
TheSim={GetScreenSize=function() return sw,sh end,
    GetPersistentString=function(_,_,cb) load_cb=cb end,
    SetPersistentString=function(_,_,value,_,cb) saves[#saves+1]=value;cb() end}
package.loaded.json={encode=function(v) return {x=v.x,y=v.y} end,decode=function(v) return v end}
TheInput={IsMouseDown=function() return down end,GetScreenPosition=function() return {x=mx,y=my} end,
    IsControlPressed=function() return false end}
local capacity,mana,cooling,total,ready,near=2,60,0,100,true,false
local function net(fn) return {value=fn} end
local w={IsValid=function() return true end,HasTag=function(_,tag) return tag=="nw_wand" end,
    _nw_ready=net(function() return true end),_nw_cards=net(function() return string.rep("0,",capacity-1).."0" end),
    _nw_mana=net(function() return mana end),_nw_maxmana=net(function() return 120 end),
    _nw_cooldown=net(function() return cooling end),_nw_cooltotal=net(function() return total end),
    _nw_cancast=net(function() return ready end)}
local equipped=w
ThePlayer={HUD={},replica={inventory={GetEquippedItem=function() return equipped end}}}
local screen=ThePlayer.HUD
TheFrontEnd={GetActiveScreen=function() return screen end}
package.loaded["nw/editing"]={near=function() return near end}
local Panel=require("widgets/nw_wandpanel")
local root=Widget();root:SetPosition(640,60);root:SetScale(1.25)
local panel=root:AddChild(Panel({}));panel.focus=true
load_cb(false,"");panel:Refresh();panel:OnUpdate(.1)
assert(panel.status.edit.texture=="readonly.tex")
assert(panel.status.state=="ready" and panel.status.target_mana==.5)
panel.guide.onclick()
assert(visited=="https://huangxxuuu.github.io/spellwoven-wands/")
require("nw/locale").configure("en")
panel.guide.onclick()
assert(visited=="https://huangxxuuu.github.io/spellwoven-wands/en/")
require("nw/locale").configure("zh")
panel.guide.focus=true
assert(not panel:BeginWindowDrag(0,0))
panel.guide.focus=false
local gauge_width=panel.status.mana.size[1]
for count=2,12 do
    capacity=count;panel:Refresh();panel:OnUpdate(.1)
    assert(#panel.row.spells==count and panel.status.mana.size[1]==gauge_width)
    assert(#panel.frame.pieces==9)
    local width=count*76+40
    assert(panel.guide.pos.x+10<width/2 and panel.guide.pos.y+10<87)
    assert((panel.guide.pos.x-66)^2+(panel.guide.pos.y-56)^2>(14+10)^2,
        "guide button overlaps cast indicator")
    for row=1,3 do
        local a,b,c=unpack(panel.frame.pieces,(row-1)*3+1,row*3)
        assert(a.size[1]==16 and c.size[1]==16 and b.size[1]==width-32)
        assert(a.pos.x+a.size[1]/2==b.pos.x-b.size[1]/2)
        assert(b.pos.x+b.size[1]/2==c.pos.x-c.size[1]/2,"frame seam is open")
    end
end
local function mouse_at(lx,ly)
    local p,s=panel:GetWorldPosition(),panel:GetScale()
    mx,my=p.x+lx*s.x,p.y+ly*s.y
end
capacity=2;panel:Refresh();mouse_at(-38,0);down=true
assert(not panel:BeginWindowDrag(mx,my) and not ThePlayer._nw_hud_dragging,"slot initiated a window drag")
mouse_at(0,56);assert(panel:OnMouseButton(MOUSEBUTTON_RIGHT,true,mx,my))
assert(ThePlayer._nw_hud_dragging==panel)
mx,my=mx+200,my+120;now=.1;panel:OnUpdate(.1)
assert(not panel.window_drag.moved,"short click must not reposition")
now=.2;panel:OnUpdate(.1)
assert(panel.window_drag.moved)
down=false;panel:OnUpdate(.1)
assert(not panel.window_drag and not ThePlayer._nw_hud_dragging and #saves==1)
local last=saves[1]
assert(math.abs(last.x-.65625)<.001 and math.abs(last.y-(305/720))<.001,"drag ignored HUD scaling")
-- A full wand and a smaller screen must be clamped without losing user intent.
capacity=12;panel.saved_position={version=1,x=.99,y=.99};panel:Refresh()
local p,s=panel:GetWorldPosition(),panel:GetScale()
local width,bottom,top=require("nw/hud_layout").bounds(12)
assert(p.x+width*s.x/2<=sw-5.99 and p.y+top*s.y<=sh-5.99)
sw,sh=900,600;panel:OnUpdate(.1);p=panel:GetWorldPosition();s=panel:GetScale()
assert(p.x-width*s.x/2>=5.99 and p.x+width*s.x/2<=sw-5.99)
-- Focus moves to the pause screen while RMB is held: release capture and save.
mouse_at(0,56);down=true;panel:BeginWindowDrag(mx,my);now=1;mx=mx-100;panel:OnUpdate(.2)
screen={};panel:OnUpdate(.1)
assert(not panel.window_drag and not ThePlayer._nw_hud_dragging and #saves==2)
screen=ThePlayer.HUD
near=true;now=2;cooling=50;panel:Refresh();panel:OnUpdate(.1)
assert(panel.status.edit.texture=="edit.tex" and panel.status.step==30)
now=2.25;panel:OnUpdate(.1);assert(panel.status.step==45,"cooldown interpolation did not advance")
cooling=0;mana=0;ready=false;panel:Refresh();panel:OnUpdate(1)
assert(panel.status.state=="blocked" and not panel.status.fill.shown)
equipped=nil;panel:Refresh();assert(not panel.shown)
panel:Kill();assert(panel.dead)
print("HUD widget: constructor, all capacities, scaled drag, capture/cancel/save, screen resize and status transitions")
