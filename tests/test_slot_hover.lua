Class=function(base,ctor)
    local c={_ctor=ctor};c.__index=c
    return setmetatable(c,{__index=base,__call=function(cls,...)
        local self=setmetatable({},cls);ctor(self,...);return self
    end})
end
local Widget=Class(nil,function(self) self.shown=true end)
function Widget:AddChild(w) w.parent=self;return w end
function Widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Widget:Show() self.shown=true end
function Widget:Hide() self.shown=false end
function Widget:SetPosition(x,y) self.x,self.y=x,y end
function Widget:SetScale(s) self.scale=s end
function Widget:GetScale() return {x=self.scale,y=self.scale} end
function Widget:GetWorldPosition() return {x=self.x,y=self.y} end
function Widget:SetClickable(v) self.clickable=v end
function Widget:SetSize() end
function Widget:SetTexture() end
function Widget:SetHoverText(text,params)
    assert(text==" " and not params.bg)
    self.hovertext=Widget();self.hovertext_root=Widget();self.hovertext_root:Hide()
    self.OnGainFocus=function() self.hovertext_root:Show() end
    self.OnLoseFocus=function() self.hovertext_root:Hide() end
end
package.loaded["widgets/widget"]=Widget;package.loaded["widgets/image"]=Widget
local panel=Widget();panel.width=480;panel.height=248;panel.inst={IsValid=function() return true end}
function panel:Display(data) self.model=data end
package.loaded["widgets/nw_itemhint"]=function() return panel end
TheSim={GetScreenSize=function() return 1280,720 end}
local Row=require("widgets/nw_slotrow")
local row=Row(76,function() end)
row:SetCards("0,1");local cell=row.cells[2]
assert(cell.hovertext_root and not cell.hovertext_root.clickable)
for _,scale in ipairs({.7,1,1.5}) do
    for _,cx in ipairs({35,640,1240}) do
        cell:SetScale(scale);cell.hovertext_root:SetScale(scale)
        cell:SetPosition(cx,100)
        cell.focus=true;cell:OnGainFocus()
        local root=cell.hovertext_root
        assert(panel.parent==root and root.shown and panel.model.title=="火花弹")
        local w,h=panel.width*scale*panel.scale,panel.height*scale*panel.scale
        assert(root.y-h/2>=100+38*scale and root.y+h/2<=720)
        assert(root.x-w/2>=0 and root.x+w/2<=1280)
        cell.focus=false;cell:OnLoseFocus();assert(not root.shown)
    end
end
cell.focus=true;cell:OnGainFocus()
local cursor
ThePlayer={replica={inventory={GetActiveItem=function() return cursor end}}}
cursor={HasTag=function(_,tag) return tag=="nw_spellcard" end}
row:PlaceHover();assert(not cell.hovertext_root.shown)
cell.focus=false;cell:OnLoseFocus();cell.focus=true;cell:OnGainFocus()
assert(not cell.hovertext_root.shown,"hovering a new slot while carrying a card")
row:SetCards("0,0");assert(not cell.hovertext_root.shown,"empty slot while carrying a card")
row:SetCards("0,2");assert(not cell.hovertext_root.shown,"replicated swap while carrying a card")
cursor=nil;row:PlaceHover();assert(cell.hovertext_root.shown and panel.model.title=="魔法箭")
cursor={HasTag=function() return false end};row:PlaceHover();assert(cell.hovertext_root.shown)
row:SetCards("0,0");assert(panel.model.title=="空法术槽")
row:SetCards("0");assert(not cell.hovertext_root.shown)
row:SetCards("0,2");row:Hide();row:PlaceHover();assert(not cell.hovertext_root.shown)
print("held slots: shared card detail panel, focused replacement, empty/hidden slots, scale and screen edges")
