local C=require("nw/constants/cast_binding")
local Key=require("nw/cast_key")
local M={}
local installed,G=false,nil
local current,epoch,serial=nil,0,0
local state,waiting,query_task,write_task=nil,nil,nil,nil
local listeners={}
local function integer(value)
    return type(value)=="number" and value>=0 and value<=C.max_integer and value==math.floor(value)
end
local function cancel(task) if task then task:Cancel() end end
local function notify()
    if current and current==G.ThePlayer then current:PushEvent("nw_cast_binding_dirty") end
    for callback in pairs(listeners) do callback() end
end
local function local_state()
    return current and current==G.ThePlayer and current:IsValid() and state or nil
end
local function component(player)
    return player and player.components and player.components.nw_castbinding
end
function M.ready() return not installed or local_state()~=nil end
function M.get(player)
    if not installed then return C.default end
    if G.TheWorld and G.TheWorld.ismastersim then
        local c=component(player or G.ThePlayer)
        return c and c:Get() or nil
    end
    local s=local_state()
    return s and (s.override or s.default) or nil
end
function M.get_default()
    if not installed then return C.default end
    local s=local_state();return s and s.default or nil
end
function M.get_override()
    local s=installed and local_state();return s and s.override or nil
end
function M.pending() return waiting end
function M.subscribe(callback)
    listeners[callback]=true
    return function() listeners[callback]=nil end
end
function M.query()
    if not installed or not current or current~=G.ThePlayer or not current:IsValid() then return false end
    local player,request=current,epoch
    G.SendModRPCToServer(G.MOD_RPC.nw_weave.cast_binding_query,request)
    if not state and not query_task then
        query_task=player:DoTaskInTime(C.retry_delay,function()
            query_task=nil
            if current==player and epoch==request then M.query() end
        end)
    end
    return true
end
function M.set(value)
    local s=installed and local_state()
    if not s or waiting or (value~=nil and not Key.valid(value)) then return false end
    serial=serial%C.max_integer+1
    local request,player,lifecycle=serial,current,epoch
    waiting={id=request,value=value}
    write_task=player:DoTaskInTime(C.request_timeout,function()
        write_task=nil
        if current==player and epoch==lifecycle and waiting and waiting.id==request then
            waiting=nil;notify();M.query()
        end
    end)
    G.SendModRPCToServer(G.MOD_RPC.nw_weave.cast_binding_set,epoch,s.token,s.revision,request,value or "")
    notify()
    return true
