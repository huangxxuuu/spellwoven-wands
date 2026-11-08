-- Persist only on this client. The server holds an ephemeral preference per player.
local M={key="nw_weave_cast_direction_v1",sync_interval=60,change_delay=1}
local mode="target"
local applied_mode="target"
local sync_current,schedule_sync
local loaded,loading,revision=false,false,0
local waiters={}
local writing,queued=false,nil

local function valid(value) return value=="target" or value=="mouse" end
function M.get() return mode end
function M.load(callback)
    if loaded then if callback then callback(mode) end;return end
    if callback then waiters[#waiters+1]=callback end
    if loading then return end
    loading=true
    local at=revision
    TheSim:GetPersistentString(M.key,function(ok,value)
        if at==revision and ok and valid(value) then mode=value end
        loaded,loading=true,false
        local callbacks=waiters;waiters={}
        for _,fn in ipairs(callbacks) do fn(mode) end
    end,false)
end
local function flush()
    if writing or not queued then return end
    writing=true
    local value=queued;queued=nil
    TheSim:SetPersistentString(M.key,value,false,function()
        writing=false;flush()
    end)
end
function M.set(value)
    if not valid(value) then return false end
    revision=revision+1;mode=value;loaded=true
    queued=value;flush()
    if schedule_sync then schedule_sync() else applied_mode=mode end
    return true
end
function M.uses_mouse(player)
    if TheWorld and TheWorld.ismastersim then
        return player~=nil and player._nw_cast_direction=="mouse" and player._nw_cast_mouse_input==true
    end
    local pc=player and player.components and player.components.playercontroller
    return applied_mode=="mouse" and player==ThePlayer and pc and pc:UsingMouse() or false
end

local function ensure_picker(player)
    local picker=player.components and player.components.playeractionpicker
    if picker then require("nw/cast_action").install_picker(picker) end
end
function M.receive(player,value,mouse_input)
    if not player or not valid(value) or type(mouse_input)~="boolean" then return false end
    player._nw_cast_direction=value
    player._nw_cast_mouse_input=mouse_input
    ensure_picker(player)
    return true
end
function M.install(env,G)
    env.AddModRPCHandler("nw_weave","cast_direction",M.receive)
    env.AddComponentPostInit("playeractionpicker",function(picker)
        require("nw/cast_action").install_picker(picker)
    end)
    -- Characters can reset their action callbacks when changing forms. Reattach
    -- the supported callback when a wand is equipped or a preference arrives.
    env.AddPlayerPostInit(function(player)
        player:ListenForEvent("equip",function() ensure_picker(player) end)
    end)
    if G.TheNet:IsDedicated() then return end

    local current,task,pending
    local function stop(player)
        if current~=player then return end
        if task then task:Cancel();task=nil end
        if pending then pending:Cancel();pending=nil end
        current=nil
    end
    local function heartbeat(player)
        if task then task:Cancel() end
        task=player:DoPeriodicTask(M.sync_interval,function()
            if current==player and player==G.ThePlayer then sync_current() else stop(player) end
        end)
    end
    sync_current=function()
        local player=current
        -- An entry/load callback or heartbeat must not bypass the last change's delay.
        if pending or not loaded or not player or player~=G.ThePlayer or not player:IsValid() then return end
        local pc=player.components and player.components.playercontroller
        if not pc then return end
        ensure_picker(player)
        local mouse_input=pc:UsingMouse()==true
        if G.TheWorld and G.TheWorld.ismastersim then
            -- A listen host shares the server process; apply the same validation.
            M.receive(player,mode,mouse_input)
        else
            G.SendModRPCToServer(G.MOD_RPC.nw_weave.cast_direction,mode,mouse_input)
        end
        applied_mode=mode
        -- Keep the fallback one minute after the last send, including an edit.
        heartbeat(player)
    end
    schedule_sync=function()
        local player=current
        if not player or player~=G.ThePlayer or not player:IsValid() then return end
        if pending then pending:Cancel() end
        local at=revision
        pending=player:DoTaskInTime(M.change_delay,function()
            if current~=player or at~=revision then return end
            pending=nil
            sync_current()
        end)
    end
    env.AddPlayerPostInit(function(player)
        local function activate()
            if player~=G.ThePlayer then return end
            if current~=player then
                if current then stop(current) end
                current=player
                heartbeat(player)
            end
            M.load(function() if current==player then sync_current() end end)
        end
        player:ListenForEvent("playeractivated",activate)
        player:ListenForEvent("playerdeactivated",function() stop(player) end)
        player:ListenForEvent("onremove",function() stop(player) end)
        player:DoTaskInTime(0,activate)
    end)
end
return M
