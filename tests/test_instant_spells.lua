-- Exercise the compiler and executor together. The fake electric weapon records
-- base damage before DST's own modifiers; the dedicated lab compares a nightstick.
local Compiler=require("nw/compiler")
local Executor=require("nw/executor")
DEGREES=math.pi/180
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
local landings,spans={},{}
local now,targets,arcs,blasts,carriers=0,{},{},{},{}
GetTime=function() return now end
TheWorld={}
TheSim={FindEntities=function() return targets end}
local owner={GUID=99,IsValid=function() return true end,components={combat={}}}
function owner.components.combat:CanTarget() return true end
function owner.components.combat:DoAttack(e,weapon,projectile,_,_,range,origin)
    assert(weapon==projectile and range==6)
    arcs[#arcs+1]={e.GUID,weapon.damage,origin.x,origin.z}
    e.components.health.currenthealth=e.components.health.currenthealth-weapon.damage
end
local function target(x,z)
    local h={currenthealth=200,IsDead=function(self) return self.currenthealth<=0 end}
    local e={GUID=#targets+1,GetPhysicsRadius=function() return .5 end,components={health=h,combat={}},
        IsValid=function() return true end,IsInLimbo=function() return false end,HasTag=function() return false end,
        Transform={GetWorldPosition=function() return x,0,z end},
        GetDistanceSqToPoint=function(_,px,_,pz) return (px-x)^2+(pz-z)^2 end}
    function e.components.combat:GetAttacked(_,d) h.currenthealth=h.currenthealth-d end
    targets[#targets+1]=e
    return e
end
SpawnPrefab=function(name)
    local fx={}
    fx.Transform={SetPosition=function(_,x,_,z) fx.x=x;fx.z=z end}
    if name=="nw_arc_fx" then
        fx.components={weapon={SetDamage=function(_,d) fx.damage=d end}}
        function fx:SetSpan(dx,dz,e) spans[#spans+1]={dx,dz,e} end
    elseif name=="nw_ground_shock_fx" then
        landings[#landings+1]=fx
    elseif name=="nw_blast_fx" then
        function fx:SetRadius(r) assert(r==3);blasts[#blasts+1]={self.x,self.z} end
    else
        assert(name=="nw_projectile")
        fx._shot={}
        function fx:Launch(_,p,_,_,_,_,cleanup) self.cleanup=cleanup end
        carriers[#carriers+1]=fx
    end
    return fx
end
local function cast(ids,x,z)
    now=now+1
    local w=require("nw/generator").starter()
    w.stats.mana_max=600;w.stats.spread=0;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={card_uid=tostring(i),spell_id=id} end
    w.runtime=Compiler.initial(w.cards,w.stats,1)
    local plan=assert(Compiler.compile(w))
    assert(Executor.execute(plan,owner,x,z,1,0))
    return plan
end
target(-1,0)
for x=6,30,6 do target(x,0) end
local plan=cast({"chain","arrow"},0,0)
assert(plan.mana_spent==14 and plan.projectile_count==1 and #carriers==0 and #arcs==4)
for i,arc in ipairs(arcs) do
    assert(arc[1]==i+1 and arc[2]==(i==1 and 15 or 10) and arc[3]==6*(i-1))
end
targets={};arcs={}
local random=math.random
math.random=function() return .5 end
landings={}
local distant=target(6.01,0);cast({"chain"},0,0)
assert(#arcs==1 and arcs[1][2]==10 and distant.components.health.currenthealth==190)
assert(#landings==4 and landings[1].x==0 and landings[2].x==6 and Executor.stats()==0)
targets={};arcs={};landings={};spans={}
math.random=function() return 1 end
cast({"chain"},0,0)
assert(#landings==5 and #spans==4)
for _,span in ipairs(spans) do
    assert(math.abs(math.atan2(span[2],span[1])/DEGREES-85)<.001)
    assert(math.abs(span[1]^2+span[2]^2-36)<.001 and span[3]==nil)
end
math.random=random
targets={};local single=target(1,0);cast({"chain"},0,0)
assert(#arcs==1 and single.components.health.currenthealth==185)
targets={};arcs={};local closest=target(11,0);local hit=target(12,0)
cast({"pierce","arrow_hit","chain"},0,0)
local carrier=carriers[1]
carrier._shot.fire(11,0,1,0,hit)
assert(arcs[1][1]==hit.GUID and arcs[2][1]==closest.GUID)
hit.components.health.currenthealth=0
carrier._shot.fire(11,0,1,0,hit)
assert(#arcs==3 and arcs[3][1]==closest.GUID)
carrier.cleanup();assert(Executor.stats()==0)
-- Explosion is now a modifier and cannot be emitted as an instant payload.
local p=cast({"explosion","arrow"},0,0)
assert(p.projectile_count==1 and p.blocks[1].projectiles[1].flags.explosive_hit)
carriers[#carriers].cleanup()
p=cast({"arrow_timer","explosion"},0,0)
assert(#p.blocks[2].projectiles==0)
carriers[#carriers].cleanup()
assert(Executor.stats()==0)
print("instant spells: native lightning, target priority and explosion modifier classification")