end
function M.install(env,globals)
    installed,G=true,globals
    local configured=env.GetModConfigData("cast_key")
    if not Key.valid(configured) then configured=C.default end
    local shared_default,default_task,default_request=nil,nil,0
    local players,token_serial={},0
    local function primary() return G.TheWorld and G.TheWorld.ismastershard~=false end
    local function initialize(player)
        local c=component(player)
        if c then c:Initialize(primary() and configured or shared_default) end
    end
    local function query_default()
        if not G.TheWorld or not G.TheWorld.ismastersim or primary() or shared_default then return end
        if default_request==0 then default_request=1 end
        local master=tostring(G.SHARDID.MASTER)
        if G.Shard_IsWorldAvailable(master) then
            G.SendModRPCToShard(G.SHARD_MOD_RPC.nw_weave.cast_binding_default_query,master,default_request)
        end
        if not shared_default and not default_task then
            default_task=G.TheWorld:DoTaskInTime(C.retry_delay,function() default_task=nil;query_default() end)
        end
    end
    env.AddSimPostInit(query_default)
    env.AddShardModRPCHandler("nw_weave","cast_binding_default_query",function(source,request)
        if primary() and integer(request) and request>0 and G.Shard_IsWorldAvailable(tostring(source)) then
            G.SendModRPCToShard(G.SHARD_MOD_RPC.nw_weave.cast_binding_default_state,tostring(source),request,configured)
        end
    end)
    env.AddShardModRPCHandler("nw_weave","cast_binding_default_state",function(source,request,value)
        if primary() or tostring(source)~=tostring(G.SHARDID.MASTER) or request~=default_request
            or not Key.valid(value) or not G.Shard_IsWorldAvailable(tostring(source)) then return end
        shared_default=value;cancel(default_task);default_task=nil
        for player in pairs(players) do if player:IsValid() then initialize(player) end end
    end)
    local function send(player,lifecycle,request,code)
        local c=component(player)
        if c and c.default and player.userid then
            G.SendModRPCToClient(G.CLIENT_MOD_RPC.nw_weave.cast_binding_state,player.userid,
                lifecycle,c.token,c.revision,c.default,c.override or "",request,code)
        end
    end
    local function valid_player(player)
        return G.TheWorld and G.TheWorld.ismastersim and player and player:IsValid() and player.userid and component(player)
    end
    env.AddModRPCHandler("nw_weave","cast_binding_query",function(player,lifecycle)
        if not valid_player(player) or not integer(lifecycle) or lifecycle==0 then return end
        initialize(player);query_default();send(player,lifecycle,0,"STATE")
    end)
    env.AddModRPCHandler("nw_weave","cast_binding_set",function(player,lifecycle,token,revision,request,value)
        if not valid_player(player) or not integer(lifecycle) or lifecycle==0 or not integer(revision)
            or not integer(request) or request==0 or type(token)~="string" or #token>C.max_token_length
            or (value~="" and not Key.valid(value)) then return end
        local c=component(player)
        local ok=token==c.token and c:Set(value~="" and value or nil,revision)
        send(player,lifecycle,request,ok and "OK" or "STALE")
    end)
    env.AddClientModRPCHandler("nw_weave","cast_binding_state",function(lifecycle,token,revision,default,override,request,code)
        if not current or current~=G.ThePlayer or not current:IsValid() or lifecycle~=epoch
            or type(token)~="string" or #token==0 or #token>C.max_token_length or not integer(revision)
            or not Key.valid(default) or (override~="" and not Key.valid(override)) or not integer(request)
            or (code~="STATE" and code~="OK" and code~="STALE") then return end
        if state and (state.token~=token or revision<state.revision) then return end
        state={token=token,revision=revision,default=default,override=override~="" and override or nil}
        cancel(query_task);query_task=nil
        if waiting and waiting.id==request then cancel(write_task);write_task=nil;waiting=nil end
        notify()
    end)
    env.AddPlayerPostInit(function(player)
        if G.TheWorld.ismastersim then
            player:AddComponent("nw_castbinding")
            local c=component(player)
            token_serial=token_serial+1
            c.token=tostring(G.TheShard:GetShardId())..":"..tostring(player.GUID)..":"..token_serial
            players[player]=true
            player:ListenForEvent("onremove",function() players[player]=nil end)
            -- Saved components load before this task; never replace a migrated default.
            player:DoTaskInTime(0,function() initialize(player);query_default() end)
            local save,load=player.SaveForReroll,player.LoadForReroll
            player.SaveForReroll=function(self,...)
                local data=save and save(self,...) or {};data=data or {}
                data.nw_castbinding=component(self):OnSave()
                return data
            end
            player.LoadForReroll=function(self,data,...)
                if load then load(self,data,...) end
                component(self):OnLoad(data and data.nw_castbinding)
            end
        end
        local function deactivate()
            if current~=player then return end
            cancel(query_task);cancel(write_task)
            query_task,write_task,current,state,waiting=nil,nil,nil,nil,nil
            for callback in pairs(listeners) do callback() end
        end
        local function activate()
            if player~=G.ThePlayer then return end
            if current~=player then
                cancel(query_task);cancel(write_task)
                query_task,write_task,state,waiting=nil,nil,nil,nil
                current=player;epoch=epoch%C.max_integer+1
                notify()
            end
            M.query()
        end
        player:ListenForEvent("playeractivated",activate)
        player:ListenForEvent("playerdeactivated",deactivate)
        player:ListenForEvent("onremove",deactivate)
        player:DoTaskInTime(0,activate)
    end)
end
return M
