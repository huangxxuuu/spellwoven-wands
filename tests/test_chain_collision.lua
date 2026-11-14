-- Real compiler -> executor -> scheduled chain -> collision payload. Only
-- engine entities/visuals and the emitted projectile's flight are simulated.
DEGREES=math.pi/180
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
local time,guid=0,0
GetTime=function() return time end
local tasks,candidates,shots,arcs,finished={},{},{},{},0
TheWorld={components={},state={israining=false},DoTaskInTime=function(_,delay,fn)
    assert(delay==.15);tasks[#tasks+1]=fn
end}
local Compiler=require("nw/compiler")
local Executor=require("nw/executor")
local Effects=require("nw/spell_effects")
local Target=require("nw/targeting")
local function entity(tags,x,z)
    guid=guid+1
    local e={GUID=guid,tags=tags,components={},valid=true,x=x or 0,z=z or 0}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return false end
    function e:HasTag(tag) return self.tags[tag] or false end
    function e:GetDistanceSqToPoint(x,_,z) return (self.x-x)^2+(self.z-z)^2 end
    function e:GetPosition() return Vector3(self.x,0,self.z) end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end}
    return e
end
local function creature(tags,x,z)
    local e=entity(tags,x,z)
    local h={currenthealth=100}
    h.IsDead=function() return h.currenthealth<=0 end
    h.DoDelta=function(_,n) h.currenthealth=h.currenthealth+n end
    e.components.health=h
    e.components.combat={CanTarget=function() return true end,IsAlly=function() return false end}
    return e
end
local owner=creature({player=true},-1,0)
owner.components.combat.DoAttack=function(_,e,weapon)
    e.components.health:DoDelta(-weapon.damage)
