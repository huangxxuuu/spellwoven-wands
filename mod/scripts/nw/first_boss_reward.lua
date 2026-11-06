local M={radius=12,modifier_chance=.05}
local variants={"spark_hit","arrow_hit","heavy_hit","scatter_hit","fire_hit","frost_hit"}
M.variants=variants
function M.choose(random)
    return random()<M.modifier_chance and "imprint_hit" or variants[random(#variants)]
end
function M.pay(inst,origin,drop,rule)
    if not (rule.group or inst:HasTag("epic")) then return 0 end
    local count=0
    for _,player in ipairs(AllPlayers or {}) do
        local receipt=player.components.nw_firstboss
        -- Proximity is the user's definition of participation, including ghosts.
        if receipt and not receipt.claimed and player:IsValid() and not player:IsInLimbo()
            and player:GetDistanceSqToInst(origin)<=M.radius*M.radius then
            local card=drop("nw_spellcard")
            if card then
                card:SetSpell(M.choose(math.random))
                card.source="first_boss:"..inst.prefab
                receipt.claimed=true -- Commit only after a real card has been produced.
                count=count+1
            end
        end
    end
    return count
end
function M.install(env)
    env.AddPlayerPostInit(function(player)
        if not TheWorld.ismastersim then return end
        player:AddComponent("nw_firstboss")
        -- The celestial portal copies only an explicit subset of components.
        local save,load=player.SaveForReroll,player.LoadForReroll
        player.SaveForReroll=function(self,...)
            local data=save and save(self,...) or {}
            data=data or {};data.nw_firstboss=self.components.nw_firstboss:OnSave()
            return data
        end
        player.LoadForReroll=function(self,data,...)
            if load then load(self,data,...) end
            self.components.nw_firstboss:OnLoad(data and data.nw_firstboss)
        end
    end)
end
return M
