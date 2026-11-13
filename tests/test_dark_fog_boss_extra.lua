local Boss=require("nw/dark_fog_boss")
local hooks,components,prefabs={},{},{}
Boss.install(function(n,fn) components[n]=fn end,function(n,fn) hooks[n]=fn end,function(n,fn) prefabs[n]=fn end)
assert(hooks.leif and not hooks.Leif,"PostInit uses StateGraph name, not SGLeif source filename")
assert(hooks.beequeen,"beequeen must register its actual native stategraph")
assert(hooks.spat,"spat must register its native attack graph")
local fog=true
TheWorld={ismastersim=true};GetTime=function() return 0 end
package.loaded["nw/dark_fog"]={contains=function() return fog end,disperse_circle=function() end}
local function make(prefab)
    local e={prefab=prefab,components={},events={},Transform={GetWorldPosition=function() return 0,0,0 end}}
    function e:IsValid() return true end
    function e:IsInLimbo() return false end
    function e:IsAsleep() return false end
    function e:ListenForEvent(n,fn) self.events[n]=fn end
    function e:StopBrain(reason) self.reason=reason end
    function e:RestartBrain(reason) assert(self.reason==reason);self.reason=nil end
    e.components.health={IsDead=function() return false end}
    local t={IsValid=function() return true end,GetDistanceSqToPoint=function() return e.distance or 1 end,
        GetPhysicsRadius=function() return .5 end}
    local c={inst=e,target=t,InCooldown=function() return e.cooldown end,DoAttack=function() end,
        CanTarget=function() return not e.illegal end,CanAttack=function() return not(e.cooldown or e.illegal) end,
        IsValidTarget=function() return not e.illegal end,canattack=true,
        CalcAttackRangeSq=function() return 4 end}
    e.components.combat=c;components.combat(c)
    if prefab=="spat" then
        c.attackrange=3
        c.ResetCooldown=function() error("fog cannot reset spat cooldown") end
        e.weaponitems={meleeweapon={IsValid=function() return true end,components={
            weapon={attackrange=.5},equippable={IsEquipped=function() return e.equipped end}}}}
        e.components.inventory={Equip=function(_,item)
            assert(item==e.weaponitems.meleeweapon)
            e.equips=(e.equips or 0)+1;e.equipped=true
        end}
    end
    return e
end
for _,name in ipairs({"klaus","warg","mutatedwarg","leif","leif_sparse","spiderqueen","beequeen","spat"}) do
    local e=make(name)
    assert(Boss.select(e).first=="attack")
    e.cooldown=true;local move,blocked=Boss.select(e);assert(not move and blocked)
    e.components.combat.target=nil;move,blocked=Boss.select(e);assert(not move and not blocked,"no enemy is not a cooldown")
    e=make(name);e.distance=100;move,blocked=Boss.select(e);assert(not move and not blocked,"out of range is not a cooldown")
    e=make(name);e.illegal=true;move,blocked=Boss.select(e);assert(not move and not blocked)
end
local sheep=make("spat")
sheep.distance=16
assert(Boss.select(sheep) and not sheep.equipped,"prospective native melee range includes target radius without equipping")
sheep.distance=16.01
assert(not Boss.select(sheep),"current launcher range must not authorize melee")
sheep.distance=1;sheep.cooldown=true
assert(not Boss.select(sheep) and not sheep.equipped)
local descriptors={};require("nw/dark_fog_boss_extra").add_specs(descriptors)
assert(not descriptors.spat.prepare(sheep) and not sheep.equipped)
sheep.cooldown=false
assert(descriptors.spat.prepare(sheep) and sheep.equips==1)
assert(descriptors.spat.prepare(sheep) and sheep.equips==1)
sheep.weaponitems.meleeweapon=nil
assert(not Boss.select(sheep) and not descriptors.spat.prepare(sheep))
local pig=make("daywalker2")
assert(not Boss.select(pig));pig.canswing=true;assert(not Boss.select(pig));pig.hostile=true
assert(Boss.select(pig).first=="attack_swing")
for _,field in ipairs({"buried","defeated"}) do pig[field]=true;assert(not Boss.select(pig));pig[field]=nil end
pig.cooldown=true;local _,blocked=Boss.select(pig);assert(blocked)
pig.canswing=false;_,blocked=Boss.select(pig);assert(not blocked,"missing equipment is not cooldown")
local lunar=make("alterguardian_phase4_lunarrift")
assert(not Boss.select(lunar));lunar.dashcombo=1
assert(Boss.select(lunar).first=="dash_pre","first phase must not unlock slam")
lunar.slamcombo=1;assert(Boss.select(lunar).first=="slam")
lunar.cooldown=true;assert(select(2,Boss.select(lunar)))

