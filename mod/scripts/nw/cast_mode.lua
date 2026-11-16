local C=require("nw/constants/casting").mode
local M={}
local installed,configured,synced,mode=false,false,false,false
local globals

function M.enabled()
    if installed and globals.TheWorld and globals.TheWorld.ismastersim then return configured end
    return mode
end
function M.ready()
    return not installed or (globals.TheWorld and globals.TheWorld.ismastersim) or synced
end

function M.install(env,G,cast)
    installed,globals=true,G
    configured=env.GetModConfigData("instant_cast")==true
    synced,mode=false,false
    cast.instant=false
    local current,pending,serial,retry=nil,nil,0,nil
    local function apply(value)
        mode,synced=value,true
        cast.instant=value
    end
    local function cancel()
        if retry then retry:Cancel();retry=nil end
    end
    local function reset()
        cancel()
        current,pending=nil,nil
        synced,mode=false,false
        cast.instant=false
    end
    env.AddSimPostInit(function()
        if G.TheWorld.ismastersim then apply(configured) else reset() end
    end)
    env.AddModRPCHandler("nw_weave","cast_mode_query",function(player,request)
        if G.TheWorld and G.TheWorld.ismastersim and player and player.userid and player:IsValid()
            and type(request)=="number" and request>=1 and request<=C.max_request and request==math.floor(request) then
            -- Use an explicit enum: a normal-mode reply must remain distinguishable
            -- from a missing argument at the native RPC boundary.
            G.SendModRPCToClient(G.CLIENT_MOD_RPC.nw_weave.cast_mode_state,player.userid,configured and 1 or 0,request)
        end
    end)
    env.AddClientModRPCHandler("nw_weave","cast_mode_state",function(value,request)
        if G.TheWorld and not G.TheWorld.ismastersim and (value==0 or value==1)
            and current and current==G.ThePlayer and current:IsValid() and request==pending then
            cancel();pending=nil;apply(value==1)
        end
    end)
    env.AddPlayerPostInit(function(player)
        local function activate()
            if player~=G.ThePlayer then return end
            if G.TheWorld.ismastersim then apply(configured);return end
            reset();current=player
            serial=serial%C.max_request+1;pending=serial
            local request=pending
            local function query()
                retry=nil
                if current~=player or player~=G.ThePlayer or not player:IsValid() or pending~=request then return end
                G.SendModRPCToServer(G.MOD_RPC.nw_weave.cast_mode_query,request)
                if pending==request then retry=player:DoTaskInTime(C.retry_delay,query) end
            end
            query()
        end
        local function deactivate()
            if current==player then reset() end
        end
        player:ListenForEvent("playeractivated",activate)
        player:ListenForEvent("playerdeactivated",deactivate)
        player:ListenForEvent("onremove",deactivate)
        player:DoTaskInTime(0,activate)
    end)
end
return M
