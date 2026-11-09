-- Exercise actual shard handlers with isolated copies of settings per world.
local Cluster=require("nw/performance_cluster")
local nodes,active={},nil
SHARDID={MASTER="1"}
local now=100;GetTime=function() return now end
TheNet={GetClientTableForUser=function(_,id) return {admin=id=="admin"} end}
Shard_IsWorldAvailable=function(id) return nodes[tostring(id)]~=nil end
Shard_GetConnectedShards=function() local result={};for id in pairs(nodes) do if id~=active then result[id]={} end end;return result end
local function use(id)
    active=id;TheWorld=nodes[id].world;AllPlayers=nodes[id].players
end
SHARD_MOD_RPC={nw_weave={performance_query="performance_query",performance_edit="performance_edit",performance_state="performance_state"}}
local events={}
SendModRPCToShard=function(name,target,...)
    events[#events+1]={source=active,target=tostring(target),name=name,args={...}}
end
local function drain()
    local count=0
    while #events>0 do
        count=count+1;assert(count<100,"shard sync must not echo forever")
        local e=table.remove(events,1);use(e.target);nodes[e.target].handlers[e.name](e.source,unpack(e.args))
    end
end
for _,id in ipairs({"1","2","3"}) do
    package.loaded["nw/performance_settings"]=nil
    local S=require("nw/performance_settings")
    for _,spec in ipairs(S.specs) do S.values[spec.key]=spec.options[1] end
    S.values.sync_performance=true;S.enabled=true
    local player={userid="admin",IsValid=function() return true end}
    nodes[id]={settings=S,handlers={},players={player},world={ismastersim=true,ismastershard=id=="1"},player=player,replies={}}
    S.send=function(_,request,key,index,code) nodes[id].replies[#nodes[id].replies+1]=code end
    S.broadcast=function() end
    use(id)
    Cluster.install({AddShardModRPCHandler=function(_,name,fn) nodes[id].handlers[name]=fn end,AddPrefabPostInit=function() end,AddSimPostInit=function() end},{},S)
end
local primary,caves,third=nodes["1"].settings,nodes["2"].settings,nodes["3"].settings
use("1");primary.commit("limit_projectiles",600);drain()
assert(caves.values.limit_projectiles==600 and third.values.limit_projectiles==600)
-- An authenticated edit in a secondary is committed by the primary and fanned out.
use("2");assert(caves.handle(nodes["2"].player,1,"limit_projectiles",4));drain()
assert(primary.values.limit_projectiles==100 and caves.values.limit_projectiles==100 and third.values.limit_projectiles==100)
assert(nodes["2"].replies[#nodes["2"].replies]=="OK")
-- Simulate each startup configuration; the switch is not a runtime RPC option.
use("3");third.values.sync_performance=false;third.commit("limit_projectiles",800)
use("1");primary.commit("limit_projectiles",200);drain()
assert(caves.values.limit_projectiles==200 and third.values.limit_projectiles==800 and not third.values.sync_performance)
use("3");third.values.sync_performance=true;drain();assert(third.values.limit_projectiles==800,"enabling does not replay old changes")
-- A primary that opts out still relays for other opted-in worlds, but keeps its own values.
use("1");primary.values.sync_performance=false
use("2");now=now+1
assert(caves.handle(nodes["2"].player,2,"limit_projectiles",8));drain()
assert(primary.values.limit_projectiles==200 and caves.values.limit_projectiles==500 and third.values.limit_projectiles==500)
use("1");primary.values.sync_performance=true
assert(primary.values.limit_projectiles==200,"primary opt-in also applies only future edits")
-- A later runtime edit synchronizes again. No old values are replayed on startup.
use("1");primary.commit("limit_projectiles",400);drain()
assert(caves.values.limit_projectiles==400 and third.values.limit_projectiles==400)
use("2");nodes["2"].handlers.performance_state("3",third.snapshot(),"",0,"",0,"STATE")
assert(caves.values.limit_projectiles==400)
-- Ordinary players cannot forward writes, even when the local UI is bypassed.
use("2");local visitor={userid="visitor",IsValid=function() return true end}
assert(not caves.handle(visitor,3,"limit_projectiles",1) and #events==0)
print("performance cluster: actual RPC routes, primary fanout, secondary writes, per-world opt-out, primary opt-out with continued relay, no stale replay, source validation and visitor denial")
