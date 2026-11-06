local fades=0
SpawnPrefab=function(name)
    assert(name=="round_puff_fx_sm");fades=fades+1
    return {Transform={SetPosition=function() end}}
end
local P=require("nw/projectiles")
local Limits=require("nw/spell_limits")
local perf=require("nw/perf")
local queries=0;local candidates={};local passable=true
local ocean=false
TheWorld={Map={IsPassableAtPoint=function(_,x,y,z,water) return passable and (not ocean or water and x>=0) end}}
TheSim={FindEntities=function(_,x,y,z,r,must,exclude,include)
    assert(include[1]=="_combat" and include[2]=="wall")
    queries=queries+1;return candidates
end}
local owner={IsValid=function() return true end,components={combat={CanTarget=function() return true end}}}
local function target(id,x,z,wall)
    local t={GUID=id,x=x,z=z,alive=true,valid=true,hits=0,components={}}
    t.components.health={IsDead=function() return not t.alive end}
    t.components.combat={GetAttacked=function(_,o,d) assert(o==owner);t.hits=t.hits+d end}
    t.Transform={GetWorldPosition=function() return t.x,0,t.z end}
    function t:IsValid() return self.valid end
    function t:IsInLimbo() return false end
    function t:HasTag(tag) return tag=="wall" and wall or false end
    function t:GetPhysicsRadius() return .5 end
    return t
end
local function shot(nx,nz,remaining,travelled)
    local p={_shot={owner=owner,x=0,z=0,time=0,remaining=remaining or 1,travelled=travelled or 0,damage=20}}
    p.Transform={GetWorldPosition=function() return nx,1.5,nz end}
    p.Transform.SetRotation=function() end
    p.Physics={SetMotorVel=function() end}
    function p:Remove() self.removed=true end
    return p
end
-- Fast sweep hits the first target even when both endpoints are outside it.
local lingering=shot(0,0,12)
P.step(lingering,8,{})
assert(not lingering.removed and lingering._shot.remaining==4,"no runtime 7.5-second cap")
P.step(lingering,12,{})
assert(lingering.removed,"extended projectile still expires at its own deadline")
local airborne=shot(1,0,.05)
airborne._shot.p={id="edge_chum",engraving="chum",ballistic=true,flags={}}
P.step(airborne,.1,{})
assert(airborne.removed,"shortened airborne projectile must expire without a ground impact")
fades=0
local near=target(2,2,0);local far=target(1,4,0)
candidates={far,near};local p=shot(6,0);P.step(p,.1,{})
assert(p.removed and near.hits==20 and far.hits==0)
-- Nearest wall blocks damage; dead/removed candidates cached earlier are skipped.
local wall=target(3,1,0,true);candidates={near,wall};P.step(shot(6,0),.1,{})
assert(near.hits==20 and fades==0);wall.alive=false;near.valid=false
p=shot(6,0);P.step(p,.1,{});assert(not p.removed)
-- A shared spatial cache reduces queries without caching eligibility or hits.
near.valid=true;candidates={near};local cache={};queries=0
P.step(shot(3,0),.1,cache);near.alive=false;P.step(shot(3,0),.1,cache)
assert(queries==1 and near.hits==40)
-- Three simulation frames per target. A second projectile has its own history.
local overlap=target(30,0,0);candidates={overlap}
for n=1,2 do
    local staying=shot(0,0);local s=staying._shot
    s.hit={};s.hits_left=3
    for frame=1,7 do
        P.step(staying,frame/30,{})
        local expected=math.floor((frame-1)/3)+1
        assert(overlap.hits==(3*(n-1)+expected)*20,"per-projectile rehit timing")
    end
    assert(staying.removed,"basic pierce must stop after three hits")
end
-- End-of-life/range cannot hit a target beyond the permitted final segment.
near.alive=true;near.x=8;candidates={near}
p=shot(10,0,.05);P.step(p,.1,{});assert(p.removed and near.hits==40)
Limits.range=30
p=shot(10,0,1,25);P.step(p,.1,{});assert(p.removed and near.hits==40)
-- Travel beyond the old 20-unit cap, but never hit beyond the new 30-unit cap.
candidates={};p=shot(25,0);P.step(p,.1,{});assert(not p.removed and p._shot.travelled==25)
near.x=25;candidates={near};p=shot(28,0);P.step(p,.1,{});assert(p.removed and near.hits==60)
near.x=32;p=shot(35,0);P.step(p,.1,{});assert(p.removed and near.hits==60)
ocean=true;candidates={};p=shot(4,0);P.step(p,.1,{});assert(not p.removed and p._shot.x==4);ocean=false
-- Defaults ignore the former 30-unit cap and legacy per-shot max_range data.
Limits.range=0;candidates={}
p=shot(100,0,10,400);p._shot.p={flags={},max_range=30}
P.step(p,1,{});assert(not p.removed and p._shot.travelled==500)
near.x=95;candidates={near};p=shot(100,0,10)
P.step(p,1,{});assert(p.removed and near.hits==80)
Limits.range=60;candidates={};p=shot(80,0,10)
P.step(p,1,{});assert(p.removed and p._shot.x==60)
Limits.range=0
-- Re-score forward intercepts every search, including when the old one is alive.
local seeker={owner=owner,x=0,z=0,heading=0,speed=15,hit={}}
local back=target(10,-.6,0);local front=target(11,4,0)
local side=target(12,1,3)
candidates={back,side,front}
local ticktime=0
GetTime=function() return ticktime end;DEGREES=math.pi/180
local F=require("nw/flight")
local f={radius=8,turn_rate=240}
assert(F.seek(seeker,f)==front)
seeker.age=0;seeker.hit[front]=.10;assert(F.seek(seeker,f)==side)
seeker.age=.10;assert(F.seek(seeker,f)==front)
side.x=-1;seeker.hit[front]=nil;seeker.heading=math.pi
assert(F.seek(seeker,f)==back)
local defs=require("nw/definitions").spells
local body={Transform={SetRotation=function() end},Physics={SetMotorVel=function(self,v) self.speed=v end}}
local function flight(flag)
    local s={owner=owner,p={flags={[flag]=defs[flag]}},speed=25,hit={},age=0,x=0,z=0}
    F.reset(s,1,0);return s
