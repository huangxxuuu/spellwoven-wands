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
-- with the same selected category. Test real steering, not only selection.
for _,id in ipairs({"payload_egg","sleep_crystal"}) do
    local prop=entity(1,1,{nw_breakable=true})
    prop._nw_stored={p={id=id}};prop._nw_break=function() error("seeking cannot activate a prop") end
    for _,scope in ipairs({false,{friendly=true},{neutral=true},{building=true},
        {friendly=true,neutral=true,building=true}}) do
        for _,card in ipairs({D.homing,D.near_homing,D.weak_homing,D.homing_rotate}) do
            TheWorld._nw_scans=nil;candidates={prop}
            local guided=velocity({[card.flag]=Copy(card),targets=scope or nil},6,FRAMES,1)
            if scope and not scope.building then
                assert(guided.vz==0 and not F.seek(guided,card),"a prop must match the attacker's selected category")
            else
            assert(guided.vz>0,id.." must attract "..card.id)
            assert(F.seek(guided,card)==prop)
            guided.hit[prop]=guided.age+.1
            assert(not F.seek(guided,card),"recent piercing contacts respect their cooldown")
            guided.placement=true
            assert(F.seek(guided,card)==prop,"placement navigation must retain a target during contact cooldown")
            guided.placement=nil
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
end
TheWorld._nw_scans=nil
candidates={}
for _,id in ipairs({"sine","spiral","orbit","reverse_path","return_path","accelerate"}) do
    local card=D[id];local flags={[card.flag]=Copy(card)}
    local e=field(descriptor(flags,6),false)
    local s={owner=owner,p=descriptor(flags,6),speed=6,age=0,x=0,z=0,hit={},drag=Motion.drag}
    local bullet=entity();F.reset(s,1,0)
    for i=1,20 do
        e.x,e.z=0,0;s.x,s.z=0,0
        now=now+FRAMES;s.age=s.age+FRAMES
        P.step(e,now,{});F.steer(bullet,s,FRAMES)
        close(e.motor,bullet.motor);close(e.rotation,bullet.rotation)
    end
    e:Remove()
end

-- Every moving placement halves unpowered inertia in four seconds, saves its
-- current velocity, and eventually settles. Finite lifetime is not an opt-out;
-- ordinary projectile propulsion retains its original undamped inertia.
local free_shot,free_body=velocity({},8,FRAMES,120)
close(free_body.motor,8);assert(free_shot.drag==nil)
for _,case in ipairs({{"sleep_crystal",true},{"payload_egg",true},
    {"edge_yellowstaff",false},{"edge_opalstaff",false},{"rain_cloud",false}}) do
    local inert=field(descriptor({},8,case[1]),case[2])
    for i=1,120 do frame(inert,FRAMES) end
    close(inert.motor,4)
    local saved=Motion.save(inert)
    assert(saved.vx==inert._nw_motion.vx and not saved.stopped)
    local restored=entity(inert.x,inert.z)
    if case[2] then restored._nw_stored={p=inert._nw_motion.p};restored._nw_owner=owner end
    Motion.start(restored,owner,inert._nw_motion.p,1,0,inert._nw_motion.age,saved)
    close(restored.motor,inert.motor)
    for i=1,900 do if not restored._nw_motion.stopped then frame(restored,FRAMES) end end
    assert(restored.valid and restored.motor==0 and restored._nw_motion.stopped and restored.can_sleep,
        case[1].." must settle without removing the placement")
    local settled=entity(restored.x,restored.z)
    if case[2] then settled._nw_stored={p=inert._nw_motion.p};settled._nw_owner=owner end
    Motion.start(settled,owner,inert._nw_motion.p,1,0,restored._nw_motion.age,Motion.save(restored))
    assert(settled.motor==0 and settled._nw_motion.stopped,"loading cannot relaunch a settled placement")
    inert:Remove();restored:Remove();settled:Remove()
end

-- Orbit steering may only integrate the native motor. Collision and ground
-- tests below retain their independent position-writing mocks.
local function forbid_orbit_position_writes(e)
    local function forbidden() error("orbit restore/steering must not write position") end
    e.Transform.SetPosition=forbidden
    e.Physics.Teleport=forbidden
    e.Physics.TeleportRespectingInterpolation=forbidden
