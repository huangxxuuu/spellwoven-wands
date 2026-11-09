-- Everyone may read shard settings; only developer-mode admins may change them.
-- Personal trail preferences are handled locally, outside the server RPC.
local M={enabled=false,values={},allowed=false,synced=false,client_values={},serial=0,listeners={}}
local Limits=require("nw/spell_limits")
local Trail=require("nw/trail_budget")
local function L(zh,en) return require("nw/locale").language=="en" and en or zh end
M.text=L
local bool={false,true}
local depth={0};for i=1,30 do depth[#depth+1]=i end
local live_options={0,25,50,100,200,300,400,500,600,700,800}
M.trail_spec={key="client_trail_limit",zh="客户端尾焰总上限",en="Client trail segment limit",options=Trail.options,
        tip={"默认1700。仅本机；他人达到总额的75%时跳过，自己达到总额时跳过。已有尾段自然消散。", "Default: 1700. This client only. Others stop at 75% of the shared total; you stop at 100%. Existing tails fade naturally."}}
M.specs={
    {key="limit_projectiles",zh="玩家活动弹体上限",en="Live projectiles per player",options=live_options,
        tip={"默认600。每次实际生成前检查，满额则跳过该实体；不预留载荷、不禁止整次施法，无额外固定分片上限。", "Default: 600. Checks each actual emission; skips that entity at capacity. No payload reservations, whole-cast rejection or extra fixed shard cap."}},
    {key="limit_fields",zh="玩家限时驻留实体上限",en="Timed spell entities per player",options=live_options,
        tip={"默认200。哨株、雷云、残光、星体等限时驻留法术共享额度。满额跳过新增，已有实体自然结束。", "Default: 200. Sentries, clouds, lingering lights, stars and other timed placements share a budget. Skip new spawns at capacity; existing entities expire normally."}},
    {key="limit_permanent_fields",zh="玩家不限时驻留实体上限",en="Permanent spell entities per player",options=live_options,
        tip={"默认100。晶体和载荷卵共用独立额度。满额后静默移除该玩家最早创建的实体，再生成新的；不引爆、不释放载荷。读档保留创建顺序。", "Default: 100. Crystals and payload eggs share a separate budget. At capacity, silently remove this player's oldest placement before spawning a new one, without detonation or payload release. Saves retain creation order."}},
    {key="limit_range",zh="子弹累计射程限制",en="Projectile travel limit",options={0,60,120,240,480,960},
        tip={"下一次弹体更新起生效；累计路程超限的弹体按原规则结束。旧30单位设置迁移为60。", "Effective on the next projectile update; projectiles over the travel limit end normally. Legacy 30 migrates to 60."}},
    {key="limit_depth",zh="载荷嵌套层数限制",en="Payload nesting limit",options=depth,
        tip={"根法术不计层数，实际触发时超过层数则跳过该载荷；不禁止整次施法，不重新编排已释放弹体。", "The root does not count. Over-depth payloads are skipped when triggered, without rejecting the cast or recompiling released projectiles."}},
    {key="boundary_cleanup",zh="越界法术实体清理",en="Out-of-bounds cleanup",options=bool,
        tip={"开启后也检查已存在的本Mod法术实体；清理不释放载荷。", "Also checks existing registered spell entities when enabled. Cleanup does not release payloads."}},
    {key="permanent_motion_cleanup",zh="永久移动实体自动清理",en="Permanent motion cleanup",options=bool,
        tip={"超过20个时清理连续休眠16分钟的永久移动晶体和卵。静止机关不计入；关闭时停止监测。", "Above 20, removes permanent moving crystals and eggs asleep for 16 minutes. Static traps are excluded; disabling stops monitoring."}},

}
M.bykey={};for _,s in ipairs(M.specs) do M.bykey[s.key]=s end
function M.index(spec,value)
    for i,v in ipairs(spec.options) do if v==value then return i end end
    return 1
end
function M.option_text(value)
    if type(value)=="boolean" then return value and L("开启","On") or L("关闭","Off") end
    return value==0 and L("不限","Unlimited") or tostring(value)
end
local function integer(n) return type(n)=="number" and n==math.floor(n) and n>=0 and n<=2147483647 end
function M.authorized(player)
    if not M.enabled or not player or not player:IsValid() or not player.userid then return false end
    local client=TheNet:GetClientTableForUser(player.userid)
    return client~=nil and client.admin==true
end
local function apply(key,value)
    if M.values[key]==value then return end
    M.values[key]=value
    if key=="limit_projectiles" then require("nw/executor").set_projectile_limit(value)
    elseif key=="limit_fields" then require("nw/entity_limits").configure("fields",value)
    elseif key=="limit_permanent_fields" then require("nw/entity_limits").configure("permanent_fields",value)
    else Limits[key:gsub("^limit_","")]=value end
    if not TheWorld or not TheWorld.ismastersim then return true end
    if key=="boundary_cleanup" and value then
        local candidates={}
        for _,inst in pairs(Ents or {}) do
            if inst._nw_boundary_candidate and inst:IsValid() then candidates[#candidates+1]=inst end
        end
        for _,inst in ipairs(candidates) do require("nw/world_bounds").watch(inst) end
    elseif key=="permanent_motion_cleanup" then
        local Cleanup=require("nw/permanent_motion_cleanup")
        local candidates={}
        for _,inst in pairs(Ents or {}) do
            if inst:IsValid() and (inst._nw_cleanup_state or inst._nw_stored and inst._nw_motion) then
                candidates[#candidates+1]=inst
            end
        end
        for _,inst in ipairs(candidates) do
            if value then Cleanup.watch(inst)
            elseif inst._nw_cleanup_state then
                if inst._nw_stored then inst._nw_stored.cleanup_absent=0 end
                Cleanup.unwatch(inst)
            end
        end
    end
    return true
end
function M.snapshot()
    local result={}
    for i,s in ipairs(M.specs) do result[i]=tostring(M.index(s,M.values[s.key])) end
    return table.concat(result,",")
end
function M.send(player,id,key,index,code)
    SendModRPCToClient(CLIENT_MOD_RPC.nw_weave.performance_result,player.userid,
        M.authorized(player),M.snapshot(),id,key,index,code)
end
function M.broadcast()
    for _,p in ipairs(AllPlayers or {}) do if p.userid and p:IsValid() then M.send(p,0,"",0,"STATE") end end
end
function M.commit(key,value,from_sync)
    if not M.bykey[key] or M.bykey[key].options[M.index(M.bykey[key],value)]~=value then return false end
    if apply(key,value) then
        if M.cluster and not from_sync then M.cluster.changed(key) end
    end
    return true
end
function M.decode(encoded)
    if type(encoded)~="string" or #encoded>128 then return end
    local values,count={},0
    for token in encoded:gmatch("[^,]+") do
        count=count+1
        local spec=M.specs[count];local n=tonumber(token)
        if not spec or not integer(n) or spec.options[n]==nil then return end
        values[spec.key]=spec.options[n]
    end
    if count==#M.specs then return values end
end
function M.handle(player,id,key,index)
    if not player or not player.userid or not integer(id) or type(key)~="string" or #key>40 or not integer(index) then return end
    if not player:IsValid() then return end
    if key=="" then M.send(player,id,key,index,"STATE");return true end
    if not M.authorized(player) then M.send(player,id,key,index,"DENIED");return false end
    local spec=M.bykey[key]
    if not spec or spec.options[index]==nil then M.send(player,id,key,index,"INVALID");return false end
    if (player._nw_performance_next or 0)>GetTime() then M.send(player,id,key,index,"BUSY");return false end
    player._nw_performance_next=GetTime()+.1
    if M.cluster and M.cluster.route(player,id,key,index) then return true end
    M.commit(key,spec.options[index])
    M.send(player,id,key,index,"OK")
    for _,p in ipairs(AllPlayers or {}) do if p~=player and p.userid then M.send(p,0,"",0,"STATE") end end
    return true
end
local function notify()
    for callback in pairs(M.listeners) do callback() end
end
function M.receive(allowed,encoded,id,key,index,code)
    local values=M.decode(encoded)
    if not values then return end
    M.allowed=allowed==true;M.synced=true
    for _,spec in ipairs(M.specs) do
        M.client_values[spec.key]=values[spec.key]
        if TheWorld and not TheWorld.ismastersim then apply(spec.key,values[spec.key]) end
    end
    local pending=M.pending
    if pending and pending.id==id and pending.key==key and pending.index==index then
        M.pending=nil;M.status=code
    end
    if not M.allowed then M.pending=nil;M.status=nil end
    notify()
end
function M.query()
    if not ThePlayer then return end
    SendModRPCToServer(MOD_RPC.nw_weave.performance,0,"",0)
end
function M.change(key,index)
    local spec=M.bykey[key]
    if not M.synced or not M.allowed or M.pending or not spec or not integer(index) or spec.options[index]==nil then return false end
    M.serial=M.serial%2147483647+1
    M.pending={id=M.serial,key=key,index=index,time=GetTime()};M.status="PENDING"
    SendModRPCToServer(MOD_RPC.nw_weave.performance,M.serial,key,index)
    notify();return true
end
function M.poll()
    if M.pending and GetTime()-M.pending.time>5 then M.pending=nil;M.status="TIMEOUT";notify() end
    M.query()
end
function M.value(spec) return M.client_values[spec.key] end
function M.subscribe(callback)
    M.allowed=false;M.synced=false;M.client_values={};M.pending=nil;M.status=nil;M.listeners[callback]=true
    M.query()
    return function() M.listeners[callback]=nil end
end
function M.install(env,G)
    M.enabled=env.GetModConfigData("developer_options")==true
    -- Startup-only world option, deliberately excluded from runtime RPC schemas.
    M.values.sync_performance=env.GetModConfigData("sync_performance")~=false
    for _,s in ipairs(M.specs) do
        local value=env.GetModConfigData(s.key)
        if s.key=="limit_projectiles" and type(value)=="boolean" then value=value and 200 or 0 end
        if s.key=="limit_range" and value==30 then value=60 end
        M.values[s.key]=s.options[M.index(s,value)]
    end
    env.AddModRPCHandler("nw_weave","performance",M.handle)
    env.AddClientModRPCHandler("nw_weave","performance_result",M.receive)
    require("nw/performance_cluster").install(env,G,M)
end
return M