-- One shared stategraph routes each prefab to its own explicit descriptor.
local graph={states={attack={name="attack",tags={attack=true},onenter=function() end}}}
hooks.warg(graph)
for _,name in ipairs({"warg","mutatedwarg"}) do
    local e=make(name)
    e.sg={sg=graph,currentstate={name="idle",tags={idle=true}},statemem={},mem={}}
    function e.sg:HasStateTag(t) return self.currentstate.tags[t] end
    function e.sg:GoToState(n)
        if self.currentstate.onexit then self.currentstate.onexit(e,n) end
        self.currentstate=graph.states[n];self.statemem={};self.currentstate.onenter(e)
    end
    assert(Boss.supports(e) and Boss.update(e,0,true))
    assert(e._nw_fog_boss_cast.spec~=nil and e._nw_fog_boss_cast.move.single)
    local spec=e._nw_fog_boss_cast.spec
    local extras={};require("nw/dark_fog_boss_extra").add_specs(extras)
    assert(extras.warg~=extras.mutatedwarg)
    e.sg.currentstate.onexit(e,"idle");assert(not e._nw_fog_boss_cast and not e.reason)
end

-- The real submit path equips once, immediately before the native SG enters.
local spatgraph={states={attack={name="attack",tags={attack=true},onenter=function(e)
    assert(e.equipped and e.equips==1,"spat melee must be equipped before attack onenter")
end}}}
hooks.spat(spatgraph)
local e=make("spat")
e.sg={sg=spatgraph,currentstate={name="idle",tags={idle=true}},statemem={},mem={}}
function e.sg:HasStateTag(t) return self.currentstate.tags[t] end
function e.sg:GoToState(n)
    if self.currentstate.onexit then self.currentstate.onexit(e,n) end
    self.currentstate=spatgraph.states[n];self.statemem={};self.currentstate.onenter(e)
end
assert(Boss.supports(e) and Boss.select(e) and not e.equipped)
assert(Boss.update(e,0,true) and e.equips==1 and e._nw_fog_boss_cast.move.single)
e.sg.currentstate.onexit(e,"idle");assert(not e._nw_fog_boss_cast and not e.reason)

-- Fissure updates can outlive the original slam. Use the actual core ready()
-- gate while isolating the native closure/tracking seam with a named fixture.
local Extra=require("nw/dark_fog_boss_extra")
local saved=Extra.install_fissure
local owner={IsValid=function() return true end}
local pending={world=TheWorld,owner=owner,move={slam=true},pending_coverage=true}
Extra.install_fissure=function(inst,ctx)
    assert(ctx.dispatch and ctx.ready)
    ctx.dispatch=function(boss,state) assert(boss==owner and state=="slam");return pending end
    ctx.active=function() error("fissures must capture dispatch provenance before coverage") end
    return saved(inst,ctx)
end
local fixture=assert(loadstring([[
    local function OnUpdate(inst) inst.updates=(inst.updates or 0)+1;return "native-update" end
    local function OnAnimOver(inst) return OnUpdate(inst) end
    return function(inst) return OnAnimOver(inst) end
]],"@scripts/prefabs/alterguardian_lunar_fissures.lua"))()
local fissure={OnLoad=fixture,Transform={GetWorldPosition=function() return 5,0,6 end},
    IsAsleep=function() return false end,
    StartTrackingBoss=function(inst,boss) inst.tracked=boss;return "native-tracking" end}
local boxes=0
package.loaded["nw/dark_fog"].disperse_box=function(_,x,z,w,h)
    assert(x==5 and z==6 and w==2 and h==2);boxes=boxes+1
end
fog=false;prefabs.alterguardian_lunar_fissures(fissure);Extra.install_fissure=saved
assert(fissure:StartTrackingBoss(owner)=="native-tracking" and fissure.tracked==owner)
assert(fissure:OnLoad()=="native-update" and boxes==0 and pending.pending_coverage)
fog=true;assert(fissure:OnLoad()=="native-update" and boxes==1 and not pending.pending_coverage)
fog=false;fissure:OnLoad();assert(boxes==2 and fissure.updates==3,
    "late coverage arms the original fissure batch and later native ticks survive self-clear")
