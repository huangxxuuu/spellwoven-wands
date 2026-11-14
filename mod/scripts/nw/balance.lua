local C=require("nw/constants/balance")
local Modifiers=require("nw/constants/modifiers")
local M={mode=C.default_mode}

local function valid(mode) return mode=="fun" or mode=="balanced" or mode=="balanced_loot" end
function M.is_balanced() return M.mode=="balanced" or M.mode=="balanced_loot" end
function M.is_loot_only() return M.mode=="balanced_loot" end
function M.configure(mode)
    local nextmode=valid(mode) and mode or C.default_mode
    local changed=M.mode~=nextmode
    M.mode=nextmode
    require("nw/definitions").spells.mana_reduce.mana=M.is_balanced() and C.mana_reduce.balanced or Modifiers.cards.mana_reduce.mana
    return changed
end

function M.install(env,G)
    M.configure(env.GetModConfigData("world_difficulty"))
    local function send(player)
        if player and player.userid and player:IsValid() then
            G.SendModRPCToClient(G.CLIENT_MOD_RPC.nw_weave.balance_state,player.userid,M.mode)
        end
    end
    env.AddModRPCHandler("nw_weave","balance_query",function(player) send(player) end)
    env.AddClientModRPCHandler("nw_weave","balance_state",function(mode)
        if valid(mode) and G.TheWorld and not G.TheWorld.ismastersim then
            if M.configure(mode) and G.ThePlayer then
                G.ThePlayer:PushEvent("refreshcrafting")
            end
        end
    end)
    env.AddPlayerPostInit(function(player)
        local function query()
            if player==G.ThePlayer then
                G.SendModRPCToServer(G.MOD_RPC.nw_weave.balance_query)
            end
        end
        player:ListenForEvent("playeractivated",query)
        player:DoTaskInTime(0,query)
    end)
end
return M
