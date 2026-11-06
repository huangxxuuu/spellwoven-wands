local C=require("nw/compiler")
local E=require("nw/executor")
local P=require("nw/projectiles")
local T=require("nw/projectile_triggers")
local Effects=require("nw/spell_effects")
local Limits=require("nw/spell_limits")
DEGREES=math.pi/180
local objects,blasts,candidates={},{},{}
local explosions=0
local owner={GUID=882,valid=true,components={combat={CanTarget=function() return true end}}}
function owner:IsValid() return self.valid end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
TheSim={FindEntities=function() return candidates end}
require("nw/explosions").hit=function(_,p) if p and p.flags and p.flags.explosive_hit then explosions=explosions+1 end end
Effects.chain=function(_,first,x,z) blasts[#blasts+1]={x=x,z=z} end
SpawnPrefab=function(name)
    if name~="nw_projectile" then return {Transform={SetPosition=function() end}} end
    local obj={valid=true,x=0,z=0}
    obj.Transform={GetWorldPosition=function() return obj.x,0,obj.z end,SetRotation=function() end}
    obj.Physics={SetMotorVel=function() end}
    function obj:IsValid() return self.valid end
    function obj:Remove() if self.valid then self.valid=false;self.cleanup() end end
    function obj:Launch(caster,p,x,z,dx,dz,cleanup)
        self.x,self.z,self.cleanup=x,z,cleanup
        self._shot={owner=caster,p=p,damage=p.damage,speed=p.speed,remaining=p.lifetime,
            x=x,z=z,dx=dx,dz=dz,time=0,age=0,travelled=0,hit={},
            hits_left=p.flags.pierce_all and math.huge or nil}
        require("nw/flight").reset(self._shot,dx,dz)
    end
    objects[#objects+1]=obj;return obj
end
local function cast(...)
    for _,e in ipairs(objects) do e:Remove() end
    assert(E.stats()==0)
    objects,blasts,candidates={},{},{};owner.valid=true
    local w=require("nw/generator").starter();w.stats.mana_max=2000;w.stats.spread=0;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,51)
    assert(E.execute(assert(C.compile(w)),owner,0,0,1,0))
    return objects[1]
end
local function target(x)
    local e={GUID=991,components={health={IsDead=function() return false end},combat={GetAttacked=function() end}}}
    e.Transform={GetWorldPosition=function() return x,0,0 end}
    function e:IsValid() return true end
    function e:IsInLimbo() return false end
    function e:HasTag() return false end
    function e:GetPhysicsRadius() return .5 end
    return e
end
for _,event in ipairs({"hit","timer"}) do
    local e=cast("short_life","short_life","arrow_"..event,"chain")
    e.x=10;P.step(e,.4,{})
    assert(not e.valid and #blasts==1 and math.abs(blasts[1].x-7.5)<1e-8 and E.stats()==0,"expiry payload at clipped endpoint")
    T.finish(e._shot,7.5,0)
    assert(#blasts==1,"termination must be idempotent")
    e=cast("arrow_"..event,"chain");candidates={target(2)}
    e.x=3;P.step(e,.1,{})
    assert(not e.valid and #blasts==1 and E.stats()==0,"terminal contact must emit only once")
end
local e=cast("arrow_timer","chain")
e.x=10;P.step(e,.5,{})
assert(e.valid and #blasts==1)
e.x=24;P.step(e,1.2,{})
assert(not e.valid and #blasts==1 and E.stats()==0,"timer cannot replay on expiry")
e=cast("pierce_all","arrow_hit","chain");candidates={target(2)}
e.x=3;P.step(e,.1,{})
assert(e.valid and #blasts==1)
candidates={target(6)};e.x=7;P.step(e,.2,{})
assert(e.valid and #blasts==2,"piercing collisions still replay the payload")
candidates={};e.x=24;P.step(e,1.2,{})
assert(not e.valid and #blasts==2 and E.stats()==0,"prior hits suppress the expiration payload")
-- Every scatter pellet owns its own timer payload.
e=cast("short_life","short_life","scatter_timer","chain")
for _,o in ipairs(objects) do o.x=6;P.step(o,.4,{}) end
assert(#blasts==3 and E.stats()==0,"every scatter pellet owns a timer payload")
e=cast("scatter_hit","chain")
for _,o in ipairs(objects) do o.x=18;P.step(o,1.2,{}) end
assert(#blasts==3 and E.stats()==0,"each collision carrier owns its expiration event")
-- Queued normal timer and expiry on the same frame retain the prepaid payload.
e=cast("scatter_timer","chain")
local queued={}
for _,o in ipairs(objects) do o.x=18;P.step(o,1.2,{},queued) end
assert(#blasts==0 and E.stats()==3)
for group,t in pairs(queued) do group.timer_queued=nil;t.fire(t.x,t.z,t.dx,t.dz) end
assert(#blasts==3 and E.stats()==0)
-- Optional range exhaustion is a normal end; administrative Remove stays silent.
local oldrange=Limits.range;Limits.range=5
e=cast("arrow_hit","chain");e.x=10;P.step(e,.2,{})
assert(not e.valid and #blasts==1 and math.abs(blasts[1].x-5)<1e-8)
Limits.range=oldrange
e=cast("arrow_timer","chain");e:Remove()
assert(#blasts==0 and E.stats()==0)
e=cast("arrow_hit","chain");owner.valid=false;P.step(e,.1,{})
assert(not e.valid and #blasts==0 and E.stats()==0)
owner.valid=true
-- An impact modifier runs for each piercing contact, never expiry or phased walls.
e=cast("pierce_all","explosion","arrow");candidates={target(2)}
e.x=3;P.step(e,.1,{})
assert(e.valid and explosions==1)
candidates={target(6)};e.x=7;P.step(e,.2,{})
assert(e.valid and explosions==2)
candidates={};e.x=24;P.step(e,1.2,{})
assert(not e.valid and explosions==2)
e=cast("phase_wall","explosion","arrow")
local wall=target(2)
function wall:HasTag(tag) return tag=="wall" end
candidates={wall};e.x=3;P.step(e,.1,{})
assert(e.valid and explosions==2,"phasing a wall is not a hit")
e=cast("explosion","arrow");candidates={wall};e.x=3;P.step(e,.1,{})
assert(not e.valid and explosions==3,"ordinary wall contact is a hit")
-- Forced gameplay destruction and landing paths use the same guarded finalizer.
e=cast("arrow_timer","chain");T.finish(e._shot,3,4);e:Remove()
assert(#blasts==1 and blasts[1].x==3 and blasts[1].z==4 and E.stats()==0)
-- A rejected hit attempt is not a successfully released payload.
local attempts=0
local pending={owner=owner,p={event="hit"},dx=1,dz=0,fire=function()
    attempts=attempts+1;return attempts>1
end}
T.hit(pending,nil,0,0);assert(not pending.hit_payload_fired)
T.finish(pending,1,0);assert(attempts==2)
local recursive={owner=owner,p={event="hit"},dx=1,dz=0}
local released=0
recursive.fire=function()
    released=released+1;T.finish(recursive,1,0);return true
end
T.hit(recursive,nil,1,0)
assert(released==1 and recursive.hit_payload_fired,"payload destroying its carrier cannot recursively replay")
-- The shield bypasses swept flight but must follow the same timer/end rules.
owner._nw_shields={}
e=cast("short_life","short_life","arrow_timer","chain")
require("nw/orbit_shield").update(e,e._shot,.3,{})
assert(not e.valid and #blasts==1 and E.stats()==0)
e=cast("arrow_timer","chain")
require("nw/orbit_shield").update(e,e._shot,.5)
require("nw/orbit_shield").update(e,e._shot,1.2)
assert(not e.valid and #blasts==1 and E.stats()==0)
print("projectile triggers: expiration, contact deduplication, piercing replay, independent scatter timers, queued expiry, ledger cleanup")