end
Effects.scan=function() return candidates end -- selection itself stays real
local fail_arc=false
Effects.fx=function(name,x,z)
    if name~="nw_arc_fx" then return {} end
    if fail_arc then return end
    local fx={components={weapon={}}}
    fx.components.weapon.SetDamage=function(_,damage) fx.damage=damage end
    fx.SetSpan=function(_,dx,dz,target) arcs[#arcs+1]={target=target,x=x,z=z,dx=dx,dz=dz} end
    return fx
end
SpawnPrefab=function(name)
    assert(name=="nw_projectile",name)
    return {Launch=function(_,caster,p,x,z,dx,dz,cleanup,height,fire)
        shots[#shots+1]={owner=caster,p=p,x=x,z=z,dx=dx,dz=dz,cleanup=cleanup,fire=fire}
    end}
end
local real_chain=Effects.chain
Effects.chain=function(owner,first,x,z,p,ax,az,front,fire,done)
    return real_chain(owner,first,x,z,p,ax,az,front,fire,function()
        finished=finished+1
        if done then done() end
    end)
end
math.random=function() return .5 end
local function compile(ids)
    local w=require("nw/generator").starter()
    w.stats.mana_max=10000;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={card_uid=tostring(i),spell_id=id} end
    w.runtime=Compiler.initial(w.cards,w.stats,1)
    return assert(Compiler.compile(w))
end
local function step()
    time=time+.15;local fn=table.remove(tasks,1);assert(fn);fn()
end
local function drain() while #tasks>0 do step() end end
local function reset(list)
    for _,shot in ipairs(shots) do shot.cleanup() end
    assert(Executor.stats()==0)
    tasks={};candidates=list or {};shots={};arcs={};finished=0
    owner.valid=true;owner.components.health.currenthealth=100;fail_arc=false
end
local function execute(plan) assert(Executor.execute(plan,owner,0,0,1,0,.75)) end

local plan=compile({"target_hostile","damage_up","imprint_hit","chain","target_nature","spark"})
local p=plan.blocks[1].projectiles[1]
assert(p.event=="hit" and p.payload==2,"chain must compile an independent collision payload")
assert(p.damage==25 and p.jump_damage==20 and p.flags.targets.hostile)
local child=plan.blocks[2].projectiles[1]
assert(child.damage==18 and child.flags.targets.nature and not child.flags.targets.hostile)
local a,b,c,d=creature({hostile=true},1,0),creature({hostile=true},1,3),
    creature({hostile=true},4,3),creature({hostile=true},4,6)
reset({a,b,c,d});execute(plan)
assert(#shots==1 and shots[1].x==1 and finished==0)
step();assert(#shots==2 and shots[2].x==1 and shots[2].z==3 and finished==0,
    "chain group must stay alive after first collision")
drain();assert(#shots==4 and finished==1 and #arcs==4)
assert(a.components.health.currenthealth==75 and b.components.health.currenthealth==80,
    "payload routing must not duplicate chain damage")
for _,shot in ipairs(shots) do
    assert(shot.p.flags.targets.nature and not shot.p.flags.targets.hostile)
    assert(math.abs(shot.dx*shot.dx+shot.dz*shot.dz-1)<1e-9)
end
assert(math.abs(shots[2].dx)<.06 and shots[2].dz>.99,
    "payload launches along the current hop, not the original aim")
assert(not p._nw_root and p.event=="hit" and child.damage==18,"compiled template stays unchanged")

-- Default payload remains default, and an explicit selection can hit scenery
-- without health/combat and still run its collision payload.
plan=compile({"target_nature","imprint_hit","chain","spark"})
local tree=entity({tree=true},1,0)
reset({tree});execute(plan);drain()
assert(#shots==1 and not shots[1].p.flags.targets and finished==1)
assert(#arcs==4,"empty hops still draw arcs but must not emit payloads")
-- A zero-length first landing uses the aim direction, and capability checks
-- do not reject an explicit scenery selection when the caster lacks combat.
reset({tree});tree.x=0
local combat=owner.components.combat;owner.components.combat=nil
execute(plan);drain();owner.components.combat=combat;tree.x=1
assert(#shots==1 and shots[1].dx>.99 and math.abs(shots[1].dz)<.06 and finished==1)
-- The optional collision-first target is checked against the child's scope.
local carrier_plan=compile({"target_hostile","spark_hit","target_nature","imprint_hit","chain","spark"})
local hostile=creature({hostile=true},0,0)
reset({tree,hostile});execute(carrier_plan)
assert(shots[1].fire(0,0,1,0,hostile))
assert(arcs[1].target==tree and #shots==2,"child chain cannot inherit parent hit target selection")
drain();assert(#shots==2 and finished==1)

-- Recheck selection on every delayed hop; do not trust the previous scan.
plan=compile({"target_hostile","imprint_hit","chain","spark"})
a=creature({hostile=true},1,0);b=creature({hostile=true},2,0)
reset({a,b});execute(plan);b.tags.hostile=nil;drain()
assert(#shots==1 and finished==1)
reset({tree});execute(plan);drain()
assert(#shots==0 and finished==1,"unselected and empty landings are not collisions, including completion")

-- Termination releases the held group once. No expiry fallback for an arc.
reset({a,b});execute(plan);owner.valid=false;step()
assert(finished==1 and #tasks==0 and #shots==1)
reset({a,b});execute(plan);owner.components.health.currenthealth=0;step()
assert(finished==1 and #tasks==0 and #shots==1)
reset({a});fail_arc=true;execute(plan)
assert(finished==1 and #tasks==0 and #shots==0)
-- A payload can invalidate its caster synchronously during the first hit.
reset({a})
local spawn=SpawnPrefab
SpawnPrefab=function(name)
    local obj=spawn(name);local launch=obj.Launch
    obj.Launch=function(...) launch(...);owner.valid=false end
    return obj
end
execute(plan);SpawnPrefab=spawn
assert(finished==1 and #tasks==0 and #shots==1)

-- Rejected payload emissions at capacity cannot strand the chain or retry
-- after it ends. Each of the four hits still attempts its own release.
reset({a,b,c,d});b.tags.hostile=true
Executor.set_projectile_limit(25)
local reserved={}
for i=1,24 do reserved[i]=assert(require("nw/entity_limits").acquire(owner,"projectiles")) end
execute(plan);drain()
assert(#shots==1 and finished==1 and Executor.stats()==25)
for _,release in ipairs(reserved) do release() end
reset();Executor.set_projectile_limit(0)

-- A timer imprint is not silently changed into a collision imprint, and a
-- normal hit carrier retains repeated per-hit releases and cleanup behavior.
local timer=compile({"imprint_timer","double","chain","spark","arrow"})
assert(not timer.blocks[1].projectiles[1].event)
assert(timer.blocks[1].projectiles[2].event=="timer")
local ordinary=compile({"imprint_hit","spark","double","arrow","arrow"})
execute(ordinary)
local carrier=shots[1]
assert(carrier.fire(1,0,1,0,a));assert(#shots==3)
assert(carrier.fire(2,0,1,0,b));assert(#shots==5)
carrier.cleanup();assert(not carrier.fire(3,0,1,0,c) and #shots==5)
reset()
print("chain collision: real compile/execute, every landing, scope isolation, scenery, retarget, empty hops, termination, capacity and ordinary carrier passed")
