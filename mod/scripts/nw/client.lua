local M={}
function M.tile(self)
    if self.item and self.item:HasTag("nw_spellcard") then
        require("nw/inventory_hint").install(self,false)
        return
    end
    if not self.item or not self.item:HasTag("nw_wand") then return end
    require("nw/inventory_hint").install(self,true)
    local UIAnim=require("widgets/uianim")
    local meter=self:AddChild(UIAnim())
    meter:GetAnimState():SetBank("recharge_meter");meter:GetAnimState():SetBuild("recharge_meter")
    meter:GetAnimState():SetMultColour(.1,.2,.6,.7);meter:SetClickable(false)
    self.inst:DoPeriodicTask(.05,function()
        local item=self.item
        if not item or not item:IsValid() then meter:Hide();return end
        local remain=item._nw_cooldown:value()
        local total=item._nw_cooltotal:value()
        if meter._remain==remain and meter._total==total then return end
        meter._remain=remain;meter._total=total
        if remain>0 then
            meter:Show();meter:GetAnimState():SetPercent("recharge",1-math.min(1,remain/math.max(1,total)))
        else meter:Hide() end
    end)
end
-- Bridge only drag releases for the wand strip. Native inventory input
-- continues to own pickup, backpack behavior, and ordinary slot clicks.
function M.inventory_slot(slot)
    local control=slot.OnControl
    slot.OnControl=function(self,key,down)
        local p=ThePlayer
        local panel=p and p.HUD and p.HUD.controls.nw_wandpanel
        if panel and self.focus and key==CONTROL_ACCEPT and panel:CanEdit() then
            if down then
                panel:StartInventoryDrag(not p.replica.inventory:GetActiveItem() and self.tile and self.tile.item)
            elseif panel.press and panel.press.slot and self.container==p.replica.inventory then
                panel:EndDrag(nil,self)
                return true
            end
        end
        return control(self,key,down)
    end
end
return M