end
-- Persist both tracking velocity and a partially entered orbit. Stationary
-- owners resume exactly; moving owners reacquire their unsaved velocity with
-- a bounded transient. Legacy saves can rebuild the missing tracking cache.
local owner_x,owner_z=owner.x,owner.z
for _,owner_speed in ipairs({0,6}) do
    owner.x,owner.z=0,0
    local orbiting=field(descriptor({orbit=Copy(D.orbit)},25),true)
    forbid_orbit_position_writes(orbiting)
    for _=1,8 do owner.x=owner.x+owner_speed*FRAMES;frame(orbiting,FRAMES) end
    local orbit_saved=Motion.save(orbiting)
    assert(orbit_saved.orbit_radius and orbit_saved.orbit_radius>0)
    close(orbit_saved.orbit_vx,orbiting._nw_motion.orbit_vx)
    close(orbit_saved.orbit_vz,orbiting._nw_motion.orbit_vz)
    local restored={}
    for _,legacy in ipairs({false,true}) do
        local saved=Copy(orbit_saved)
        if legacy then saved.orbit_vx,saved.orbit_vz=nil,nil end
        local loaded=entity(orbiting.x,orbiting.z)
        forbid_orbit_position_writes(loaded)
        loaded._nw_stored={p=orbiting._nw_motion.p};loaded._nw_owner=owner
        Motion.start(loaded,owner,orbiting._nw_motion.p,1,0,orbiting._nw_motion.age,saved)
        close(loaded._nw_motion.orbit_radius,orbiting._nw_motion.orbit_radius)
        close(loaded.motor,orbiting.motor);close(loaded.rotation,orbiting.rotation)
        table.insert(restored,loaded)
    end
    for i=1,90 do
        owner.x=owner.x+owner_speed*FRAMES;now=now+FRAMES
        for _,e in ipairs({orbiting,restored[1],restored[2]}) do
            local s=e._nw_motion
            local vx,vz=s.orbit_vx,s.orbit_vz
            e.x=e.x+math.cos(-e.rotation*DEGREES)*e.motor*FRAMES
            e.z=e.z+math.sin(-e.rotation*DEGREES)*e.motor*FRAMES
            P.step(e,now,{})
            assert(s.orbit_vx==s.orbit_vx and s.orbit_vz==s.orbit_vz,"legacy orbit velocity must remain finite")
            if vx then
                assert(math.sqrt((s.orbit_vx-vx)^2+(s.orbit_vz-vz)^2)<=180*FRAMES+1e-8,
                    "restoring an orbit cannot bypass tracking acceleration")
            end
        end
        if owner_speed==0 then
            close(restored[1].motor,orbiting.motor);close(restored[1].rotation,orbiting.rotation)
        end
        if i>60 then
            for _,loaded in ipairs(restored) do
                local separation=math.sqrt((loaded.x-orbiting.x)^2+(loaded.z-orbiting.z)^2)
                assert(separation<.3,"saved and legacy orbits must converge without losing their phase")
            end
        end
    end
    orbiting:Remove();for _,e in ipairs(restored) do e:Remove() end
