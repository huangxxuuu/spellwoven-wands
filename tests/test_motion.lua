RemovePhysicsColliders=function(e) e.no_terrain_collision=true end
local F=require("nw/flight")
local Motion=require("nw/field_motion")
local P=require("nw/projectiles")
local Copy=require("nw/util").copy
local D=require("nw/definitions").spells
FRAMES=1/30;DEGREES=math.pi/180
local now,candidates,guid=0,{},0
GetTime=function() return now end
TheWorld={};TheSim={FindEntities=function() return candidates end}
local function entity(x,z,tags)
    guid=guid+1
    local e={GUID=guid,x=x or 0,z=z or 0,valid=true,components={},events={},tags=tags or {},motor=0,rotation=0}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return false end
    function e:HasTag(t) return self.tags[t] end
    function e:GetPhysicsRadius() return .5 end
    function e:ListenForEvent(n,fn) self.events[n]=self.events[n] or {};table.insert(self.events[n],fn) end
    function e:Remove() self.valid=false;for _,fn in ipairs(self.events.onremove or {}) do fn(self) end end
    function e:DoPeriodicTask(_,fn) return {fn=fn,Cancel=function(self) self.cancelled=true end} end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetRotation=function(_,r) e.rotation=r end}
    e.Physics={Stop=function() end,SetMotorVel=function(_,v) e.motor=v end,ClearCollisionMask=function() end,
        Teleport=function(_,x,_,z) e.x,e.z=x,z end}
    e.entity={SetCanSleep=function(_,v) e.can_sleep=v end}
    e.components.health={IsDead=function() return false end}
    e.components.combat={CanTarget=function() return true end,GetAttacked=function() error("moving placements must not add impact damage") end}
    return e
end
local owner=entity(-20,0,{player=true});AllPlayers={owner}
local function descriptor(flags,speed,id)
    return {id=id or "sleep_crystal",kind="field",speed=speed or 0,flags=Copy(flags or {}),damage=22,spread=0}
end
local function field(p,permanent)
    local e=entity()
    if permanent then e._nw_stored={p=p};e._nw_owner=owner end
    Motion.start(e,owner,p,1,0)
    return e
end
local function frame(e,dt)
    now=now+dt
    e.x=e.x+math.cos(-e.rotation*DEGREES)*e.motor*dt
    e.z=e.z+math.sin(-e.rotation*DEGREES)*e.motor*dt
    P.step(e,now,{})
    if e._nw_motion and not e._nw_motion.stopped then Motion.settle(e,e._nw_motion) end
end
local function close(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..tostring(b)) end

-- Force guidance launches from rest; direction-only guidance cannot do that.
local enemy=entity(5,0);candidates={enemy}
local h=field(descriptor({homing=Copy(D.homing)},0),true)
frame(h,FRAMES);assert(h.motor>0 and h._nw_motion.vx>0)
local rot=field(descriptor({homing_rotate=Copy(D.homing_rotate)},0),true)
assert(not rot._nw_motion and rot.motor==0)
local function velocity(flags,speed,dt,steps)
    local e=entity();local s={owner=owner,p=descriptor(flags,speed),speed=speed,age=0,x=0,z=0,hit={}}
    F.reset(s,1,0)
    for i=1,steps do s.age=i*dt;F.steer(e,s,dt) end
    return s,e
end
local a=velocity({homing=Copy(D.homing)},0,1/30,30)
local b=velocity({homing=Copy(D.homing)},0,1/60,60)
close(a.vx,b.vx);assert(a.vx>10)
enemy.x=2
local near=velocity({homing_short=Copy(D.near_homing)},0,1/30,1)
local normal=velocity({homing=Copy(D.homing)},0,1/30,1)
assert(near.vx>normal.vx)
-- Sustained forward guidance approaches 50 without imposing a hard speed cap.
for _,card in ipairs({D.homing,D.near_homing}) do
    local flags={[card.flag]=Copy(card)}
    local steady=velocity(flags,2,1/30,1200)
    assert(steady.vx>49.99 and steady.vx<=50)
    local fast=velocity(flags,55,1/30,1)
    assert(fast.vx>50 and fast.vx<55,"guidance damps excess speed rather than clipping it")
end
enemy.x=5
local far=velocity({homing_short=Copy(D.near_homing)},0,1/30,1)
assert(far.vx==0,"short guidance does not act outside its range")
enemy.x,enemy.z=0,5
local turn,body=velocity({homing_rotate=Copy(D.homing_rotate)},6,1/30,1)
close(body.motor,6);close(math.atan2(turn.vz,turn.vx),12*DEGREES)
for _,flags in ipairs({{homing=Copy(D.homing)}, {homing_short=Copy(D.near_homing)},
    {homing=Copy(D.homing),homing_rotate=Copy(D.homing_rotate)}}) do
    enemy.z=2
    local guided=velocity(flags,2,1/30,1)
    assert(math.atan2(guided.vz,guided.vx)<=12*DEGREES+1e-9,"combined guidance must respect 360 degrees/s")
