local Widget=require("widgets/widget")
local Row=require("widgets/nw_slotrow")
local Editor=require("nw/editor_client")
local Editing=require("nw/editing")
local Layout=require("nw/hud_layout")
local Position=require("nw/hud_position")

local Panel=Class(Widget,function(self,bar)
    Widget._ctor(self,"nw_wandpanel")
    self.bar=bar
    self.frame=self:AddChild(require("widgets/nw_wandframe")())
    self.frame:SetPosition(0,16)
    self.row=self:AddChild(Row(Layout.slot,function(i,down) self:Slot(i,down) end))
    self.status=self:AddChild(require("widgets/nw_wandstatus")())
    self.count=2
    self:Hide()
    self.inst:DoPeriodicTask(.10,function() self:Refresh() end)
    Position.load(function(value)
        if self.inst:IsValid() and not self.position_touched then self.saved_position=value end
    end)
    self:StartUpdating()
end)

function Panel:Refresh()
    local p=ThePlayer
    local inv=p and p.replica.inventory
    local w=inv and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    if self.wand~=w then self:StopWindowDrag();self.press=nil;self.drop=nil;self.wand=w end
    if not w or not w:HasTag("nw_wand") or not w._nw_ready:value() then self:StopWindowDrag();self:Hide();return end
    self:Show()
    self.row:SetCards(w._nw_cards:value())
    local count=#self.row.spells
    if self.count~=count or not self.frame_width then
        self.count=count;self.frame_width=count*Layout.slot+40
        self.frame:SetSize(self.frame_width,142)
    end
    self:PlaceWindow()
    self.row:PlaceHover()
    if not self.checked or GetTime()-self.checked>=.25 then
        self.near=Editing.near(p);self.checked=GetTime()
    end
    if self.press and not TheInput:IsControlPressed(CONTROL_PRIMARY) then self.press=nil end
    self:FinishDrop()
    local request=p._nw_edit_request
    local hint
    if request and request.wand==require("nw/edit_protocol").id(w) and request.done and not request.ok
        and GetTime()-request.time<2 then hint=require("nw/edit_protocol").messages[request.code] end
    self.status:Refresh(w,self.near,hint)
end

function Panel:PlaceWindow()
    local sw,sh=TheSim:GetScreenSize()
    local width,bottom,top=Layout.bounds(self.count)
    local parent_scale=self.parent:GetScale()
    local fit=math.min(1,(sw-12)/(width*parent_scale.x),(sh-12)/((top-bottom)*parent_scale.y))
    if self.fit~=fit then self.fit=fit;self:SetScale(fit) end
    local scale=self:GetScale()
    local x,y
    if self.saved_position then x,y=self.saved_position.x*sw,self.saved_position.y*sh
    else
        local row_y=self.bar.toprow and self.bar.toprow:GetPosition().y or 0
        self:SetPosition(0,row_y+100)
        local p=self:GetWorldPosition();x,y=p.x,p.y
    end
    x,y=Position.clamp(x,y,width*scale.x,bottom*scale.y,top*scale.y,sw,sh)
    local at,localpos=self:GetWorldPosition(),self:GetPosition()
    self:SetPosition(localpos.x+(x-at.x)/parent_scale.x,localpos.y+(y-at.y)/parent_scale.y)
end
function Panel:BeginWindowDrag(x,y)
    if self.window_drag then return true end
    local p=ThePlayer
    if not self.shown or not self.focus or not p or not p.HUD or TheFrontEnd:GetActiveScreen()~=p.HUD then return false end
    local pos,scale=self:GetWorldPosition(),self:GetScale()
    local lx,ly=(x-pos.x)/scale.x,(y-pos.y)/scale.y
    local width,bottom,top=Layout.bounds(self.count)
    if math.abs(lx)>width/2 or ly<bottom or ly>top or Layout.slot_at(lx,ly,self.count) then return false end
    self.window_drag={x=x,y=y,dx=pos.x-x,dy=pos.y-y,time=GetTime(),owner=p}
    p._nw_hud_dragging=self
    self.press=nil;self.drop=nil
    return true
end
function Panel:StopWindowDrag()
    local drag=self.window_drag
    if not drag then return end
    self.window_drag=nil
    if drag.owner._nw_hud_dragging==self then drag.owner._nw_hud_dragging=nil end
    if drag.moved then
        local p=self:GetWorldPosition();local sw,sh=TheSim:GetScreenSize()
        self.saved_position={version=1,x=p.x/sw,y=p.y/sh}
        Position.save(self.saved_position)
    end