end
-- Losing the owner stops actual physics. Reacquisition starts tracking from
-- that rest state, including when the player moved while absent.
owner.x,owner.z=0,0
local waiting=field(descriptor({orbit=Copy(D.orbit)},25),true)
forbid_orbit_position_writes(waiting)
for _=1,12 do frame(waiting,FRAMES) end
local waiting_motion=waiting._nw_motion
assert(waiting.motor>0 and waiting_motion.ox~=nil)
owner.valid=false
frame(waiting,FRAMES)
assert(waiting.motor==0 and waiting_motion.orbit_vx==0 and waiting_motion.orbit_vz==0)
assert(waiting_motion.ox==nil and waiting_motion.oz==nil,"absent owner history must not trigger teleport cleanup later")
owner.x=10;owner.valid=true;waiting._nw_owner=owner
frame(waiting,FRAMES)
assert(waiting.valid and not waiting_motion.stopped and waiting_motion.owner==owner)
assert(waiting.motor>0 and waiting.motor<=180*FRAMES+1e-8,"owner reacquisition must accelerate from stopped physics")
waiting:Remove()
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
local fast_bounce=field(descriptor({bounce={bounces=2}},500),false);fast_bounce.x=4
now=now+.1;P.step(fast_bounce,now,{})
close(fast_bounce.motor,require("nw/spell_limits").max_speed)
close(fast_bounce._nw_motion.vx,-fast_bounce.motor)
assert(fast_bounce._nw_motion.bounces==1,"initial reflection must bound the legacy nominal-speed fallback")
fast_bounce:Remove()
local phased=field(descriptor({phase_wall={}},6),false);phased.x=4
now=now+.1;P.step(phased,now,{});assert(not phased._nw_motion.stopped)
-- Both floating stars cross walls without consuming pierce/bounce, including
-- building selection and a restored movement state. Other fields still stop.
for _,id in ipairs({"edge_yellowstaff","edge_opalstaff"}) do
    local p=descriptor({targets={building=true},bounce={bounces=2},pierce={hits=3}},6,id)
    local floating=field(p,false);floating.x=4
    now=now+.1;P.step(floating,now,{})
    assert(not floating._nw_motion.stopped and floating._nw_motion.vx>0 and floating.x==4)
    assert(floating._nw_motion.bounces==2 and floating._nw_motion.hits_left==math.huge)
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
    assert(not floating._nw_motion.stopped and floating._nw_motion.hits_left==math.huge,"stars have intrinsic infinite piercing")
end

-- Reproduce a self-targeted native star: its birth overlap is ignored, then
-- return contacts never exhaust the stars' intrinsic piercing.
-- Contact cooldown suppresses repeated collisions, not placement steering.
local owner_x,owner_z=owner.x,owner.z
for _,piercing in ipairs({false,true}) do
    owner.x,owner.z=0,0;candidates={owner};TheWorld._nw_scans=nil
    local flags={targets={self=true},homing=Copy(D.homing),pierce_all=piercing and {} or nil}
    local following=field(descriptor(flags,0,"edge_yellowstaff"),false)
    local motion=following._nw_motion
    frame(following,FRAMES)
    assert(not motion.stopped and not motion.hit[owner],"initial self overlap is not a hit")
    owner.x=2
    for _=1,90 do
        frame(following,FRAMES)
        if motion.hit[owner] then break end
    end
    assert(motion.hit[owner],"the star must catch and contact its selected owner")
    do
        assert(not motion.stopped and motion.hits_left==math.huge)
        local hit_until=motion.hit[owner]
        -- Sweep past the owner while the .5 s collision cooldown is active.
        -- Force another search after the .1 s guidance-cache interval.
        following.x=owner.x+1
        now=now+.12;P.step(following,now,{})
        assert(motion.age<hit_until and motion.hit[owner]==hit_until)
        assert(motion.seek_states.homing.target==owner and math.abs(motion.vz)>0,
            "after passing its target, a piercing placement must turn back during contact cooldown")
        assert(F.seek(motion,D.homing)==owner)
        local ordinary=Copy(motion);ordinary.placement=nil;ordinary.owner=owner
        ordinary.hit={[owner]=hit_until}
        assert(not F.seek(ordinary,D.homing),"ordinary piercing shots still skip cooling-down contacts")
        -- Keep the body overlapping to verify that continued steering did not
        -- shorten the independent half-second collision settlement interval.
        local function overlap_at(age)
            following.x,following.z=owner.x,owner.z
            motion.x,motion.z=owner.x,owner.z
            now=now+age-motion.age
            P.step(following,now,{})
        end
        overlap_at(hit_until-.01)
        close(motion.hit[owner],hit_until)
        overlap_at(hit_until)
        close(motion.hit[owner],hit_until+.5)
        assert(not motion.stopped and motion.hits_left==math.huge)
    end
    following:Remove()
end
owner.x,owner.z=owner_x,owner_z

