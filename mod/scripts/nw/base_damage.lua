local C=require("nw/constants/balance")
local D=require("nw/definitions")
local M={multiplier=C.default_damage_multiplier}
local allowed=C.damage_multipliers
local originals={}
for id,d in pairs(D.spells) do
    local base={}
    for _,key in ipairs({"damage","burn_damage","jump_damage","end_damage","planar",
        "explosion_damage","echo_damage","effect_damage"}) do
        if d[key]~=nil then base[key]=d[key] end
    end
    originals[id]=base
end

function M.configure(value)
    local rate=allowed[value] and value or C.default_damage_multiplier
    local changed=M.multiplier~=rate
    M.multiplier=rate
    for id,base in pairs(originals) do
        local d=D.spells[id]
        for key,value in pairs(base) do d[key]=value*rate end
        d.base_damage_multiplier=rate
    end
    return changed
end

function M.install(env,G)
    M.configure(env.GetModConfigData("base_damage_multiplier"))
    env.AddModRPCHandler("nw_weave","base_damage_query",function(player)
        if player and player.userid and player:IsValid() then
            G.SendModRPCToClient(G.CLIENT_MOD_RPC.nw_weave.base_damage_state,player.userid,M.multiplier)
        end
    end)
    env.AddClientModRPCHandler("nw_weave","base_damage_state",function(rate)
        if allowed[rate] and G.TheWorld and not G.TheWorld.ismastersim then
            if M.configure(rate) and G.ThePlayer then G.ThePlayer:PushEvent("refreshcrafting") end
        end
    end)
    env.AddPlayerPostInit(function(player)
        local function query()
            if player==G.ThePlayer then
                G.SendModRPCToServer(G.MOD_RPC.nw_weave.base_damage_query)
            end
        end
        player:ListenForEvent("playeractivated",query)
        player:DoTaskInTime(0,query)
    end)
end
return M
