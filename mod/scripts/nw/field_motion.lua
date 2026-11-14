local C=require("nw/constants/motion")
local Flight=require("nw/flight")
local Cleanup=require("nw/permanent_motion_cleanup")
local Policy=require("nw/target_policy")
local Limits=require("nw/spell_limits")
local M={drag=math.log(2)/C.field.drag_half_life,stop_speed=C.field.stop_speed}
local saved_keys={"vx","vz","heading","phase","offx","offz","accel_factor","reversed","motor_speed","motor_angle",
    "orbit_angle","orbit_radius","orbit_started","orbit_vx","orbit_vz","escaped","bounces","hits_left","travelled","stopped","actor_userid"}
function M.save(inst)
    local data={}
    for _,key in ipairs(saved_keys) do
        local value=inst._nw_motion[key]
        if value~=math.huge then data[key]=value end
    end
    return data
end
function M.stop(inst,x,z)
    local s=inst._nw_motion
    if not s then return end
    if x then inst.Physics:Teleport(x,0,z);s.x,s.z=x,z end
    s.vx,s.vz,s.motor_speed,s.stopped=0,0,0,true
    s.orbit_vx,s.orbit_vz=nil,nil
    inst.Physics:Stop()
    inst.Physics:SetMotorVel(0,0,0)
    RemovePhysicsColliders(inst);inst._nw_ground_mask=true
    if s.task then s.task:Cancel();s.task=nil end
    inst.entity:SetCanSleep(inst._nw_fuse_deadline==nil)
    Cleanup.unwatch(inst)
end
local function owner(inst,s)
    local Stored=require("nw/persistent_fields")
    if s.actor_userid then
        for _,e in ipairs(AllPlayers) do
            if e.userid==s.actor_userid then return Stored.caster(e) end
        end
        return
    end
    if s.actor then return Stored.caster(s.actor) end
    if inst._nw_motion_owner then return inst._nw_motion_owner(inst) end
    if inst._nw_stored then return Stored.owner(inst) end
    return Stored.caster(s.owner)
end
function M.prepare(inst,s,now)
    if s.stopped then return false end
    local x,y,z=inst.Transform:GetWorldPosition()
    Flight.ground(inst,x,y,z)
    Cleanup.sync(inst)
    s.owner=owner(inst,s)
    if not s.owner then
        s.time=now;s.target=nil;s.search=nil;s.seek_states=nil
        s.motor_speed=nil;s.motor_angle=nil
        if s.p.flags.orbit and not s.escaped then s.orbit_vx,s.orbit_vz=0,0 end
        s.ox,s.oz=nil,nil
        inst.Physics:Stop()
        inst.Physics:SetMotorVel(0,0,0)
        return false
    end
    return true
end
function M.settle(inst,s)
    local f=s.p.flags
    if s.drag and not (f.homing or f.homing_short or f.orbit or f.sine or f.spiral)
        and (not f.accelerate or s.age>=C.acceleration.duration) and s.vx*s.vx+s.vz*s.vz<M.stop_speed^2 then
        M.stop(inst)
    end
