local now=10;GetTime=function() return now end
local Limits=require("nw/spell_limits")
local Trail=require("nw/trail_budget")
local Settings=require("nw/performance_settings")
local envinfo={folder_name="nw_weave_dev",locale="zh",ChooseTranslationTable=function(t) return t.zh end}
local info=assert(loadfile("mod/modinfo.lua"));setfenv(info,envinfo);info()
local configs={developer_options=true};local rows={}
for _,row in ipairs(envinfo.configuration_options) do rows[row.name]=row;configs[row.name]=row.default end
configs.developer_options=true
assert(#Settings.specs==7)
local schemas={Settings.trail_spec};for _,spec in ipairs(Settings.specs) do schemas[#schemas+1]=spec end
for _,spec in ipairs(schemas) do
    local row=assert(rows[spec.key]);assert(#spec.options==#row.options)
    for _,option in ipairs(row.options) do
        assert(spec.options[Settings.index(spec,option.data)]==option.data,"UI must expose every mod configuration value")
    end
end
-- Exercise enabling cleanup from an explicitly disabled saved configuration.
configs.boundary_cleanup=false;configs.permanent_motion_cleanup=false
Shard_GetConnectedShards=function() return {} end
local rpc,client_rpc={},{}
local install_env={GetModConfigData=function(key) return configs[key] end,
    AddShardModRPCHandler=function() end,AddPrefabPostInit=function() end,AddSimPostInit=function() end,
    AddModRPCHandler=function(_,key,fn) rpc[key]=fn end,
    AddClientModRPCHandler=function(_,key,fn) client_rpc[key]=fn end}
configs.sync_performance=false;Settings.install(install_env,{})
assert(Settings.values.sync_performance==false,"world startup opt-out must be honored")
configs.sync_performance=true;Settings.install(install_env,{})
assert(rpc.performance==Settings.handle and client_rpc.performance_result==Settings.receive)
local admin={userid="admin",IsValid=function() return true end}
local visitor={userid="visitor",IsValid=function() return true end}
local clients={admin={admin=true},visitor={admin=false}}
TheNet={GetClientTableForUser=function(_,id) return clients[id] end}
TheWorld={ismastersim=true};ThePlayer=admin;AllPlayers={admin,visitor}
MOD_RPC={nw_weave={performance=1}};CLIENT_MOD_RPC={nw_weave={performance_result=2}}
local replies,sent={},{}
SendModRPCToClient=function(_,userid,...) replies[#replies+1]={userid=userid,args={...}} end
SendModRPCToServer=function(_,...) sent[#sent+1]={...} end
local fields=require("nw/expanded_fields")
local projectile_setting
local executor=require("nw/executor");local original=executor.set_projectile_limit
executor.set_projectile_limit=function(value) projectile_setting=value;original(value) end
assert(not Settings.handle(visitor,1,"limit_projectiles",3) and Settings.values.limit_projectiles==600)
assert(Settings.handle(visitor,0,"",0))
assert(replies[#replies].args[1]==false and replies[#replies].args[6]=="STATE")
Settings.enabled=false
assert(Settings.handle(visitor,0,"",0) and Settings.handle(admin,0,"",0))
assert(replies[#replies].args[1]==false and replies[#replies].args[6]=="STATE")
assert(not Settings.handle(admin,2,"limit_projectiles",3) and Settings.values.limit_projectiles==600)
Settings.enabled=true
assert(Settings.handle(admin,0,"",0))
assert(replies[#replies].args[1]==true)
assert(not Settings.handle(admin,3,"developer_options",2))
assert(Settings.values.sync_performance==true and not Settings.bykey.sync_performance)
assert(not Settings.handle(admin,3,"sync_performance",1),"startup sync option cannot be changed through runtime RPC")
assert(not Settings.commit("sync_performance",false) and Settings.values.sync_performance==true)
assert(not Settings.handle(admin,3,"client_trail_limit",2),"local preferences must not be writable through the server RPC")
for _,index in ipairs({0,1000,1.5,math.huge}) do assert(not Settings.handle(admin,3,"limit_projectiles",index)) end
local before=#replies;Settings.handle(admin,0/0,"limit_projectiles",2);assert(#replies==before)
local watched,unwatched,bounds=0,0,0
package.loaded["nw/permanent_motion_cleanup"]={watch=function(inst) watched=watched+1;inst._nw_cleanup_state={} end,
    unwatch=function(inst) unwatched=unwatched+1;inst._nw_cleanup_state=nil end}
package.loaded["nw/world_bounds"]={watch=function(inst) bounds=bounds+1 end}
local moving={IsValid=function() return true end,_nw_stored={cleanup_absent=999},_nw_motion={}}
local bounded={IsValid=function() return true end,_nw_boundary_candidate=true}
Ents={moving=moving,bounded=bounded}
for i,spec in ipairs(Settings.specs) do
    now=now+1
    assert(Settings.handle(admin,10+i,spec.key,#spec.options))
    assert(Settings.values[spec.key]==spec.options[#spec.options])
    assert(replies[#replies].userid=="visitor" and replies[#replies].args[1]==false and replies[#replies].args[2]==Settings.snapshot(),"read-only players receive live broadcasts")
end
assert(Trail.limit==0,"server must not apply an individual client's cosmetic preference")
assert(projectile_setting==800 and require("nw/entity_limits").fields==800 and require("nw/entity_limits").permanent_fields==800)
assert(Limits.depth==30 and Limits.range==960)
assert(bounds==1 and watched==1 and Limits.boundary_cleanup and Limits.permanent_motion_cleanup)
now=now+1;assert(Settings.handle(admin,50,"permanent_motion_cleanup",1))
assert(unwatched==1 and moving._nw_stored.cleanup_absent==0)
-- New requests are checked against live admin status; cached client permission is insufficient.
clients.admin.admin=false;now=now+1
assert(not Settings.handle(admin,51,"limit_projectiles",1) and Settings.values.limit_projectiles==800)
clients.admin.admin=true
local notifications=0
local unsubscribe=Settings.subscribe(function() notifications=notifications+1 end)
assert(not Settings.allowed and not Settings.synced and not Settings.change("limit_range",1))
Settings.receive(false,Settings.snapshot(),0,"",0,"STATE")
assert(Settings.synced and not Settings.allowed and Settings.client_values.limit_projectiles==800)
assert(not Settings.change("limit_projectiles",1))
Settings.receive(true,Settings.snapshot(),0,"",0,"STATE")
assert(not Settings.change("sync_performance",1))
assert(Settings.allowed and Settings.change("limit_range",1))
local pending=Settings.pending
assert(not Settings.change("limit_range",2),"only one in-flight edit")
Settings.receive(true,Settings.snapshot(),pending.id+1,"limit_range",1,"OK")
assert(Settings.pending)
Settings.receive(true,Settings.snapshot(),pending.id,"limit_range",1,"OK")
assert(not Settings.pending)
assert(Settings.change("limit_range",2))
Settings.receive(false,Settings.snapshot(),Settings.pending.id,"limit_range",2,"DENIED")
assert(not Settings.allowed and not Settings.pending and Settings.synced)
Settings.receive(true,Settings.snapshot(),0,"",0,"STATE")
assert(Settings.change("limit_range",1));now=now+6;Settings.poll()
assert(not Settings.pending and Settings.status=="TIMEOUT")
local previous=Settings.client_values.limit_range
Settings.receive(true,"1,2,3",0,"",0,"STATE")
assert(Settings.client_values.limit_range==previous,"malformed state must be ignored atomically")
unsubscribe();before=notifications;Settings.receive(false,Settings.snapshot(),0,"",0,"STATE")
assert(notifications==before)
-- A remote peer updates compiler limits from the authoritative shard snapshot.
TheWorld.ismastersim=false;Settings.values.limit_depth=0;Limits.depth=0
Settings.receive(false,"11,11,11,6,31,2,1",0,"",0,"STATE")
assert(Limits.depth==30 and Trail.limit==0 and not Settings.allowed)
print("performance settings: 7 server schemas plus personal trails, public queries and broadcasts, server admin/developer edit gates, validated RPC, runtime limits, existing cleanup, local trails, acknowledgement and timeout")
