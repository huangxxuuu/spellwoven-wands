local Widget=require("widgets/widget")
local Image=require("widgets/image")
local Cards=require("nw/cards")
local Info=require("nw/spell_info")
local Hint=require("nw/inventory_hint")
local Row=Class(Widget,function(self,size,selectslot)
    Widget._ctor(self,"nw_slotrow")
    self.size=size
    self.cells={}
    self.selectslot=selectslot
    if not selectslot then self:SetClickable(false) end
end)
function Row:PlaceHover()
    local cell=self.hovered
    if not cell then return end
    if not cell.focus or not cell:IsVisible() then cell.hovertext_root:Hide();return end
    Hint.show_card(cell,cell.spell,self.size*.5)
end
function Row:SetCards(encoded)
    if self.encoded==encoded then return end
    self.encoded=encoded
    self.spells=Cards.decode(encoded)
    local count=#self.spells
    for i=1,math.max(#self.cells,count) do
        local cell=self.cells[i]
        if i<=count then
            if not cell then
                cell=self:AddChild(Image("images/hud.xml","inv_slot.tex"))
                self.cells[i]=cell
                cell:SetSize(self.size-2,self.size-2)
                cell.icon=cell:AddChild(Image("images/inventoryimages/nw_icons.xml",Info.icon("spark")))
                cell.icon:SetSize(self.size-7,self.size-7);cell.icon:SetClickable(false)
                if self.selectslot then
                    Hint.setup_root(cell)
                    local gain,lose=cell.OnGainFocus,cell.OnLoseFocus
                    cell.OnGainFocus=function(widget)
                        gain(widget);self.hovered=widget;self:PlaceHover()
                    end
                    cell.OnLoseFocus=function(widget)
                        lose(widget)
                        if self.hovered==widget then self.hovered=nil end
                    end
                    cell.OnControl=function(widget,control,down)
                        if widget.focus and (control==CONTROL_ACCEPT or control==CONTROL_SECONDARY) then
                            if control==CONTROL_ACCEPT then self.selectslot(i,down) end
                            return true
                        end
                        return false
                    end
                else cell:SetClickable(false) end
            end
            cell:Show();cell:SetPosition((i-(count+1)/2)*self.size,0)
            local id=self.spells[i]
            if cell.spell~=id then
                cell.spell=id
                if id then
                    cell.icon:SetTexture("images/inventoryimages/nw_icons.xml",Info.icon(id))
                    cell.icon:SetSize(self.size-7,self.size-7);cell.icon:Show()
                else cell.icon:Hide() end
            end
        else cell:Hide() end
    end
    self.width=count*self.size
    self:PlaceHover()
end
return Row