end
function M.start(inst,caster,p,dx,dz,age,saved)
    if require("nw/ground_fields").applies(p) and require("nw/ground_fields").sink(inst) then return false end
    if not require("nw/world_bounds").watch(inst) then return false end
    if not p.flags then p=require("nw/util").copy(p);p.flags={} end
    local f=Policy.flags(p)
    require("nw/field_effects").attach(inst,caster,p,function() return owner(inst,inst._nw_motion or {owner=caster}) end)
    if (p.speed or 0)<=0 and not (f.homing or f.homing_short) and not saved then return end
    local x,_,z=inst.Transform:GetWorldPosition()
    local s={placement=true,owner=caster,p=p,speed=p.speed or 0,hit={},dx=dx,dz=dz,
        ignore_walls=p.id=="edge_yellowstaff" or p.id=="edge_opalstaff",
        age=age or 0,x=x,z=z,time=GetTime(),remaining=math.huge,travelled=0,
        ignore_self=f.targets and f.targets.self,
        pass_creatures=Policy.infinite_pierce(p) or p.id=="vital_ring" or p.id=="rain_cloud" or p.id=="shock_ring"
            or p.id=="storm_cloud" or p.id=="fireflies" or p.id=="delay_seal",
        bounces=f.bounce and f.bounce.bounces,
        hits_left=(Policy.infinite_pierce(p) or f.pierce_all) and math.huge or f.pierce and f.pierce.hits,
        drag=M.drag}
    Flight.reset(s,dx,dz)
    if saved then
        for _,key in ipairs(saved_keys) do if saved[key]~=nil then s[key]=saved[key] end end
        s.vx,s.vz=Limits.limit_velocity(s.vx,s.vz)
        if s.motor_speed and s.motor_speed>Limits.max_speed then
            if s.orbit_vx then
                local angle=s.motor_angle and -s.motor_angle*DEGREES or s.heading
                local delta=Limits.max_speed-s.motor_speed
                s.orbit_vx=s.orbit_vx+delta*math.cos(angle)
                s.orbit_vz=s.orbit_vz+delta*math.sin(angle)
            end
            s.motor_speed=Limits.max_speed
        end
    end
    if Policy.infinite_pierce(p) then s.hits_left=math.huge end
    inst._nw_motion=s
    RemovePhysicsColliders(inst);inst._nw_ground_mask=true
    if s.stopped then M.stop(inst);return end
    inst.entity:SetCanSleep(false)
    Cleanup.watch(inst)
    if M.prepare(inst,s,GetTime()) then
        local speed=s.motor_speed or math.sqrt(s.vx*s.vx+s.vz*s.vz)
        inst.Transform:SetRotation(s.motor_angle or -s.heading/DEGREES)
        Limits.set_motor_velocity(inst,speed,0,0)
    end
    s.task=inst:DoPeriodicTask(FRAMES,function()
        require("nw/projectiles").step(inst,GetTime(),{})
        if inst:IsValid() and not s.stopped then M.settle(inst,s) end
    end,FRAMES)
end
function M.push_egg(inst,actor,dx,dz,impulse)
    if not inst._nw_stored or inst._nw_stored.p.id~="payload_egg"
        or not require("nw/persistent_fields").caster(actor) then return false end
    local old=inst._nw_motion
    local data=old and M.save(inst) or {}
    local motor_speed,motor_angle=data.motor_speed,data.motor_angle
    data.vx=(data.vx or 0)+dx*impulse;data.vz=(data.vz or 0)+dz*impulse
    if data.orbit_vx then
        data.orbit_vx=data.orbit_vx+dx*impulse;data.orbit_vz=data.orbit_vz+dz*impulse
    end
    data.heading=math.atan2(data.vz,data.vx);data.stopped=false
    data.motor_speed,data.motor_angle=nil,nil
    if data.orbit_vx then
        local vx,vz=data.orbit_vx,data.orbit_vz
        if motor_speed and motor_angle then
            local a=-motor_angle*DEGREES
            vx,vz=math.cos(a)*motor_speed+dx*impulse,math.sin(a)*motor_speed+dz*impulse
        end
        data.motor_speed=math.sqrt(vx*vx+vz*vz)
        data.motor_angle=-math.atan2(vz,vx)/DEGREES
    end
    data.actor_userid=require("nw/persistent_fields").userid(actor)
    if old and old.task then old.task:Cancel() end
    local stored=inst._nw_stored
    M.start(inst,actor,stored.p,math.cos(data.heading),math.sin(data.heading),old and old.age or 0,data)
    if not data.actor_userid and inst._nw_motion then
        local s=inst._nw_motion;s.actor=actor;s.owner=actor
        inst.Transform:SetRotation(s.motor_angle or -s.heading/DEGREES)
        Limits.set_motor_velocity(inst,s.motor_speed or math.sqrt(s.vx*s.vx+s.vz*s.vz),0,0)
    end
    return true
end
return M