end
for _,flag in ipairs({"sine","spiral"}) do
    local s=flight(flag)
    local peak,reverse=0,false
    for i=1,30 do
        assert(F.steer(body,s,1/30))
        s.x=s.x+s.dx*body.Physics.speed/30;s.z=s.z+s.dz*body.Physics.speed/30
        peak=math.max(peak,math.abs(s.z));reverse=reverse or s.dx<0
    end
    assert(peak>1 and (flag~="spiral" or reverse),"curve too small / missing loop")
end
local s=flight("homing")
candidates={back};ticktime=1
F.steer(body,s,1/30);assert(s.seek_states.homing.target==back)
candidates={front,back};s.age=.099;ticktime=2
F.steer(body,s,1/30);assert(s.seek_states.homing.target==back)
s.age=.10
F.steer(body,s,1/30);assert(s.seek_states.homing.target==front,"kept old rear target when a front target became available")
-- A returning orbit may exceed 30 units of cumulative path and still fly.
candidates={};p=shot(2,0,4,31)
p._shot.p={flags={orbit={}}};p._shot.owner.Transform={GetWorldPosition=function() return 0,0,0 end}
p._shot.speed=15;p._shot.phase=0;p._shot.offx=0;p._shot.offz=0;p._shot.heading=0
p.Physics={SetMotorVel=function() end};p.Transform.SetRotation=function() end
P.step(p,.1,{});assert(not p.removed)
-- Broad-phase circle conservatively encloses every swept hit circle, including
-- negative coordinates and different segment lengths in a single cache cell.
math.randomseed(123)
for i=1,1000 do
    local x,z=math.random()*40-20,math.random()*40-20
    local nx,nz=x+math.random()*6-3,z+math.random()*6-3
    P.candidates({},x,z,nx,nz,function(cx,_,cz,r)
        assert(math.sqrt((x-cx)^2+(z-cz)^2)+3.12<=r+1e-8)
        assert(math.sqrt((nx-cx)^2+(nz-cz)^2)+3.12<=r+1e-8)
        return {}
    end)
end
-- All instances share one task, removed objects are pruned, idle task stops.
-- A harvesting scythe sweeps the whole strip and does not consume itself or
-- harvest a plant twice after a turn, even if the plant regrows immediately.
HARVESTABLE_PLANT_TARGET_TAGS={"plant"}
TheWorld.Map.IsOceanAtPoint=function() return false end
local function plant(id,x,z)
    local e=target(id,x,z)
    e.components.health=nil;e.components.combat=nil;e.picked=0
    e.HasOneOfTags=function() return true end
    e.GetPosition=function() return {x=x,y=0,z=z} end
    e.components.pickable={CanBePicked=function() return true end,Pick=function() e.picked=e.picked+1;return true,{} end}
    return e
end
owner.GetDistanceSqToPoint=function() return 0 end
local pa,pb,pc=plant(101,1,.9),plant(102,3,-.9),plant(103,2,1.5)
candidates={pa,pb,pc};p=shot(4,0,2)
p._shot.p={id="edge_voidcloth_scythe",engraving="voidcloth_scythe",flags={},no_impact_damage=true,hit_radius=.8}
p._shot.hits_left=math.huge;p._shot.hit={}
F.reset(p._shot,1,0);p._shot.speed=10
P.step(p,.4,{})
assert(pa.picked==1 and pb.picked==1 and pc.picked==0 and not p.removed)
p._shot.x=0;p._shot.z=0;P.step(p,.8,{})
assert(pa.picked==1 and pb.picked==1 and not p.removed)
p._shot.p.size_mult=2.5;p._shot.x=0;p._shot.z=0
P.step(p,1.2,{})
assert(pc.picked==1 and pa.picked==1 and pb.picked==1,"giant scythe must harvest the enlarged strip once")
P.candidates({},0,0,1,0,function(cx,_,cz,r)
    assert(math.sqrt(cx*cx+cz*cz)+3.8<=r+1e-8);return {}
end,{nature=true},.8)
local tick,scheduled,cancelled=nil,0,0
GetTime=function() return .1 end;FRAMES=1/30
TheWorld.DoPeriodicTask=function(_,_,fn) scheduled=scheduled+1;tick=fn;return {Cancel=function() cancelled=cancelled+1 end} end
local a={IsValid=function() return false end};local b={IsValid=function() return false end}
P.add(a);P.add(b);assert(scheduled==1)
tick(TheWorld);assert(cancelled==1 and #TheWorld._nw_projectiles.items==0)
P.add(a);assert(scheduled==2);tick(TheWorld)
print("projectiles: swept nearest hit/wall, stale candidates, lifetime/range clipping, conservative shared queries, idle cleanup")
