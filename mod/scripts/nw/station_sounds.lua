-- Entering/leaving our crafting stations changes the catalogue automatically.
-- Update the native crafting indicator without announcing that transition.
local M={}
local quiet_stations={nw_workbench=true,nw_engraver=true}
function M.install(pinbar)
    local button=pinbar.open_menu_button
    if not button or not button.SetCraftingState then return end
    local previous
    local update=button.SetCraftingState
    button.SetCraftingState=function(self,can_prototype,new_recipe_available,...)
        local owner=pinbar.owner
        local builder=owner and owner.replica and owner.replica.builder
        local station=builder and builder:GetCurrentPrototyper()
        if station~=previous and (station and quiet_stations[station.prefab]
            or previous and quiet_stations[previous.prefab]) then
            -- Native SetCraftingState plays sounds for either a changed research
            -- state or newly available recipes. Consume just this transition.
            self.can_prototype=can_prototype
            if can_prototype then self.prototype:Show() else self.prototype:Hide() end
            new_recipe_available=false
        end
        previous=station
        return update(self,can_prototype,new_recipe_available,...)
    end
end
return M
