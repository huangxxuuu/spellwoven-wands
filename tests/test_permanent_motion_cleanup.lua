RemovePhysicsColliders=function(e) e.no_terrain_collision=true end
local Limits=require("nw/spell_limits")
local Cleanup=require("nw/permanent_motion_cleanup")
local Stored=require("nw/persistent_fields")
local Motion=require("nw/field_motion")
FRAMES=1/30;DEGREES=math.pi/180
local now,tasks,cancelled,probes,active_region
GetTime=function() return now end
local function world(time)
    now=time or 0;tasks={};cancelled=0;AllPlayers={}
    probes={};active_region=function() return false end
    TheWorld={events={}}
    function TheWorld:DoPeriodicTask(period,fn)
        local task={period=period,fn=fn,Cancel=function(self) self.cancelled=true;cancelled=cancelled+1 end}
        tasks[#tasks+1]=task;return task
    end
end
CreateEntity=function()
    local probe={valid=true,sleepstatepending=true,events={},entity={}}
    function probe.entity:AddTransform() end
    function probe.entity:SetCanSleep(v) assert(v==true) end
    function probe:IsValid() return self.valid end
    function probe:IsAsleep() return self.asleep end
    function probe:Remove() self.valid=false end
    function probe:ListenForEvent(name,fn) self.events[name]=fn end
    probe.Transform={SetPosition=function(_,x,y,z) probe.x,probe.z=x,z end}
    probes[#probes+1]=probe
    return probe
end
local function engine()
    for _,probe in ipairs(probes) do
        if probe.valid then
            local asleep=not active_region(probe.x,probe.z)
            if probe.sleepstatepending or asleep~=probe.asleep then
                probe.asleep=asleep
                probe.events[asleep and "entitysleep" or "entitywake"]()
                probe.sleepstatepending=nil
            end
        end
    end
end
local guid=0
local function entity(id,speed,absent)
    guid=guid+1
    local e={GUID=guid,valid=true,x=1000,z=1000,events={},components={}}
    if id then
        e._nw_stored={p={id=id,speed=speed or 0,flags={},field_drive=true},dx=1,dz=0,order=guid,
            owner_key="fixture",cleanup_absent=absent}
    end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetRotation=function() end}
    e.Physics={Stop=function() end,ClearCollisionMask=function() end,SetMotorVel=function() end}
    e.AnimState={PlayAnimation=function() end,PushAnimation=function() end,SetScale=function() end}
    e.entity={SetCanSleep=function() end}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return self.limbo end
    function e:HasTag(tag) return tag=="playerghost" and self.ghost end
    function e:ListenForEvent(name,fn,source)
        source=source or self;source.events[name]=source.events[name] or {}
        table.insert(source.events[name],fn)
    end
    function e:Remove()
        assert(self.valid,"double remove");self.valid=false
        for _,fn in ipairs(self.events.onremove or {}) do fn(self) end
    end
    function e:DoPeriodicTask() end
    function e:DoTaskInTime() end
    e._nw_break=function() error("cleanup must not detonate or release payloads") end
    return e
end
local function moving(id,absent)
    local e=entity(id or "payload_egg",6,absent)
    -- Use the actual field registration path, including ownerless placements.
    Motion.start(e,nil,e._nw_stored.p,1,0)
    engine()
    return e
end
local function tick(t)
    now=t
    local pool=TheWorld._nw_permanent_motion_cleanup
    if pool then for inst in pairs(pool.items) do Cleanup.sync(inst) end end
    engine()
    for _,task in ipairs(tasks) do if not task.cancelled then task.fn(TheWorld) end end
end
local function count() local p=TheWorld._nw_permanent_motion_cleanup;return p and p.count or 0 end

world()
assert(not Limits.permanent_motion_cleanup)
local disabled=moving();tick(2000)
assert(disabled.valid and count()==0 and #tasks==0,"disabled adds no collector task")
assert(#probes==0,"disabled allocates no engine probes")
Limits.permanent_motion_cleanup=true
world()
local static=entity("sleep_crystal",0)
Motion.start(static,nil,static._nw_stored.p,1,0)
local star=entity();star._nw_motion_owner=function() return nil end
Motion.start(star,nil,{speed=6,flags={},field_drive=true},1,0)
assert(count()==0 and #tasks==0,"static fields and finite-lived stars are excluded")

local list={}
for i=1,20 do list[i]=moving(i%2==0 and "sleep_crystal" or "payload_egg") end
assert(count()==20 and #tasks==1 and tasks[1].period==1)
Cleanup.watch(list[1]);assert(count()==20,"registration is idempotent")
tick(960);assert(count()==20,"exactly twenty never starts collection")
assert(Cleanup.elapsed(list[1])==960,"absence accumulates independently below the count threshold")
list[21]=moving("crystal_mine")
tick(961)
assert(count()==1 and list[21].valid,"one pass removes all old candidates, not just down to twenty")
for i=1,20 do assert(not list[i].valid) end
list[21]:Remove();assert(count()==0 and cancelled==1 and not TheWorld._nw_permanent_motion_cleanup.task)
for _,probe in ipairs(probes) do assert(not probe.valid and probe.persists==false) end

world()
list={};for i=1,21 do list[i]=moving() end
tick(959.99);assert(count()==21,"never delete young entities to meet a count cap")
tick(960);assert(count()==0 and cancelled==1,"sixteen minutes is 960 simulation seconds")

-- Native active regions determine protection; no fixed player-distance test.
world()
active_region=function() return true end
list={};for i=1,21 do list[i]=moving() end
tick(900);assert(count()==21 and Cleanup.elapsed(list[1])==0,"native active area")
active_region=function() return false end;engine()
tick(1859.9);assert(count()==21)
tick(1860);assert(count()==0,"leaving player range starts a fresh uninterrupted interval")

-- Each probe follows its own spell, without inheriting its forced-awake state.
world()
active_region=function(x) return x<1500 end
list={};for i=1,21 do list[i]=moving() end
list[21].x=2000;Cleanup.sync(list[21]);engine()
tick(960)
assert(count()==20 and not list[21].valid and list[1].valid)
for i=1,20 do list[i]:Remove() end
assert(cancelled==1)

-- Even a brief native wake between collection ticks resets the clock.
world();list={};for i=1,21 do list[i]=moving() end
now=959.5;active_region=function() return true end;engine()
now=959.6;active_region=function() return false end;engine()
tick(960);assert(count()==21)
tick(1919.59);assert(count()==21)
tick(1919.61);assert(count()==0)

-- Save an elapsed duration, then restore it on a fresh simulation clock.
world()
local capped=moving()
Stored.install(capped)
tick(1199);assert(Cleanup.elapsed(capped)==1199)
tick(1200);assert(capped._nw_cleanup_state.absent==1200)
tick(1000000);assert(capped._nw_cleanup_state.absent==1200,"runtime counter stops at twenty minutes")
local capped_save={};capped:OnSave(capped_save)
assert(capped_save.placement.cleanup_absent==1200,"save preserves the twenty-minute cap")
capped:Remove()
world(10)
capped=entity();Stored.install(capped);capped:OnLoad(capped_save);engine()
assert(Cleanup.elapsed(capped)==1200,"load preserves a saturated counter")
active_region=function() return true end;engine()
assert(Cleanup.elapsed(capped)==0,"native wake resets the saturated counter")
active_region=function() return false end;engine()
tick(70);assert(Cleanup.elapsed(capped)==60,"sleep starts a new accumulation after reset")
local oversized=moving("payload_egg",1e30)
assert(oversized._nw_cleanup_state.absent==1200,"oversized saved durations are clamped on load")

world()
local saved_entity=moving("payload_egg")
Stored.install(saved_entity)
tick(600)
local data={};saved_entity:OnSave(data)
assert(data.placement.cleanup_absent==600)
saved_entity:Remove()
world(10)
local restored=entity()
Stored.install(restored);restored:OnLoad(data)
assert(count()==1 and Cleanup.elapsed(restored)==600)
for i=1,20 do moving() end
tick(369.99);assert(restored.valid)
tick(370);assert(not restored.valid and count()==20,"restart preserves elapsed time without counting downtime")

-- A nearby player at load resets the saved timer, and disabling drops it on save.
world()
active_region=function() return true end
restored=entity();Stored.install(restored);restored:OnLoad(data)
assert(restored._nw_cleanup_state.probe.sleepstatepending)
assert(Cleanup.elapsed(restored)==600,"initial awake placeholder must not erase saved absence")
engine()
assert(Cleanup.elapsed(restored)==0)
Limits.permanent_motion_cleanup=false
local off={};restored:OnSave(off);assert(off.placement.cleanup_absent==nil)
tick(2000);assert(restored.valid)
print("permanent motion cleanup: native sleep probes, independent count/absence, brief wakes, pending initialization, save/load and silent cleanup")