-- A proximity behaviour sweeps its whole path, even with infinite pierce and
-- both endpoints outside sensing range. It explodes at the first valid entry.
local sensed=entity(5,0,{tree=true});sensed.components.health=nil;sensed.components.combat=nil
candidates={sensed}
local moving_mine=field(descriptor({targets={nature=true},pierce_all={}},100,"crystal_mine"),true)
local triggers=0
moving_mine._nw_proximity={radius=1.6,trigger=function(e)
    assert(e==sensed);triggers=triggers+1;moving_mine:Remove()
end}
moving_mine.x=10;now=now+.1;P.step(moving_mine,now,{})
assert(triggers==1 and not moving_mine.valid)
close(moving_mine.x,3.4)
local excluded=field(descriptor({targets={hostile=true},pierce_all={}},100,"crystal_mine"),true)
excluded._nw_proximity={radius=1.6,trigger=function() error("unselected tree cannot trigger proximity") end}
excluded.x=10;now=now+.1;P.step(excluded,now,{})
assert(excluded.valid and not excluded._nw_motion.stopped)
excluded:Remove();candidates={}

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
-- A gust edits live propulsion and the saved tracking velocity together. A
-- stale orbit cache must never replace that impulse on the following tick.
local orbit_egg=prop("payload_egg")
orbit_egg._nw_stored.p=descriptor({orbit=Copy(D.orbit),sine=Copy(D.sine)},8,"payload_egg")
Motion.start(orbit_egg,owner,orbit_egg._nw_stored.p,1,0)
forbid_orbit_position_writes(orbit_egg)
candidates={};for _=1,10 do frame(orbit_egg,FRAMES) end
local before=orbit_egg._nw_motion
local drive_x,drive_z=before.vx,before.vz
local tracking_x,tracking_z=before.orbit_vx,before.orbit_vz
local actual_x=math.cos(-orbit_egg.rotation*DEGREES)*orbit_egg.motor
local actual_z=math.sin(-orbit_egg.rotation*DEGREES)*orbit_egg.motor
assert(math.sqrt((actual_x-tracking_x)^2+(actual_z-tracking_z)^2)>.1,
    "the regression must exercise a real sine offset beyond baseline tracking")
assert(Motion.push_egg(orbit_egg,owner,1,0,8))
local pushed=orbit_egg._nw_motion
close(pushed.vx,drive_x+8);close(pushed.vz,drive_z)
close(pushed.orbit_vx,tracking_x+8);close(pushed.orbit_vz,tracking_z)
close(math.cos(-orbit_egg.rotation*DEGREES)*orbit_egg.motor,actual_x+8)
close(math.sin(-orbit_egg.rotation*DEGREES)*orbit_egg.motor,actual_z)
local propulsion_speed=math.sqrt(pushed.vx^2+pushed.vz^2)
frame(orbit_egg,FRAMES)
close(math.sqrt(pushed.vx^2+pushed.vz^2),propulsion_speed*math.exp(-Motion.drag*FRAMES))
assert(math.sqrt((pushed.orbit_vx-tracking_x-8)^2+(pushed.orbit_vz-tracking_z)^2)<=180*FRAMES+1e-8)
-- Strong impulses cap the immediate motor and propulsion independently, with
-- the applied correction fed back to tracking without absorbing curve offsets.
local cap=require("nw/spell_limits").max_speed
local actual_x=math.cos(-orbit_egg.rotation*DEGREES)*orbit_egg.motor
local actual_z=math.sin(-orbit_egg.rotation*DEGREES)*orbit_egg.motor
local offset_x,offset_z=actual_x-pushed.orbit_vx,actual_z-pushed.orbit_vz
local motor_length=math.sqrt((actual_x+600)^2+(actual_z+800)^2)
local expected_x,expected_z=(actual_x+600)*cap/motor_length,(actual_z+800)*cap/motor_length
local drive_length=math.sqrt((pushed.vx+600)^2+(pushed.vz+800)^2)
local drive_x,drive_z=(pushed.vx+600)*cap/drive_length,(pushed.vz+800)*cap/drive_length
assert(Motion.push_egg(orbit_egg,owner,.6,.8,1000))
pushed=orbit_egg._nw_motion
close(orbit_egg.motor,cap)
close(math.cos(-orbit_egg.rotation*DEGREES)*orbit_egg.motor,expected_x)
close(math.sin(-orbit_egg.rotation*DEGREES)*orbit_egg.motor,expected_z)
close(pushed.vx,drive_x);close(pushed.vz,drive_z)
close(pushed.orbit_vx+offset_x,expected_x);close(pushed.orbit_vz+offset_z,expected_z)
frame(orbit_egg,FRAMES)
assert(orbit_egg.motor<=cap+1e-8 and math.sqrt(pushed.vx^2+pushed.vz^2)<=cap+1e-8)
orbit_egg:Remove()
for _,id in ipairs({"crystal_mine","sleep_crystal"}) do
    local crystal=prop(id);assert(gust(crystal).valid and not crystal._nw_motion)
