local Mode=require("nw/cast_mode")
local Cast=require("nw/cast_action")
EQUIPSLOTS={HANDS="hands"};ACTIONS={NW_CAST={}}
local tick,now=10,1
GetTick=function() return tick end
GetTime=function() return now end
local config=true
local server_rpc,client_rpc,init,post,requests,sends={},{},nil,nil,{},{}
local G={MOD_RPC={nw_weave={cast_mode_query="query"}},CLIENT_MOD_RPC={nw_weave={cast_mode_state="state"}}}
local env={GetModConfigData=function(key) assert(key=="instant_cast");return config end,
    AddModRPCHandler=function(_,name,fn) server_rpc[name]=fn end,
    AddClientModRPCHandler=function(_,name,fn) client_rpc[name]=fn end,
    AddSimPostInit=function(fn) init=fn end,AddPlayerPostInit=function(fn) post=fn end}
G.SendModRPCToServer=function(_,request) requests[#requests+1]=request end
-- Deliberately model a lossy false argument at the native boundary. This is a
-- regression fixture, not a claim that Lua can execute the engine's codec.
local function wire_value(value) if value==false then return nil end;return value end
G.SendModRPCToClient=function(_,userid,value,request) sends[#sends+1]={userid,wire_value(value),request} end
local function world(master)
    TheWorld={ismastersim=master,Map={IsPassableAtPoint=function() return true end}}
    G.TheWorld=TheWorld
end
world(true);Mode.install(env,G,ACTIONS.NW_CAST);init()
assert(Mode.ready() and Mode.enabled() and ACTIONS.NW_CAST.instant)
local tags,sgtags={},{}
local cancast,netready,netcast=true,true,true
local count,previews,faces=0,0,0
local posecasts=0
local plan={}
local wand={components={nw_wand={}},_nw_ready={value=function() return netready end},
    _nw_cancast={value=function() return netcast end},HasTag=function(_,tag) return tag=="nw_wand" end}
local equipped=wand
local inv={GetEquippedItem=function() return equipped end}
local combatcool=false
local combat={InCooldown=function() return combatcool end}
local enabled,busy=true,false
local player={userid="test",components={inventory=inv,combat=combat,
    playercontroller={IsEnabled=function() return enabled end,IsBusy=function() return busy end}},
    replica={inventory=inv,combat=combat},Transform={GetWorldPosition=function() return 0,0,0 end},
    HasTag=function(_,tag) return tags[tag] end,IsValid=function() return true end,
    sg={currentstate={name="idle"},HasStateTag=function(_,tag) return sgtags[tag] end},
    FacePoint=function(_,x,y,z) assert(x==4 and z==0);faces=faces+1 end,
    PerformPreviewBufferedAction=function() previews=previews+1 end}
local ensures=0
player._nw_pose_ensure=function(doer,item)
    assert(doer==player and item==wand)
    if doer._nw_editing or (doer._nw_edit_until or 0)>now then return false end
    ensures=ensures+1
    return true
end
player._nw_pose_on_cast=function(doer,item)
    assert(doer==player and item==wand and not doer._nw_instant_casting)
    assert(doer._nw_instant_cast_tick==tick,"success is deduplicated before presentation")
    posecasts=posecasts+1
end
local pos={x=4,z=0}
local cast_result=true
function wand.components.nw_wand:CanCast(_,prepared)
    return cancast and (not prepared or prepared==plan),nil,plan
end
function wand.components.nw_wand:Cast(doer,point,prepared)
    assert(prepared==plan and point==pos)
    assert(not Cast.available(equipped,doer,pos),"nested execution must be rejected")
    if cast_result then count=count+1 end
    return cast_result,"test"
end
local function action()
    return {doer=player,invobject=equipped,point=pos,action=ACTIONS.NW_CAST,
        GetActionPoint=function(self) return self.point end,SetActionPoint=function(self,p) self.point=p end}
end
assert(Cast.perform(action()) and count==1)
assert(posecasts==1,"one cast produces one pose impulse regardless of its payload")
assert(not Cast.perform(action()) and count==1)
assert(posecasts==1,"a rejected duplicate cannot produce recoil")
local other={components=wand.components,HasTag=wand.HasTag,_nw_ready=wand._nw_ready,_nw_cancast=wand._nw_cancast}
equipped=other;assert(not Cast.perform(action()),"switching wand cannot bypass player tick limit")
equipped=wand;tick=tick+1
assert(Cast.perform(action()) and count==2)
tick=tick+1;cast_result=false
assert(not Cast.perform(action()))
assert(posecasts==2,"failed casts cannot produce recoil")
cast_result=true;assert(Cast.perform(action()) and count==3,"failed cast must not consume successful tick")
assert(posecasts==3)
tick=tick+1
for _,tag in ipairs({"busy","attack","moving","sleeping","frozen","dead","nointerrupt"}) do
    sgtags[tag]=true;assert(not Cast.available(wand,player,pos) and not Cast.perform(action()),tag);sgtags[tag]=nil
    tags[tag]=true;assert(not Cast.available(wand,player,pos),tag);tags[tag]=nil
end
enabled=false;assert(not Cast.available(wand,player,pos));enabled=true
busy=true;assert(not Cast.perform(action()));busy=false
tags.playerghost=true;assert(not Cast.perform(action()));tags.playerghost=nil
player._nw_editing=true;assert(not Cast.perform(action()));player._nw_editing=nil
player._nw_edit_until=now+1;assert(not Cast.perform(action()));player._nw_edit_until=nil
combatcool=true;assert(not Cast.perform(action()));combatcool=false
cancast=false;assert(not Cast.perform(action()));cancast=true
local stale=action();Cast.prepare(stale);plan={};assert(not Cast.perform(stale),"prepared plan must be revalidated")
local invalid=action();invalid.point={x=0/0,z=0};assert(not Cast.perform(invalid))
invalid=action();invalid.point={x=31,z=0};assert(not Cast.perform(invalid))
local prepared=action();Cast.prepare(prepared);sgtags.frozen=true;assert(not Cast.perform(prepared));sgtags.frozen=nil
prepared=action();Cast.prepare(prepared);combatcool=true;assert(not Cast.perform(prepared));combatcool=false
assert(posecasts==3,"mana, cooldown and state failures cannot kick the pose")
for _,name in ipairs({"chop","mine","emote","hiding","mounted","unknown_idle"}) do
    player.sg.currentstate.name=name;sgtags.idle=true
    local before=ensures
    assert(not Cast.available(wand,player,pos) and not Cast.perform(action()),name)
    assert(ensures==before,"illegal native states must not trigger pose entry")
end
player.sg.currentstate.name="idle";sgtags.idle=nil
local before=ensures
local invalid_pose=action();invalid_pose.point={x=math.huge,z=0};assert(not Cast.perform(invalid_pose))
invalid_pose=action();invalid_pose._nw_done=true;assert(not Cast.perform(invalid_pose))
assert(ensures==before,"malformed or already completed actions cannot trigger pose entry")
local ensure=player._nw_pose_ensure
player._nw_pose_ensure=function() return false end
assert(not Cast.perform(action()),"failed authoritative pose entry must prevent the on-foot cast")
player._nw_pose_ensure=ensure
server_rpc.cast_mode_query(player,5);assert(sends[1][2]==1 and sends[1][3]==5)
server_rpc.cast_mode_query(player,0/0);server_rpc.cast_mode_query(player,-1);server_rpc.cast_mode_query(player,"5")
assert(#sends==1)

-- Remote clients require the current activation's authoritative response.
world(false);init();G.ThePlayer=player
local events,tasks={},{}
player.ListenForEvent=function(_,name,fn) events[name]=fn end
player.DoTaskInTime=function(_,delay,fn)
    local task={delay=delay,fn=fn,Cancel=function(self) self.cancelled=true end}
    tasks[#tasks+1]=task;return task
end
post(player);tasks[1].fn()
assert(not Mode.ready() and not Cast.available(wand,player,pos))
local first=requests[#requests]
tasks[#tasks].fn();assert(requests[#requests]==first,"retry must preserve request identity")
client_rpc.cast_mode_state(1,first+1);assert(not Mode.ready())
client_rpc.cast_mode_state("true",first);assert(not Mode.ready())
client_rpc.cast_mode_state(true,first);assert(not Mode.ready())
client_rpc.cast_mode_state(nil,first);assert(not Mode.ready())
client_rpc.cast_mode_state(2,first);assert(not Mode.ready())
client_rpc.cast_mode_state(1,first)
assert(Mode.ready() and Mode.enabled() and ACTIONS.NW_CAST.instant and tasks[#tasks].cancelled)
netcast=false;assert(Cast.available(wand,player,pos),"net cooldown is not a per-shot ACK")
netready=false;assert(not Cast.available(wand,player,pos));netready=true
assert(Cast.client_state(player,action())==nil and previews==1)
sgtags.busy=true;assert(Cast.client_state(player,action())==nil and previews==1);sgtags.busy=nil
assert(not Cast.perform(action()),"client must never execute server cast")
events.playerdeactivated();assert(not Mode.ready() and not ACTIONS.NW_CAST.instant)
client_rpc.cast_mode_state(1,first);assert(not Mode.ready())
events.playeractivated();local second=requests[#requests];assert(second~=first)
client_rpc.cast_mode_state(1,first);assert(not Mode.ready())
client_rpc.cast_mode_state(wire_value(false),second);assert(not Mode.ready(),"missing mode is not an authoritative normal reply")
client_rpc.cast_mode_state(0,second)
assert(Mode.ready() and not Mode.enabled() and not ACTIONS.NW_CAST.instant)
assert(Cast.client_state(player,action())==nil)
netcast=true;assert(Cast.client_state(player,action())=="attack")
events.onremove();assert(not Mode.ready())

-- A default-off authoritative server preserves the native attack route.
world(true);config=false;Mode.install(env,G,ACTIONS.NW_CAST);init()
assert(Mode.ready() and not Mode.enabled() and not ACTIONS.NW_CAST.instant)
assert(Cast.server_state(player,action())=="attack")
local instant_cast=wand.components.nw_wand.Cast
wand.components.nw_wand.Cast=function() return true end
assert(Cast.perform(action()) and posecasts==3,"normal mode keeps its native animation")
wand.components.nw_wand.Cast=instant_cast
server_rpc.cast_mode_query(player,1)
local normal=sends[#sends]
assert(normal[2]==0 and type(normal[2])=="number" and normal[3]==1,"normal mode must have an explicit wire value")
world(false);init();post(player);events.playeractivated()
assert(not Mode.ready() and requests[#requests]==normal[3])
client_rpc.cast_mode_state(normal[2],normal[3])
assert(Mode.ready() and not Mode.enabled() and not ACTIONS.NW_CAST.instant)
local actions={};Cast.point(wand,player,pos,actions,true)
assert(actions[1]==ACTIONS.NW_CAST and Cast.client_state(player,action())=="attack","normal reply must restore the right-click action")
print("instant cast: authoritative activation sync, retry/stale reply rejection, preview, legal states, fresh plans and player tick deduplication")
