local C=require("nw/constants/acquisition").first_boss
local M={radius=C.radius,modifier_chance=C.modifier_chance}
local variants=require("nw/util").copy(C.variants)
M.variants=variants
function M.choose(random)
    return random()<M.modifier_chance and "imprint_hit" or variants[random(#variants)]
end
function M.pay(inst,origin,drop,rule)
    if not (rule.group or inst:HasTag("epic")) then return 0 end
    local count=0
    for _,player in ipairs(AllPlayers or {}) do
        local receipt=player.components.nw_firstboss
        if receipt and not receipt.claimed and player:IsValid() and not player:IsInLimbo()
            and player:GetDistanceSqToInst(origin)<=M.radius*M.radius then
            local card=drop("nw_spellcard")
            if card then
                card:SetSpell(M.choose(math.random))
                card.source="first_boss:"..inst.prefab
                receipt.claimed=true
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
