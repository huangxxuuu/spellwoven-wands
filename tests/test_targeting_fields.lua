-- Exercise shared targeting through the real field/electric implementations.
-- Engine entities, visuals and emitted-shot execution are simulated; no
-- selection function is stubbed, including native-combat capability checks.
DEGREES=math.pi/180
FRAMES=1/30
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
local now,guid=0,0
GetTime=function() return now end
local candidates,arcs,attacks,shots,moves,wet,soil,chain_tasks={},{},{},{},{},{},0,{}
TheWorld={components={},state={israining=false},DoTaskInTime=function(_,delay,fn) chain_tasks[#chain_tasks+1]=fn end}
TheWorld.components.farming_manager={AddSoilMoistureAtPoint=function() soil=soil+1 end}
package.loaded["nw/field_stages"]={start=function() end,finish=function() end,pulse=function() end,
    warning=function() end,duration=function() return .2 end,storm_time_scale=function() return 1 end,storm_lift=function() return 0 end}
package.loaded["nw/executor"]={execute=function(plan) shots[#shots+1]=plan;return true end}
local Target=require("nw/targeting")
local Effects=require("nw/spell_effects")
local Hits=require("nw/expanded_hits")
local Fields=require("nw/expanded_fields")
local Field=require("nw/field_effects")
local function entity(tags,x)
    guid=guid+1
    local e={GUID=guid,tags=tags or {},components={},valid=true,x=x or 0,z=0,tasks={},periodic={},events={}}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return false end
    function e:HasTag(tag) return self.tags[tag] or false end
    function e:HasAnyTag(...) for _,tag in ipairs({...}) do if self:HasTag(tag) then return true end end return false end
    function e:AddTag(tag) self.tags[tag]=true end
    function e:RemoveTag(tag) self.tags[tag]=nil end
    function e:IsAsleep() return false end
    function e:GetPosition() return Vector3(self.x,0,self.z) end
    function e:GetPhysicsRadius() return .2 end
    function e:GetDistanceSqToPoint(x,y,z) return (self.x-x)^2+(self.z-z)^2 end
    function e:Remove() self.valid=false end
    function e:ListenForEvent(name,fn) self.events[name]=fn end
    function e:RemoveEventCallback(name) self.events[name]=nil end
    function e:DoTaskInTime(delay,fn) self.tasks[#self.tasks+1]={delay=delay,fn=fn};return {Cancel=function() end} end
    function e:DoPeriodicTask(delay,fn) self.periodic[#self.periodic+1]=fn;return {Cancel=function() end} end
    function e:AddComponent(name)
        self.components[name]={SetMaxHealth=function() end,SetInvincible=function() end}
        if name=="wateryprotection" then
            local water=self.components[name];water.inst=self;water.ignoretags={"FX","DECOR","INLIMBO","burnt"}
            water.ApplyProtectionToEntity=function(_,target) wet[#wet+1]=target end
            water.SpreadProtectionAtPoint=function(self,x,y,z,r)
                for _,target in ipairs(TheSim:FindEntities(x,y,z,r,nil,self.ignoretags)) do self:ApplyProtectionToEntity(target) end
                soil=soil+1
            end
        end
    end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end}
    return e
end
local function health(e)
    local h={currenthealth=100,IsDead=function() return false end,GetMaxWithPenalty=function() return 100 end,
        GetFireDamageScale=function() return 1 end}
    h.DoDelta=function(_,n) h.currenthealth=h.currenthealth+n end
    e.components.health=h
end
local function creature(tags,x)
    tags._combat=true
    local e=entity(tags,x);health(e)
    e.components.combat={CanTarget=function() return true end,IsAlly=function() return false end,
        GetAttacked=function(_,who,n) e.components.health.currenthealth=e.components.health.currenthealth-n end,
        SetTarget=function(_,target) e.taunted=target end}
    return e
end
local owner=creature({player=true},10)
owner.components.combat.DoAttack=function(_,target,weapon)
    assert(target.components.combat and target.components.health,"native combat must never receive scenery")
    attacks[#attacks+1]=target
    target.components.health.currenthealth=target.components.health.currenthealth-weapon.damage
end
TheSim={FindEntities=function(_,x,y,z,r,must,exclude,oneof)
    local found={}
    for _,e in ipairs(candidates) do
        local ok=e.valid and e:GetDistanceSqToPoint(x,y,z)<=r*r
        for _,tag in ipairs(exclude or {}) do if e:HasTag(tag) then ok=false end end
        local matches=not oneof
        for _,tag in ipairs(oneof or {}) do if e:HasTag(tag) then matches=true end end
        if ok and matches then found[#found+1]=e end
    end
    return found
end}
Effects.fx=function(name,x,z)
    local fx={components={weapon={}}}
    fx.components.weapon.SetDamage=function(_,n) fx.damage=n end
    fx.SetSpan=function(_,dx,dz,target) arcs[#arcs+1]=target or false end
    fx.SetRadius=function() end
    return fx
end
Hits.safe_move=function(e) moves[#moves+1]=e end
local tree=entity({tree=true},1);tree.Physics={}
local rock=entity({boulder=true},2);rock.Physics={}
local monster=creature({hostile=true},1)
local nature={targets={nature=true}}
local function params(id,flags)
    return {id=id,flags=flags or {},radius=3,damage=12,jump_damage=8,max_targets=2}
end
local function reset(list)
    now=now+1;candidates=list;arcs={};attacks={};shots={};moves={};wet={};soil=0;chain_tasks={}
end
local function run(id,flags,list)
    reset(list);local inst=entity();local p=params(id,flags)
    Fields.actions[id](inst,owner,p,0,0,1,0)
    return inst,p
end
-- Both electrical field families can land on trees/rocks without native
-- combat. Selecting nature must not silently revert to nearby monsters.
for _,id in ipairs({"shock_ring","storm_cloud"}) do
    local inst=run(id,nature,{tree,rock,monster})
    for _,task in ipairs(inst.tasks) do if task.delay<1 then task.fn() end end
    assert(#arcs>0 and #attacks==0,id.." must reach selected natural objects safely")
    for _,e in ipairs(arcs) do assert(e==tree or e==rock) end
end
local inst=run("shock_ring",{}, {tree,monster})
inst.tasks[1].fn();assert(arcs[1]==monster and attacks[1]==monster)
-- A health-only object takes health damage, not an unsafe DoAttack call.
local living_tree=entity({tree=true},1);health(living_tree)
reset({living_tree});Hits.electric(owner,living_tree,0,0,12,params("shock_ring",nature),true)
assert(living_tree.components.health.currenthealth==88 and arcs[1]==living_tree and #attacks==0)
-- A default scan cached in this same frame must not hide health-only
-- candidates from an explicit selector's broader scan.
local health_only=entity({_health=true},1);health(health_only)
reset({health_only})
assert(#Target.query(owner,0,0,3,{})==0)
assert(Target.query(owner,0,0,3,{targets={neutral=true}},{components={"health"}})[1]==health_only)
-- Projectile electric impact, twin arcs and a chain all share that landing
-- policy; chain hop tracking still advances through separate scenery targets.
reset({tree});Hits.impact({owner=owner,p=params("tri_electric",nature),age=0,dx=1,dz=0},tree,1,0)
assert(arcs[1]==tree and #attacks==0)
reset({tree,rock,monster});Effects.chain(owner,nil,0,0,params("chain",nature),1,0,true)
assert(arcs[1]==tree and #chain_tasks==1)
chain_tasks[1]();assert(arcs[2]==rock and #attacks==0)
reset({tree});local partner=entity({},2)
Hits.step({owner=owner,p=params("spark",{targets={nature=true},twin_arc={}}),x=0,z=0,height=.5,
    partner=partner,context={arcs={}}},now)
assert(arcs[#arcs]==tree and #attacks==0)
-- Swarms can launch toward selected scenery; biological taunt/movement
-- capabilities remain independent, so trees are never taunted/teleported.
inst=run("bee_swarm",nature,{tree,monster});inst.tasks[1].fn()
assert(#shots==1 and shots[1].blocks[1].projectiles[1].flags.targets.nature)
inst=run("deer_decoy",nature,{tree,rock});inst.periodic[1]();assert(not tree.taunted and not rock.taunted)
inst=run("deer_decoy",{targets={hostile=true}},{tree,monster});inst.periodic[1]();assert(monster.taunted==inst)
run("vortex",nature,{tree,rock});assert(#moves==0)
monster.Physics={};monster.components.locomotor={}
run("vortex",{targets={hostile=true}},{tree,monster});assert(moves[1]==monster)
-- Rain keeps its broad environmental default, but explicit selectors govern
-- native water applications, creature wet tags and the separate soil effect.
local player=creature({player=true},1)
local item=entity({},1)
inst=run("rain_cloud",nature,{tree,rock,monster,player,item});inst.tasks[1].fn()
assert(#wet==2 and wet[1]==tree and wet[2]==rock and soil==1 and not monster:HasTag("wet"))
inst=run("rain_cloud",{targets={hostile=true}},{tree,monster,player,item});inst.tasks[1].fn()
assert(#wet==1 and wet[1]==monster and soil==0 and monster:HasTag("wet"))
inst=run("rain_cloud",{}, {tree,monster,player,item});inst.tasks[1].fn()
assert(#wet==4 and soil==1)
-- Explicit support selection replaces the default beneficiary faction.
player.components.health.currenthealth=50;monster.components.health.currenthealth=50
assert(Effects.ally(owner,player,{}) and Effects.ally(owner,player,{targets={players_other=true}}))
assert(not Effects.ally(owner,player,nature) and Effects.ally(owner,monster,{targets={hostile=true}}))
assert(not Effects.ally(owner,monster,{}))
-- Ordinary shared blasts retain player exposure only as their default.
-- Explicit selectors replace that default across every caller of blast.
local original_impact=Hits.impact
local impacts={}
Hits.impact=function(s,e,x,z) impacts[#impacts+1]=e;return original_impact(s,e,x,z) end
for _,id in ipairs({"spore_ball","end_beam","moon_fall"}) do
    reset({tree,player,monster});impacts={}
    player.components.health.currenthealth=100;monster.components.health.currenthealth=100
    Effects.blast(owner,0,0,params(id,nature))
    assert(#impacts==1 and impacts[1]==tree,id.." explicit nature blast must not reach players/creatures")
    assert(player.components.health.currenthealth==100 and monster.components.health.currenthealth==100)
end
for _,id in ipairs({"crystal_mine","sleep_crystal"}) do
    reset({tree,player,monster});impacts={}
    player.components.health.currenthealth=100;monster.components.health.currenthealth=100
    local p=params(id,nature)
    Effects.blast(owner,0,0,p)
    assert(#impacts==3 and player.components.health.currenthealth==88 and monster.components.health.currenthealth==88,
        "real crystal bursts bypass scope at selection and deep damage entry")
    assert(p.flags==nature and nature.targets.nature and not nature._nw_target_bypass,"burst cannot mutate sensing flags")
end
local pet=creature({},1);pet.components.follower={leader=owner}
local untagged=entity({},1);health(untagged)
reset({pet,untagged});impacts={}
Effects.blast(owner,0,0,params("crystal_mine",{targets={self=true}}))
assert(pet.components.health.currenthealth==88 and untagged.components.health.currenthealth==88,
    "crystal aftermath includes friendlies and untagged native health objects")
reset({tree,player,monster});impacts={}
player.components.health.currenthealth=100;monster.components.health.currenthealth=100
Effects.blast(owner,0,0,params("crystal_mine",{}))
assert(#impacts==3 and player.components.health.currenthealth==88 and monster.components.health.currenthealth==88,
    "default crystal burst retains broad environmental reach")
reset({tree,player,monster});impacts={}
player.components.health.currenthealth=100;monster.components.health.currenthealth=100
Effects.blast(owner,0,0,params("crystal_mine",{targets={players_other=true}}))
assert(#impacts==3 and player.components.health.currenthealth==88 and monster.components.health.currenthealth==88)
local boat=entity({boat=true,walkableplatform=true},1);health(boat)
boat.components.hullhealth={};boat.components.boatphysics={};boat.components.walkableplatform={}
local wall=entity({wall=true},2);health(wall)
reset({boat,wall});impacts={}
Effects.blast(owner,0,0,params("crystal_mine",{targets={building=true}}))
assert(#impacts==2 and boat.components.health.currenthealth==88 and wall.components.health.currenthealth==88,
    "real scan must discover a boat without combat/structure/workable tags")
reset({boat,wall});impacts={}
boat.components.health.currenthealth=100;wall.components.health.currenthealth=100
local moon=params("moon_fall",{targets={building=true}});moon.no_structures=true
Effects.blast(owner,0,0,moon)
assert(#impacts==0 and boat.components.health.currenthealth==100 and wall.components.health.currenthealth==100,
    "building-protected blasts exclude boats and walls through the common category")
impacts={};inst=run("deer_decoy",{targets={building=true}},{boat,wall});inst.tasks[1].fn()
assert(#impacts==0,"decoy's structural immunity includes boats")
player.components.health.currenthealth=100;monster.components.health.currenthealth=100
impacts={};inst=run("deer_decoy",{targets={hostile=true}},{player,monster});inst.tasks[1].fn()
assert(#impacts==1 and impacts[1]==monster and player.components.health.currenthealth==100,
    "decoy expiration cannot force players through an explicit hostile scope")
inst=run("rain_cloud",{targets={building=true}},{boat,tree});inst.tasks[1].fn()
assert(#wet==1 and wet[1]==boat and not boat:HasTag("wet"),"boats receive native water without the creature-only wet tag")
Hits.impact=original_impact
local frozen=0
monster.components.freezable={AddColdness=function() frozen=frozen+1 end,SpawnShatterFX=function() end}
Effects.direct(owner,monster,{damage=0,freeze=1,flags=nature},1,0)
assert(frozen==0,"status-only hits must not bypass an explicit target selector")
Effects.direct(owner,monster,{damage=0,freeze=1,flags={targets={hostile=true}}},1,0)
assert(frozen==1)
local slowed=0
local healthless=entity({hostile=true},1)
healthless.components.locomotor={SetExternalSpeedMultiplier=function() slowed=slowed+1 end,
    RemoveExternalSpeedMultiplier=function() end}
Hits.impact({owner=owner,p={id="slime",damage=0,flags={targets={hostile=true}}},dx=1,dz=0},healthless,1,0)
assert(slowed==1,"a selected locomotor-only target can receive a control effect without health")
-- Bound fire damage survives category changes and ordinary combat target
-- rejection, while new applications remain subject to the original selector.
monster.components.health.currenthealth=100;monster.tasks={};monster.components.freezable=nil
local fire={id="fire",damage=9,burn_damage=3.6,burn_ticks=3,flags={targets={hostile=true}}}
Effects.direct(owner,monster,fire,1,0)
assert(monster._nw_burn and not fire.flags._nw_target_bypass)
monster.tags.hostile=nil;monster.components.follower={leader=owner}
owner.components.combat.CanTarget=function() return false end
for i=1,3 do now=now+1;monster.tasks[i].fn(monster) end
assert(math.abs(monster.components.health.currenthealth-80.2)<.001 and not monster._nw_burn)
Effects.direct(owner,monster,fire,1,0)
assert(not monster._nw_burn,"a new fire hit still checks current category")
owner.components.combat.CanTarget=function() return true end
monster.components.follower=nil;monster.tags.hostile=true
-- Rain backlash is a real hop: explicit scope must admit the caster. The
-- no-selector default retains its original self-backfire probability.
TheWorld.state.israining=true;owner.GetIsWet=function() return true end
local old_random=math.random;math.random=function() return 0 end
owner.x=1
for _,flags in ipairs({{targets={hostile=true}}, {}, {targets={hostile=true,self=true}}}) do
    reset({monster,owner});owner.components.health.currenthealth=100
    Effects.chain(owner,monster,0,0,params("chain",flags),1,0,true);chain_tasks[1]()
    assert((owner.components.health.currenthealth<100)==(not flags.targets or flags.targets.self==true),
        "explicit backlash follows each-hop selection; default backlash remains")
end
math.random=old_random
print("targeting fields: real crystal aftermath, filtered body blasts, burn lifetime, chain backlash and support scopes")
