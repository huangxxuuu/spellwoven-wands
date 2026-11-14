local M={enabled=true,key="nw_weave_limit_speech_v1",interval=require("nw/constants/performance").feedback.interval}
local Locale=require("nw/locale")
local lines={
    {"这世界限制了我的发挥。","This world is holding my magic back."},
    {"再强的法术，也得给这世界留点余地。","Even magic must leave this world some breathing room."},
    {"看来，这世界装不下我全部的法术。","It seems this world cannot hold all my magic."},
}
for _,line in ipairs(lines) do Locale.register(line[1],line[2]) end
function M.limited(owner)
    if not TheWorld or not TheWorld.ismastersim then return false end
    local userid=type(owner)=="string" and owner or owner and owner.userid
    if type(userid)~="string" or userid=="" then return false end
    local player
    for _,p in ipairs(AllPlayers or {}) do
        if p.userid==userid then player=p;break end
    end
    if not player or not player:IsValid() or player._nw_limit_speech_enabled~=true
        or player:HasTag("playerghost") then return false end
    local talker=player.components and player.components.talker
    if not talker or player.components.health and player.components.health:IsDead() then return false end
    local state=TheWorld._nw_limit_speech
    if not state then state={cooldowns={},sequence={}};TheWorld._nw_limit_speech=state end
    local cooldowns,sequence=state.cooldowns,state.sequence
    local now=GetTime()
    if (cooldowns[userid] or -math.huge)>now then return false end
    cooldowns[userid]=now+M.interval
    local n=(sequence[userid] or 0)%#lines+1;sequence[userid]=n
    talker:Say(Locale.for_player(player,lines[n][1]))
    return true
end
local loaded,loading,revision=false,false,0
local waiters={}
local writing,queued=false,nil
local function announce()
    if not ThePlayer then return end
    SendModRPCToServer(MOD_RPC.nw_weave.limit_speech,M.enabled)
end
function M.load(callback)
    if loaded then if callback then callback() end;return end
    if callback then waiters[#waiters+1]=callback end
    if loading then return end
    loading=true
    local at=revision
    TheSim:GetPersistentString(M.key,function(ok,value)
        if at==revision and ok and (value=="true" or value=="false") then M.enabled=value=="true" end
        loaded,loading=true,false
        announce()
        local callbacks=waiters;waiters={}
        for _,fn in ipairs(callbacks) do fn() end
    end,false)
end
local function flush()
    if writing or queued==nil then return end
    writing=true
    local value=queued;queued=nil
    TheSim:SetPersistentString(M.key,tostring(value),false,function() writing=false;flush() end)
end
function M.set(value)
    if type(value)~="boolean" then return false end
    revision=revision+1;loaded=true;M.enabled=value
    queued=value;flush();announce()
    return true
end
function M.install(env,G)
    env.AddModRPCHandler("nw_weave","limit_speech",function(player,value)
        if player and type(value)=="boolean" then player._nw_limit_speech_enabled=value end
    end)
    if G.TheNet:IsDedicated() then return end
    M.load()
    env.AddPlayerPostInit(function(player)
        local function activated()
            if player==G.ThePlayer then M.load(announce) end
        end
        player:ListenForEvent("playeractivated",activated)
        player:DoTaskInTime(0,activated)
    end)
end
return M
