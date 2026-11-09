RemovePhysicsColliders=function(e) e.no_terrain_collision=true end
local L=require("nw/spell_limits")
local B=require("nw/world_bounds")
L.boundary_cleanup=true
FRAMES=1/30;TILE_SCALE=4;DEGREES=math.pi/180
GROUND={WALL_CAVE=154}
local now=0
GetTime=function() return now end
local wall=false
local function tile(x,z)
    if x>=-12 and x<12 and z>=-12 and z<12 then return x<0 and 2 or 201 end
    if wall and x>=12 and x<16 and z>=-12 and z<12 then return 154 end
    return 1
end
local map={}
function map:GetTileAtPoint(x,y,z) return tile(x,z) end
function map:IsAboveGroundAtPoint(x,y,z,water) local t=tile(x,z);return t==2 or water and t==201 end
function map:IsPassableAtPoint(x,y,z,water) return self:IsAboveGroundAtPoint(x,y,z,water) end
function map:IsImpassableTileAtPoint(x,y,z) local t=tile(x,z);return t==1 or t==154 end
function map:GetSize() return 20,20 end
function map:GetTileCoordsAtPoint(x,y,z) return math.floor(x/4)+10,math.floor(z/4)+10 end
function map:GetTileCenterPoint(x,z) return (x-9.5)*4,0,(z-9.5)*4 end
local tasks,cancelled={},0
TheWorld={Map=map,flying=true,CanFlyingCrossBarriers=function(self) return self.flying end}
function TheWorld:DoPeriodicTask(period,fn)
    local task={fn=fn,period=period,Cancel=function(self) self.cancelled=true;cancelled=cancelled+1 end}
    tasks[#tasks+1]=task;return task
end
local function frame()
    now=now+FRAMES
    for _,task in ipairs(tasks) do if not task.cancelled then task.fn(TheWorld) end end
end
assert(not B.outside(-1,0) and not B.outside(1,0),"coast is inside the world")
assert(not B.outside(16.999,0) and B.outside(17,0))
assert(not B.outside(-16.999,0) and B.outside(-17,0))
assert(not B.outside(14.9,15.9) and B.outside(15,16),"corner margin uses Euclidean distance")
assert(B.outside(1000,0),"far beyond the rectangular tile grid")
local f=B.clip(0,0,100,0)
assert(f and math.abs(f*100-17)<.001,"fast flight stops at the first exit")
wall=true
f=B.clip(0,0,100,0);assert(f and math.abs(f*100-12)<.001)
assert(B.outside(12,0),"explicit natural wall has no margin")
wall=false;TheWorld.flying=false
assert(B.outside(12,0),"cave impassable terrain is a natural barrier")
TheWorld.flying=true
L.boundary_cleanup=false
assert(not B.outside(1000,0) and not B.clip(0,0,1000,0))
L.boundary_cleanup=true

local function entity(x,z)
    local e={x=x or 0,z=z or 0,valid=true,events={},components={}}
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetRotation=function() end}
    e.Physics={Stop=function() end,SetMotorVel=function(_,v) e.speed=v end,ClearCollisionMask=function() e.no_terrain_collision=true end}
    e.entity={SetCanSleep=function(_,v) e.can_sleep=v end}
    function e:IsValid() return self.valid end
    function e:HasTag() return false end
    function e:ListenForEvent(name,fn) self.events[name]=self.events[name] or {};table.insert(self.events[name],fn) end
    function e:Remove()
        assert(self.valid,"double remove")
        self.valid=false
        for _,fn in ipairs(self.events.onremove or {}) do fn(self) end
    end
    function e:DoPeriodicTask() end
    return e
end
local a,b=entity(),entity(5,0)
assert(B.watch(a) and B.watch(a) and B.watch(b) and #tasks==1)
a.x=16.9;frame();assert(a.valid and b.valid)
a.x=17;frame();assert(not a.valid and b.valid and cancelled==0)
b:Remove();assert(cancelled==1 and next(TheWorld._nw_boundary_entities.items)==nil)
local restored=entity(40,0)
assert(not B.watch(restored) and not restored.valid,"saved off-map field removed on load")

local owner=entity();owner.GUID=100;owner.components.combat={CanTarget=function() return true end}
local moving=entity()
require("nw/field_motion").start(moving,owner,{speed=6,field_drive=true,flags={}},1,0)
assert(moving.no_terrain_collision and moving.can_sleep==false and moving.speed==6)
moving.x=100;frame();assert(not moving.valid,"permanent field cannot escape cleanup")
local paused=entity();paused._nw_motion_owner=function() return nil end
require("nw/field_motion").start(paused,nil,{speed=6,field_drive=true,flags={}},1,0)
assert(paused.speed==0)
paused.x=100;frame();assert(not paused.valid,"cleanup also works while owner is absent")
L.boundary_cleanup=false
local unchecked=entity()
require("nw/field_motion").start(unchecked,owner,{speed=6,field_drive=true,flags={}},1,0)
unchecked.x=100;frame();assert(unchecked.valid)
L.boundary_cleanup=true

-- Exercise the real executor's reservation cleanup, including unused payloads.
local E=require("nw/executor")
local P=require("nw/projectiles")
TheSim={FindEntities=function() return {} end}
local projectile
SpawnPrefab=function(name)
    assert(name=="nw_end_beam","boundary must not manufacture a terminal effect")
    local e=entity()
    function e:Launch(caster,p,x,z,dx,dz,cleanup)
        self:ListenForEvent("onremove",cleanup)
        self._shot={owner=caster,p=p,dx=dx,dz=dz,x=x,z=z,time=now,age=0,remaining=10,travelled=0,damage=0}
    end
    projectile=e;return e
end
local fired=0
local effect=require("nw/spell_effects")
effect.blast=function() fired=fired+1 end
local plan={projectile_count=2,next_state={rng_state=1},blocks={
    {projectiles={{id="end_beam",kind="projectile",event="hit",payload=2,end_damage=16,flags={},spread=0}}},
    {projectiles={{id="explosion",kind="instant",flags={},spread=0,damage=16,radius=2}}},
}}
assert(E.execute(plan,owner,0,0,1,0,1.4) and E.stats()==1)
projectile.x=100;P.step(projectile,now+1,{})
assert(not projectile.valid and E.stats()==0 and fired==0,"boundary cleanup releases carrier and reserved child silently")
-- A timer beyond the boundary is neither reached nor flushed on removal.
plan.blocks[1].projectiles[1].event="timer";plan.blocks[1].projectiles[1].time=.5
assert(E.execute(plan,owner,0,0,1,0,1.4))
projectile.x=100;P.step(projectile,now+1,{})
assert(not projectile.valid and E.stats()==0 and fired==0)
-- Terminal blink in the five-unit buffer must not teleport the caster.
TheWorld.Map.IsOceanAtPoint=function() return false end
owner.Physics.Teleport=function() error("teleport into void") end
require("nw/engraved_impact").finish({owner=owner,p={engraving="orangestaff"}},14,0)
print("world bounds: coast/ocean, void margin/corners, natural barriers, fast sweep, restored and ownerless fields, idle cleanup, reservations and silent removal")