end

-- All paths use exactly the same steering function for a moving native star.
-- Guidance must see the same attackable egg/crystal props as collisions do,
-- regardless of creature/team selectors. Test real steering, not only selection.
for _,id in ipairs({"payload_egg","sleep_crystal"}) do
    local prop=entity(1,1,{nw_breakable=true})
    prop._nw_stored={p={id=id}};prop._nw_break=function() error("seeking cannot activate a prop") end
    for _,scope in ipairs({false,{friendly=true},{neutral=true},{building=true},
        {friendly=true,neutral=true,building=true}}) do
        for _,card in ipairs({D.homing,D.near_homing,D.weak_homing,D.homing_rotate}) do
            TheWorld._nw_scans=nil;candidates={prop}
            local guided=velocity({[card.flag]=Copy(card),targets=scope or nil},6,FRAMES,1)
            assert(guided.vz>0,id.." must attract "..card.id)
            assert(F.seek(guided,card)==prop)
            guided.hit[prop]=guided.age+.1
            assert(not F.seek(guided,card),"recent piercing contacts respect their cooldown")
            guided.hit[prop]=nil;prop.valid=false
            assert(not F.seek(guided,card),"removed props cannot attract shots")
            prop.valid=true
            prop._nw_motion=guided
            assert(not F.seek(guided,card),"moving spell props cannot home on themselves")
            prop._nw_motion=nil
            guided.p.id="gust"
            assert((F.seek(guided,card)==prop)==(id=="payload_egg"),"gust only interacts with eggs")
        end
    end
end
TheWorld._nw_scans=nil
candidates={}
for _,id in ipairs({"sine","spiral","orbit","reverse_path","return_path","accelerate"}) do
    local card=D[id];local flags={[card.flag]=Copy(card)}
    local e=field(descriptor(flags,6),false)
    local s={owner=owner,p=descriptor(flags,6),speed=6,age=0,x=0,z=0,hit={}}
    local bullet=entity();F.reset(s,1,0)
    for i=1,20 do
        e.x,e.z=0,0;s.x,s.z=0,0
        now=now+FRAMES;s.age=s.age+FRAMES
        P.step(e,now,{});F.steer(bullet,s,FRAMES)
        close(e.motor,bullet.motor);close(e.rotation,bullet.rotation)
    end
    e:Remove()
end

-- Permanent inertia halves in four seconds, saves velocity, and eventually
-- stops. A finite star retains its speed. Motion state is plain save data.
local inert=field(descriptor({},8),true)
for i=1,120 do frame(inert,FRAMES) end
close(inert.motor,4)
local saved=Motion.save(inert);assert(saved.vx==inert._nw_motion.vx and not saved.stopped)
local restored=entity();restored._nw_stored={p=inert._nw_motion.p};restored._nw_owner=owner
Motion.start(restored,owner,inert._nw_motion.p,1,0,inert._nw_motion.age,saved)
close(restored.motor,inert.motor)
for i=1,900 do if not restored._nw_motion.stopped then frame(restored,FRAMES) end end
assert(restored.valid and restored.motor==0 and restored._nw_motion.stopped and restored.can_sleep)
local star=field(descriptor({},8),false);frame(star,4);close(star.motor,8)

-- Persist a partially entered orbit so loading a moving placement continues
-- the same smooth radius and phase instead of restarting its entry.
local owner_x,owner_z=owner.x,owner.z
owner.x,owner.z=0,0
local orbiting=field(descriptor({orbit=Copy(D.orbit)},25),true)
for _=1,8 do frame(orbiting,FRAMES) end
local orbit_saved=Motion.save(orbiting)
assert(orbit_saved.orbit_radius and orbit_saved.orbit_radius>0)
local orbit_loaded=entity(orbiting.x,orbiting.z)
orbit_loaded._nw_stored={p=orbiting._nw_motion.p};orbit_loaded._nw_owner=owner
Motion.start(orbit_loaded,owner,orbiting._nw_motion.p,1,0,orbiting._nw_motion.age,orbit_saved)
close(orbit_loaded._nw_motion.orbit_radius,orbiting._nw_motion.orbit_radius)
close(orbit_loaded.motor,orbiting.motor);close(orbit_loaded.rotation,orbiting.rotation)
F.steer(orbiting,orbiting._nw_motion,FRAMES)
F.steer(orbit_loaded,orbit_loaded._nw_motion,FRAMES)
close(orbit_loaded.motor,orbiting.motor);close(orbit_loaded.rotation,orbiting.rotation)
orbiting:Remove();orbit_loaded:Remove()
owner.x,owner.z=owner_x,owner_z

