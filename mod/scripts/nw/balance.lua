-- Gameplay difficulty is a world setting, never a personal preference.
-- Stored wand rolls remain unchanged; callers apply only the requested rules.
local M={mode="fun"}

local function valid(mode) return mode=="fun" or mode=="balanced" or mode=="balanced_loot" end
function M.is_balanced() return M.mode=="balanced" or M.mode=="balanced_loot" end
function M.is_loot_only() return M.mode=="balanced_loot" end
function M.configure(mode)
    local nextmode=valid(mode) and mode or "fun"
    local changed=M.mode~=nextmode
    M.mode=nextmode
    -- The compiler and all card stat panels share this definition. Updating the
    -- existing table also handles clients receiving the joined world's mode.
    require("nw/definitions").spells.mana_reduce.mana=M.is_balanced() and -20 or -30
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
    -- Each shard reads its own startup configuration. Only players joining
    -- this world receive its mode; difficulty is never shared between shards.
end
return M
