local Boss = require("nw/dark_fog_boss")
local clock = 0
GetTime = function() return clock end
local notifications = {}
TheWorld = { ismastersim = true }
package.loaded["nw/dark_fog"] = { disperse_circle = function(world, x, z, r, inner)
    notifications[#notifications + 1] = { world, x, z, r, inner }
end, contains = function(_, inst) return inst.fog_inside == true end,
disperse_sector = function(world,x,z,r,rotation,arc) notifications[#notifications+1]={world,x,z,r,rotation,arc} end }
local components, graphs = {}, {}
Boss.install(function(name, fn) components[name] = fn end,
    function(name, fn) graphs[name] = fn end)
Boss.install(function() error("install twice") end, function() error("install twice") end)

local function entity(prefab)
    local e = { prefab = prefab, components = {}, events = {}, stops = 0, restarts = 0, fog_inside = true }
    function e:IsValid() return not self.removed end
    function e:IsInLimbo() return self.limbo end
    function e:IsAsleep() return self.asleep end
    function e:ListenForEvent(name, fn) self.events[name] = fn end
    function e:StopBrain(reason) self.stops = self.stops + 1; self._brainstopped = self._brainstopped or {}; self._brainstopped[reason] = true end
    function e:RestartBrain(reason)
        self.restarts = self.restarts + 1
        self._brainstopped[reason] = nil
        if next(self._brainstopped) == nil then self._brainstopped = nil end
    end
    e.components.health = { IsDead = function() return e.dead end }
    e.components.combat = { InCooldown = function() return e.cooldown end }
    e.components.timer = { TimerExists = function(_, key) return e.timer == key or e.timers and e.timers[key] end }
    local graph = { states = { idle = { name = "idle", tags = { idle = true } }, hit = { name = "hit", tags = { busy = true } } } }
    for _, name in ipairs({ "attack", "pound", "bi", "pound_pre", "pound_post", "pound_pst", "disarm", "mushroombomb" }) do
        graph.states[name] = { name = name, tags = { busy = true }, onenter = function(owner) owner.native_entries = (owner.native_entries or 0) + 1 end }
    end
    if prefab == "moose" then
        -- Named native-source closure lets the guard distinguish the actual
        -- target-disarm entry from an arbitrary animation callback.
        graph.states.disarm.timeline = { { fn = assert(loadstring([[
            local function DisarmTarget(inst, target)
                inst.disarms=(inst.disarms or 0)+1;inst.CanDisarm=false
            end
            return function(inst) DisarmTarget(inst,inst.components.combat.target) end
        ]], "@scripts/stategraphs/SGmoose.lua"))() } }
    elseif prefab == "bearger" then
        local events=assert(loadstring([[
            local ARC=math.pi/2
            local function DoArcAttack(inst,dist,radius) inst.swings=(inst.swings or 0)+1;return ARC end
            return {{fn=function(inst) DoArcAttack(inst,1,6) end},{fn=function(inst) DoArcAttack(inst,1,6) end}}
        ]],"@scripts/stategraphs/SGbearger.lua"))()
        graph.states.attack.timeline=events
    end
    if graphs[prefab] then graphs[prefab](graph) end
    e.sg = { sg = graph, currentstate = graph.states.idle, statemem = {} }
    e.Transform = { GetWorldPosition = function() return 0,0,0 end,GetRotation=function() return 0 end }
    function e.sg:HasStateTag(tag) return self.currentstate.tags[tag] == true end
    function e.sg:GoToState(name)
        local old = self.currentstate
        if old.onexit then old.onexit(e, name) end
        self.currentstate = self.sg.states[name]; self.statemem = {}
        if self.currentstate.onenter then self.currentstate.onenter(e) end
    end
    local gp = { inst = e, ringWidth = 1.5, queued = {}, damage = 0 }
    function gp:GroundPound(pt, hits)
        self.queued[#self.queued + 1] = { pt = pt or { x = 1, z = 2 }, hits = hits or {} }
    end
    function gp:DestroyRing(pt, radius, points, breakobjects, damage, platforms, inventory, fx, hits)
        if damage then self.damage = self.damage + 1 end
        return "native-result"
    end
    components.groundpounder(gp); e.components.groundpounder = gp
    return e, gp
end

local e, gp = entity("bearger")
assert(Boss.supports(e))
e.dead = true; assert(not Boss.update(e, 0, true)); e.dead = nil
e.limbo = true; assert(not Boss.update(e, 0, true)); e.limbo = nil
e.bufferedaction = {}; assert(not Boss.update(e, 0, true)); e.bufferedaction = nil
e._brainstopped = { frozen = true }; assert(not Boss.update(e, 0, true)); e._brainstopped = nil
e.timer = "GroundPound";e.cooldown=true; assert(not Boss.update(e, 0, true)); e.timer = nil;e.cooldown=nil
e.sg:GoToState("hit"); assert(not Boss.update(e, 0, true)); e.sg:GoToState("idle")
assert(Boss.update(e, 0, true) and e.sg.currentstate.name == "pound" and e.stops == 1)
e.sg:GoToState("bi"); e.sg:GoToState("pound")
assert(e.restarts == 0, "native stand-up chain remains one cast")
gp:GroundPound(); local hit = gp.queued[1]
assert(#notifications == 0, "GroundPound only schedules rings")
Boss.leave(e); assert(e._nw_fog_boss_cast and e.restarts == 0)
e._brainstopped.frozen = true
e.sg:GoToState("hit")
assert(e.restarts == 1 and e._brainstopped.frozen, "release only our brain reason")
assert(gp:DestroyRing(hit.pt, 5, {}, true, true, false, false, false, hit.hits) == "native-result")
assert(gp.damage == 1 and #notifications == 1 and notifications[1][4] == 6.5 and notifications[1][5] == 3.5)
gp:DestroyRing(hit.pt, 7, {}, true, false, false, false, false, hit.hits)
assert(#notifications == 1, "destruction-only rings do not count as damage rings")
gp:GroundPound(); local ordinary = gp.queued[2]
gp:DestroyRing(ordinary.pt, 1, {}, true, true, false, false, false, ordinary.hits)
assert(gp.damage == 2 and #notifications == 1, "ordinary attacks retain damage without clearing fog")
e._brainstopped = nil; e.sg:GoToState("idle")
e.timer="GroundPound"
assert(Boss.update(e, 1, true) and e.sg.currentstate.name=="attack", "native skill cooldown does not block another usable move")
e.timer=nil
e.sg:GoToState("idle");clock=9
assert(Boss.update(e, 9, true))
e.sg:GoToState("idle");clock=99;assert(Boss.update(e, 99, true), "continuous coverage remains responsive")
e.sg:GoToState("idle");Boss.leave(e);clock=100;assert(Boss.update(e, 100, true));clock=0
e.events.entitysleep(e); assert(not e._nw_fog_boss_cast and not e._brainstopped)

local d, dg = entity("dragonfly")
for _, name in ipairs({"walk_start","walk","walk_stop"}) do
    local walking = entity("dragonfly")
    walking.sg.sg.states[name]={name=name,tags={moving=true}}
    walking.sg:GoToState(name);walking.cooldown=true
    walking.sg.mem={flyover=true};assert(not Boss.update(walking,0,true),"do not interrupt lavae/reset flight")
    walking.sg.mem={};walking.reset=true;assert(not Boss.update(walking,0,true));walking.reset=nil
    walking.timer="groundpound_cd";assert(not Boss.update(walking,0,true));walking.timer=nil
    assert(Boss.update(walking,0,true),"ordinary pursuit and swing cooldown must allow defensive pound")
end
assert(Boss.update(d, 0, true)); d.sg:GoToState("pound")
dg:GroundPound(); dg:GroundPound(); dg:GroundPound()
assert(dg.queued[1].hits ~= dg.queued[2].hits, "never merge native pulse hit sets")
Boss.leave(d); d.sg:GoToState("pound_post"); assert(d.restarts == 0)
d.sg:GoToState("idle"); assert(d.restarts == 1)
local before = #notifications
for _, item in ipairs(dg.queued) do dg:DestroyRing(item.pt, 1, {}, true, true, false, false, false, item.hits) end
assert(#notifications == before + 3 and dg.damage == 3, "all committed native pulses survive leaving")
local other = entity("pigman"); assert(not Boss.supports(other) and not Boss.update(other, 10, true))
-- Bearger can leave ordinary walking/running pursuit, but not committed attacks.
for _, name in ipairs({"walk_start","walk","walk_stop","run","run_stop"}) do
    local walking = entity("bearger")
    walking.sg.sg.states[name]={name=name,tags={moving=true}}
    walking.sg:GoToState(name);walking.cooldown=true
    walking.timer="GroundPound";assert(not Boss.update(walking,0,true));walking.timer=nil
    assert(Boss.update(walking,0,true),"bearger walk/swing cooldown must allow defensive pound")
end
for _, name in ipairs({"attack","sleep","layegg2","flyaway"}) do
    local blocked=entity("bearger");blocked.fog_inside=false
    blocked.sg.sg.states[name]={name=name,tags={moving=true}}
    blocked.sg:GoToState(name);assert(not Boss.update(blocked,0,true),"never steal charge/committed states")
end
-- Cancel a queued chase only after acquiring the brain, never a committed
-- attack even when the SG has already dropped its attack/busy tags.
ACTIONS={ATTACK={}}
local pursuit=entity("bearger")
pursuit.sg.sg.states.run={name="run",tags={moving=true,running=true}}
pursuit.sg:GoToState("run");pursuit.bufferedaction={action=ACTIONS.ATTACK}
pursuit.ClearBufferedAction=function(self) assert(self._brainstopped.nw_fog_boss);self.bufferedaction=nil end
pursuit.components.locomotor={bufferedaction={action=ACTIONS.ATTACK},
    SetBufferedAction=function(self,value) assert(pursuit._brainstopped.nw_fog_boss);self.bufferedaction=value end,
    Stop=function() assert(pursuit._brainstopped.nw_fog_boss);pursuit.path_cleared=true end}
assert(Boss.update(pursuit,0,true) and not pursuit.bufferedaction and pursuit.path_cleared
    and not pursuit.components.locomotor.bufferedaction)
local travel=entity("bearger")
travel.components.locomotor={bufferedaction={action={}}}
assert(not Boss.update(travel,0,true) and travel.components.locomotor.bufferedaction and travel.stops==0,
    "a non-combat travel action is not pursuit")
local committed=entity("bearger");committed.fog_inside=false
committed.sg.sg.states.attack.tags={idle=true}
committed.sg:GoToState("attack");committed.bufferedaction={action=ACTIONS.ATTACK}
assert(not Boss.update(committed,0,true) and committed.bufferedaction and committed.stops==0)
local pre=entity("bearger")
pre.sg.sg.states.run_start={name="run_start",tags={moving=true,atk_pre=true}}
pre.sg:GoToState("run_start");assert(not Boss.update(pre,0,true),"wait for charge preparation to finish")
-- An original native entry before the first region scan acquires only a token.
for _,prefab in ipairs({"bearger","moose"}) do
    local first=prefab=="bearger" and "pound" or "disarm"
    local native=entity(prefab);native._brainstopped={other_mod=true}
    assert(Boss.supports(native))
    native.sg:GoToState(first)
    assert(native._nw_fog_boss_cast and not native._nw_fog_boss_cast.brain_owned)
    assert(not native._nw_fog_boss_covered and native.stops==0)
    assert(not Boss.update(native,0,true) and native._nw_fog_boss_cast)
    if prefab=="bearger" then native.sg:GoToState("bi");native.sg:GoToState("pound") end
    Boss.leave(native);native.fog_inside=false;native.sg:GoToState("idle")
    assert(not native._nw_fog_boss_cast and not native._nw_fog_boss_covered)
    assert(native.stops==0 and native.restarts==0 and native._brainstopped.other_mod)
    native.fog_inside=true;native.sg:GoToState(first)
    assert(native._nw_fog_boss_cast,"already-started native entry is marked regardless of scheduler cooldown")

    local early=entity(prefab);early.sg:GoToState(first)
    early.fog_inside=false;early.sg:GoToState("idle")
    assert(not early._nw_fog_boss_cast and not early._nw_fog_boss_covered and early.restarts==0,
        "leaving before first refresh cannot strand coverage or restart the native brain")
    local interrupted=entity(prefab);interrupted.sg:GoToState(first);interrupted.sg:GoToState("hit")
    interrupted.fog_inside=false
    assert(not interrupted._nw_fog_boss_covered,"same-frame interruption before region scan leaves no consumed marker")
    clock=9;early.fog_inside=true;early.sg:GoToState(first)
    assert(early._nw_fog_boss_cast,"after leaving, a later native entry can react again")
    clock=0
    local dry=entity(prefab);dry.fog_inside=false;dry.sg:GoToState(first)
    assert(not dry._nw_fog_boss_cast and dry.stops==0,"ordinary attacks outside fog remain ordinary")
    local ordinary=entity(prefab);ordinary.sg:GoToState("attack")
    assert((ordinary._nw_fog_boss_cast~=nil)==(prefab=="bearger"),"only verified native attack states receive fog provenance")
    local continuous=entity(prefab);continuous.sg:GoToState(first);Boss.update(continuous,0,true)
    continuous.sg:GoToState("idle");clock=9;continuous.sg:GoToState(first)
    assert(continuous._nw_fog_boss_cast,"every native entry in continuous coverage remains marked")
    Boss.leave(continuous);continuous.sg:GoToState("idle");continuous.sg:GoToState(first)
    assert(continuous._nw_fog_boss_cast,"leaving releases only the coverage gate")
    clock=0
end
-- Moose honk clears fog once at its original disarm callback, preserving it.
for _,name in ipairs({"flyaway","glide","layegg","layegg2","layegg_pst","attack"}) do
    local blocked=entity("moose")
    blocked.sg.sg.states[name]={name=name,tags={busy=true}}
    blocked.sg:GoToState(name);assert(not Boss.update(blocked,0,true),"honk cannot steal flight/egg/attack states")
end
local moose=entity("moose")
moose.sg.sg.states.hop={name="hop",tags={moving=true,hopping=true}}
moose.sg:GoToState("hop");moose.cooldown=true
assert(Boss.update(moose,0,true) and moose.sg.currentstate.name=="disarm")
local count=#notifications
moose.sg.currentstate.timeline[1].fn(moose)
assert(moose.disarms==1 and moose.CanDisarm==false and #notifications==count+1 and notifications[#notifications][4]==5.5)
moose.sg:GoToState("idle");assert(moose.restarts==1)
local plain=entity("moose");plain.fog_inside=false;plain.sg:GoToState("disarm")
plain.sg.currentstate.timeline[1].fn(plain)
assert(plain.disarms==1 and #notifications==count+1,"uncovered native honk keeps disarm without fog dispatch")
local deer = entity("deerclops"); assert(not Boss.supports(deer), "missing native closure fails closed")
local fallback=entity("bearger");fallback.timer="GroundPound"
assert(Boss.update(fallback,0,true) and fallback.sg.currentstate.name=="attack","pound cooldown selects ordinary swing")
local notices=#notifications
fallback.sg.currentstate.timeline[1].fn(fallback)
assert(#notifications==notices+1 and notifications[#notifications][2]==1 and notifications[#notifications][4]==6
    and notifications[#notifications][6]==180,"swipe notifies the original offset sector")
local natural=entity("bearger");natural.timer="GroundPound";natural.sg:GoToState("attack")
assert(natural._nw_fog_boss_cast and natural._nw_fog_boss_cast.move.sector and natural.stops==0,
    "native fallback before scan is marked without taking the brain")
for _,prefab in ipairs({"toadstool","toadstool_dark"}) do
    local toad=entity(prefab=="toadstool_dark" and "toadstool" or prefab)
    if prefab=="toadstool_dark" then toad.prefab=prefab end
    toad.timer="pound_cd";toad._nw_fog_boss_bombs_ready=true
    assert(Boss.select(toad).first=="mushroombomb")
    toad.timers={mushroombomb_cd=true};assert(Boss.select(toad)==nil);toad.timers=nil
    toad.cooldown=true;assert(Boss.select(toad)==nil);toad.cooldown=nil
    toad._nw_fog_boss_bombs_ready=nil;assert(Boss.select(toad)==nil,"missing native launch guard disables only bomb fallback")
    toad._nw_fog_boss_bombs_ready=true
    for _,pending in ipairs({"wantstochannel","wantstoroar","wantstoburrow"}) do
        toad.sg.mem={[pending]=true};assert(not Boss.update(toad,0,true),"do not steal queued native phase action")
    end
end
-- Real combat targets are kept only while a native attack can reach them.
local function target(distance)
    return {distance=distance,IsValid=function() return true end,
        GetDistanceSqToPoint=function(self) return self.distance^2 end,
        GetPhysicsRadius=function() return .5 end,Transform={GetWorldPosition=function() return distance,0,0 end}}
end
local function combat_for(inst, victim)
    local c=inst.components.combat;c.inst=inst;c.target=victim
    c.CanTarget=function() return true end;c.CalcAttackRangeSq=function() return 16 end
    c.CanAttack=function(self,t) return not self:InCooldown() and t and t.distance<=4 end
    c.DropTarget=function(self) self.dropped=(self.dropped or 0)+1;self.target=nil end
    c.SetTarget=function(self,t) self.target=t end
    c.DoAttack=function(self,t)
        t=t or self.target;inst.hits=(inst.hits or 0)+1
        if t then inst.events.onattackother(inst,{target=t}) end
        return "native-hit"
    end
    components.combat(c);return c
end
local far=entity("bearger");local fc=combat_for(far,target(30))
assert(Boss.update(far,0,true) and fc.target==nil and fc.dropped==1,"starting defense really drops remote pursuit")
local near=entity("dragonfly");local victim=target(3);local nc=combat_for(near,victim)
assert(Boss.update(near,0,true) and nc.target==victim)
near.timer="groundpound_cd";near.sg:GoToState("pound");near.sg:GoToState("pound_post");near.sg:GoToState("idle")
assert(Boss.update(near,.1,true) and near.sg.currentstate.name=="attack" and nc.target==victim,
    "after pound the in-range original target can receive a normal attack immediately under native cooldown rules")
local contacts=#notifications
assert(nc:DoAttack()=="native-hit" and near.hits==1 and #notifications==contacts+1)
near.sg:GoToState("idle");assert(Boss.update(near,.2,true),"no one-shot coverage latch")
nc:SetTarget(target(30));assert(nc.target==victim,"remote retaliation cannot restart pursuit while controlled")
near.sg:GoToState("idle");victim.distance=30
assert(not Boss.update(near,.3,true),"single-target fallback never starts outside the original reach")

-- An ordinary native attack can enter fog after onenter; it is tagged at the
-- actual hit without re-entering the SG, changing damage, or stopping its brain.
local mid=entity("dragonfly");local mc=combat_for(mid,target(3));mid.fog_inside=false
mid.sg:GoToState("attack");assert(not mid._nw_fog_boss_cast)
mid.fog_inside=true;local count=#notifications;local entries=mid.native_entries
assert(mc:DoAttack()=="native-hit" and #notifications==count+1)
assert(mid._nw_fog_boss_cast and mid.native_entries==entries and mid.stops==0)
mid.sg:GoToState("idle");assert(not mid._nw_fog_boss_cast and mid.restarts==0)
local sweep=entity("bearger");sweep.fog_inside=false;sweep.sg:GoToState("attack")
sweep.fog_inside=true;local count=#notifications
sweep.sg.currentstate.timeline[1].fn(sweep)
assert(#notifications==count+1 and sweep._nw_fog_boss_cast.move.sector and sweep.stops==0,
    "late fog coverage observes the real native sector even with pound available")

-- A native ring already scheduled in clear air can meet fog after its SG
-- has ended. Arm its real batch at impact, then preserve later rings on exit.
local late,lg=entity("bearger");late.fog_inside=false;late.sg:GoToState("pound")
lg:GroundPound();local pulse=lg.queued[1];late.sg:GoToState("idle")
local n=#notifications
lg:DestroyRing(pulse.pt,1,{},true,true,false,false,false,pulse.hits)
assert(#notifications==n and not late._nw_fog_boss_cast,"dry native batch stays inert")
late.fog_inside=true
lg:DestroyRing(pulse.pt,3,{},true,true,false,false,false,pulse.hits)
assert(#notifications==n+1 and not late._nw_fog_boss_cast and late.stops==0,
    "late native ring activates from its own provenance without current attack state")
late.fog_inside=false
lg:DestroyRing(pulse.pt,5,{},true,true,false,false,false,pulse.hits)
assert(#notifications==n+2 and lg.damage==3,"later committed rings survive self-clear and retain all damage")

-- Observation of an externally committed attack must never call Wait.stop
-- and briefly restart a pursuing brain.
local Wait=require("nw/dark_fog_boss_wait")
local observed=entity("bearger");observed.cooldown=true;observed.timer="GroundPound"
observed.components.locomotor={Stop=function() end,GetWalkSpeed=function() return 4 end}
observed.RemoveEventCallback=function(self,event,fn) if self.events[event]==fn then self.events[event]=nil end end
observed.DoPeriodicTask=function(self,_,fn) self.waittask={fn=fn,Cancel=function() end};return self.waittask end
assert(Wait.start(observed,0,function() return false end))
observed.sg:GoToState("pound")
assert(observed._nw_fog_boss_cast and observed._nw_fog_boss_wait and observed._brainstopped[Wait.reason]
    and observed.restarts==0,"native entry preserves waiting ownership")
observed.sg:GoToState("idle")
assert(observed._nw_fog_boss_wait and observed.restarts==0,"native finish does not release someone else's brain reason")
Wait.leave(observed);assert(observed.restarts==1 and not observed._brainstopped)

TheWorld.ismastersim = false
Boss.leave(e); assert(not Boss.update(e, 999, true), "server-only scheduler")
return true