-- Collision preserves the field. Pierce and wall reflection reuse bullet
-- contact ordering and budgets, without detonating the placement.
enemy.x,enemy.z=2,0;candidates={enemy}
local stopped=field(descriptor({},6),false);stopped.x=4
now=now+.1;P.step(stopped,now,{})
assert(stopped.valid and stopped.motor==0 and stopped._nw_motion.stopped and stopped.x<2)
local pierced=field(descriptor({pierce={hits=3}},6),false);pierced.x=4
now=now+.1;P.step(pierced,now,{})
assert(not pierced._nw_motion.stopped and pierced._nw_motion.hits_left==2)
enemy.tags.wall=true
local bounced=field(descriptor({bounce={bounces=2}},6),false);bounced.x=4
now=now+.1;P.step(bounced,now,{})
assert(bounced.valid and not bounced._nw_motion.stopped and bounced._nw_motion.dx<0 and bounced._nw_motion.vx<0)
local phased=field(descriptor({phase_wall={}},6),false);phased.x=4
now=now+.1;P.step(phased,now,{});assert(not phased._nw_motion.stopped)
-- Both floating stars cross walls without consuming pierce/bounce, including
-- building selection and a restored movement state. Other fields still stop.
for _,id in ipairs({"edge_yellowstaff","edge_opalstaff"}) do
    local p=descriptor({targets={building=true},bounce={bounces=2},pierce={hits=3}},6,id)
    local floating=field(p,false);floating.x=4
    now=now+.1;P.step(floating,now,{})
    assert(not floating._nw_motion.stopped and floating._nw_motion.vx>0 and floating.x==4)
    assert(floating._nw_motion.bounces==2 and floating._nw_motion.hits_left==3)
    local loaded=entity()
    Motion.start(loaded,owner,p,1,0,floating._nw_motion.age,Motion.save(floating))
    loaded.x=4;now=now+.1;P.step(loaded,now,{})
    assert(not loaded._nw_motion.stopped and loaded.x==4 and loaded._nw_motion.bounces==2)
end
local grounded=field(descriptor({},6),true);grounded.x=4
now=now+.1;P.step(grounded,now,{})
assert(grounded._nw_motion.stopped and grounded.x<2)
enemy.tags.wall=nil
for _,id in ipairs({"edge_yellowstaff","edge_opalstaff"}) do
    local floating=field(descriptor({},6,id),false);floating.x=4
    now=now+.1;P.step(floating,now,{})
    assert(floating._nw_motion.stopped,"stars still stop on non-wall targets")
end

-- Gust pushes an egg without opening it, accumulates actual momentum, can
-- wake a stopped egg, and passes through crystals without pushing them.
SpawnPrefab=function(name)
    assert(name=="nw_elemental_hit_fx")
    return nil -- Cosmetic impacts are covered by test_elemental_hit.lua.
end
local function prop(id)
    local e=entity(2,0,{nw_breakable=true});e._nw_owner=owner
    e._nw_stored={p=descriptor({},0,id)}
    e._nw_break=function() error("gust must not break stored spells") end
    return e
end
local function gust(target)
    candidates={target}
    local e=entity(4,0);local p=Copy(D.gust);p.flags=Copy(p.innate)
    e._shot={owner=owner,p=p,speed=16,damage=4,hit={},age=0,x=0,z=0,time=now,remaining=2,travelled=0,dx=1,dz=0}
    F.reset(e._shot,1,0);now=now+.1;P.step(e,now,{})
    return e
end
local egg=prop("payload_egg")
assert(not gust(egg).valid and egg.valid);close(egg._nw_motion.vx,8)
gust(egg);close(egg._nw_motion.vx,16)
Motion.stop(egg);gust(egg);close(egg._nw_motion.vx,8);assert(not egg._nw_motion.stopped)
for _,id in ipairs({"crystal_mine","sleep_crystal"}) do
    local crystal=prop(id);assert(gust(crystal).valid and not crystal._nw_motion)
end
-- Map support is retained on-map; leaving it clears only engine collisions.
-- Height correction preserves horizontal motion and interpolation off-map.
local probe=entity(0,0);probe._nw_ground_mask=true
local writes,clears=0,0
probe.Physics.ClearCollisionMask=function() clears=clears+1 end
probe.Physics.TeleportRespectingInterpolation=function(_,x,y,z)
    assert(x==12 and y==0 and z==3);writes=writes+1
end
TheWorld.Map={IsAboveGroundAtPoint=function(_,x) return x<10 end}
F.ground(probe,0,0,3);assert(writes==0 and clears==0)
F.ground(probe,12,-.02,3);assert(writes==1 and clears==1 and not probe._nw_ground_mask)
F.ground(probe,12,0,3);assert(writes==1 and clears==1)
F.ground(probe,0,0,3);assert(probe._nw_ground_mask)
print("motion: force/rotate/short guidance, frame-rate independence, shared paths, drag/save/restart, collision stop/pierce/bounce and selective gust impulses")