end
candidates={}
local strong_egg=prop("payload_egg")
assert(Motion.push_egg(strong_egg,owner,.6,.8,1000))
close(strong_egg.motor,cap)
close(strong_egg._nw_motion.vx,cap*.6);close(strong_egg._nw_motion.vz,cap*.8)
strong_egg:Remove()
-- Old saves restore before the first simulation tick. Both cached motors and
-- legacy records lacking that cache must respect the same cap and direction.
for _,cached in ipairs({false,true}) do
    local restored=prop("payload_egg")
    local data={vx=300,vz=400,heading=math.atan2(400,300)}
    if cached then
        data.motor_speed=500;data.motor_angle=-data.heading/DEGREES
        data.orbit_vx=290;data.orbit_vz=380
        restored._nw_stored.p.flags={orbit=Copy(D.orbit),sine=Copy(D.sine)}
    end
    Motion.start(restored,owner,restored._nw_stored.p,.6,.8,0,data)
    local s=restored._nw_motion
    close(restored.motor,cap);close(s.vx,cap*.6);close(s.vz,cap*.8)
    close(math.cos(-restored.rotation*DEGREES)*restored.motor,cap*.6)
    close(math.sin(-restored.rotation*DEGREES)*restored.motor,cap*.8)
    if cached then close(s.orbit_vx+10,cap*.6);close(s.orbit_vz+20,cap*.8) end
    close(data.vx,300);close(data.vz,400) -- never mutate a shared save table
    frame(restored,FRAMES);assert(restored.motor<=cap+1e-8)
    restored:Remove()
end
-- Map support is retained on-map; leaving it clears only engine collisions.
-- Size changes art/physics scale, never world-space movement. Exercise the
-- actual initial, steering, restored and reflected native motor writes.
for _,scale in ipairs({.4,2.5,10}) do
    local function scaled()
        local e=entity()
        e.Transform.GetScale=function() return scale,scale,scale end
        return e
    end
    candidates={}
    local e=scaled();local p=descriptor({},cap)
    Motion.start(e,owner,p,1,0)
    close(e.motor*scale,cap)
    e.x=e.x+e.motor*scale*FRAMES;now=now+FRAMES;P.step(e,now,{})
    close(e.motor*scale,math.sqrt(e._nw_motion.vx^2+e._nw_motion.vz^2))
    local restored=scaled()
    Motion.start(restored,owner,p,1,0,e._nw_motion.age,Motion.save(e))
    close(restored.motor*scale,e.motor*scale)
    local wall=entity(2,0,{wall=true});candidates={wall}
    local reflected=scaled()
    Motion.start(reflected,owner,descriptor({bounce={bounces=1}},500),1,0)
    reflected.x=4;now=now+.1;P.step(reflected,now,{})
    close(reflected.motor*scale,cap);close(reflected._nw_motion.vx,-cap)
    assert(reflected._nw_motion.bounces==0)
    e:Remove();restored:Remove();reflected:Remove()
end
candidates={}
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
print("motion: force/rotate/short guidance, frame-rate independence, shared paths, placement drag/save/settle, independent guidance/contact cooldowns, stop/pierce/bounce and selective gust impulses")