end
function Panel:OnMouseButton(button,down,x,y)
    if button==MOUSEBUTTON_RIGHT then
        if not down and self.window_drag then self:StopWindowDrag();return true end
        if down and self:BeginWindowDrag(x,y) then return true end
    end
    return Widget.OnMouseButton(self,button,down,x,y)
end
function Panel:OnControl(control,down)
    if control==CONTROL_SECONDARY then
        if self.window_drag then if not down then self:StopWindowDrag() end;return true end
        if self.focus and down and TheInput:IsMouseDown(MOUSEBUTTON_RIGHT) then
            local p=TheInput:GetScreenPosition()
            if self:BeginWindowDrag(p.x,p.y) then return true end
        end
    end
    return Widget.OnControl(self,control,down)
end
function Panel:OnUpdate(dt)
    local drag=self.window_drag
    if drag then
        if not TheInput:IsMouseDown(MOUSEBUTTON_RIGHT) or not self.shown
            or TheFrontEnd:GetActiveScreen()~=drag.owner.HUD then self:StopWindowDrag()
        else
            local p=TheInput:GetScreenPosition()
            if GetTime()-drag.time>=.15 and (drag.moved or (p.x-drag.x)^2+(p.y-drag.y)^2>=9) then
                local sw,sh=TheSim:GetScreenSize()
                drag.moved=true;self.position_touched=true
                self.saved_position={version=1,x=(p.x+drag.dx)/sw,y=(p.y+drag.dy)/sh}
            end
        end
    end
    if self.shown then
        self:PlaceWindow()
        self.status:OnUpdate(dt)
        self.row:PlaceHover()
    end
end
function Panel:OnHide()
    self:StopWindowDrag()
    self.row:PlaceHover()
end
function Panel:Kill()
    self:StopWindowDrag()
    Widget.Kill(self)
end

function Panel:CanEdit()
    local p=ThePlayer
    return self.shown and not self.window_drag and p and self.wand and self.wand:IsValid()
        and p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==self.wand
        and Editing.near(p)
end
function Panel:Slot(i,down)
    if not self:CanEdit() then self.press=nil;self.drop=nil;return end
    if not down then
        self:EndDrag(i)
        return
    end
    self.press=nil;self.drop=nil
    local p=ThePlayer
    local card=p.replica.inventory:GetActiveItem()
    if card and not card:HasTag("nw_spellcard") then return end
    local old=self.row.spells[i]
    if not card and not old then return end
    local revision=self.wand._nw_revision:value()
    if Editor.submit(p,self.wand,i,card,true) and old then
        self.press={slot=i,spell=old,revision=revision,request=p._nw_edit_request,wand=self.wand}
    end
end

-- Native inventory slots pick up on mouse-down, even when the button is
-- held. Complete an actual drag on release; a simple click leaves the card
-- on the normal inventory cursor so it can also be placed with another click.
function Panel:StartInventoryDrag(card)
    self.press=nil;self.drop=nil
    if card and card:HasTag("nw_spellcard") and self:CanEdit() then
        self.press={item=card,wand=self.wand}
    end
end
function Panel:EndDrag(to,inventoryslot)
    local drag=self.press
    self.press=nil
    if not drag or drag.slot==to and not inventoryslot or not self:CanEdit() then return end
    if inventoryslot and not drag.slot then return end
    drag.to=to;drag.inventoryslot=inventoryslot;drag.expires=GetTime()+2
    self.drop=drag
    self:FinishDrop()
end
function Panel:FinishDrop()
    local drag=self.drop
    if not drag then return end
    if not self:CanEdit() or drag.wand~=self.wand or GetTime()>drag.expires then self.drop=nil;return end
    local p=ThePlayer
    local card=p.replica.inventory:GetActiveItem()
    if drag.request then
        if drag.request~=p._nw_edit_request or drag.request.done and not drag.request.ok then self.drop=nil;return end
        if not drag.request.done or self.wand._nw_revision:value()~=drag.revision+1
            or GetTime()-drag.request.time<.16 then return end
    end
    if not card then return end
    if not card:HasTag("nw_spellcard") or drag.item and card~=drag.item
        or drag.spell and require("nw/cards").bycode[card._spell:value()]~=drag.spell then self.drop=nil;return end
    self.drop=nil
    if drag.inventoryslot then
        local slot=drag.inventoryslot
        if slot.inst:IsValid() and slot.container==p.replica.inventory then slot:Click(false) end
    else Editor.submit(p,self.wand,drag.to,card,true) end
end

return Panel
