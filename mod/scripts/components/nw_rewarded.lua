-- Added after resolving a boss body (including an unpaid bat clone).
-- Persist the receipt across a save taken
-- between the victory event and cleanup of a corpse or arena.
local function on_health_change(inst)
    if inst.components.nw_rewarded.reset_on_revive and not inst.components.health:IsDead() then
        inst:RemoveComponent("nw_rewarded")
    end
end
local Rewarded = Class(function(self, inst)
    self.inst=inst
    inst:ListenForEvent("healthdelta",on_health_change)
end)
function Rewarded:OnRemoveFromEntity()
    self.inst:RemoveEventCallback("healthdelta",on_health_change)
end
function Rewarded:OnSave()
    return {add_component_if_missing=true,reset_on_revive=self.reset_on_revive}
end
function Rewarded:OnLoad(data)
    self.reset_on_revive=data and data.reset_on_revive
end
return Rewarded
