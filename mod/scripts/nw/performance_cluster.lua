-- Runtime-only opt-in synchronization. The primary orders and relays edits;
-- opting out also protects the primary's own values without disabling relaying.
local M={}
function M.install(env,G,S)
    local C={}
    S.cluster=C
    local function primary() return TheWorld and TheWorld.ismastershard~=false end
    local function masterid() return tostring(SHARDID.MASTER) end
    local function connected(id) return Shard_IsWorldAvailable(tostring(id)) end
    local function rpc(name,id,...)
        SendModRPCToShard(SHARD_MOD_RPC.nw_weave[name],tostring(id),...)
    end
    local function snapshot(changes)
        local values={}
        for i,spec in ipairs(S.specs) do
            values[i]=tostring(changes[spec.key]~=nil and S.index(spec,changes[spec.key]) or 0)
        end
        return table.concat(values,",")
    end
    local function decode(encoded)
        if type(encoded)~="string" or #encoded>128 then return end
        local values,count={},0
        for token in encoded:gmatch("[^,]+") do
            count=count+1
            local spec=S.specs[count];local index=tonumber(token)
            if not spec or not index or index~=math.floor(index) or index<0 or index>#spec.options then return end
            if index>0 then
                if spec.key=="sync_performance" then return end
                values[spec.key]=spec.options[index]
            end
        end
        if count==#S.specs then return values end
    end
    local function apply_shared(values)
        if not S.values.sync_performance then return end
        for key,value in pairs(values) do S.commit(key,value,true) end
    end
    local function publish(id,changes,userid,request,key,index,code)
        rpc("performance_state",id,snapshot(changes),userid or "",request or 0,key or "",index or 0,code or "STATE")
    end
    local function relay(key,value)
        local changes={[key]=value}
        apply_shared(changes)
        for id in pairs(Shard_GetConnectedShards()) do publish(id,changes) end
    end
    function C.changed(key)
        if S.values.sync_performance and key~="sync_performance" and primary() then relay(key,S.values[key]) end
    end
    function C.route(player,id,key,index)
        if primary() or key=="sync_performance" or not S.values.sync_performance then return false end
        if not connected(masterid()) then S.send(player,id,key,index,"UNAVAILABLE");return true end
        rpc("performance_edit",masterid(),player.userid,id,key,index)
        return true
    end
    local next_edit={}
    env.AddShardModRPCHandler("nw_weave","performance_edit",function(source,userid,id,key,index)
        if not primary() or not connected(source) or type(userid)~="string" or #userid>128
            or type(id)~="number" or id~=math.floor(id) or id<0 or id>2147483647 then return end
        local spec=type(key)=="string" and S.bykey[key]
        if not spec or key=="sync_performance" or type(index)~="number" or spec.options[index]==nil then return end
        -- Only a server can send this RPC; it already checked its current player,
        -- developer option, admin permission and opt-in switch before forwarding.
        local code
        if (next_edit[userid] or 0)>GetTime() then code="BUSY"
        else
            next_edit[userid]=GetTime()+.1
            relay(key,spec.options[index]);S.broadcast();code="OK"
        end
        publish(source,code=="OK" and {[key]=spec.options[index]} or {},userid,id,key,index,code)
    end)
    env.AddShardModRPCHandler("nw_weave","performance_state",function(source,encoded,userid,id,key,index,code)
        if primary() or tostring(source)~=masterid() or not connected(source) then return end
        local values=decode(encoded)
        if not values then return end
        -- Opted-out worlds ignore every value, including delayed broadcasts.
        apply_shared(values)
        S.broadcast()
        if userid~="" then
            for _,p in ipairs(AllPlayers or {}) do
                if p.userid==userid and p:IsValid() then S.send(p,id,key,index,code);break end
            end
        end
    end)
    -- No startup replay or saved snapshots: restarting a world restores its
    -- configured values until a new runtime edit is received.

end
return M
