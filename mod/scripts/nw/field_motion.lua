-- Placement lifecycle adapter. Movement and swept collision use the same
-- Flight/Projectiles code as bullets; contact stops rather than deletes it.
local Flight=require("nw/flight")
local Cleanup=require("nw/permanent_motion_cleanup")
local M={drag=math.log(2)/4,stop_speed=.1}
local saved_keys={"vx","vz","heading","phase","offx","offz","accel_factor","reversed","motor_speed","motor_angle",
    "orbit_angle","orbit_radius","orbit_started","escaped","bounces","hits_left","travelled","stopped","actor_userid"}
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
    inst.Physics:Stop()
    inst.Physics:SetMotorVel(0,0,0)
    RemovePhysicsColliders(inst);inst._nw_ground_mask=true
    if s.task then s.task:Cancel();s.task=nil end
    -- A stopped spell bomb still has a live fuse; do not let native burnable's
    -- coarse sleep catch-up explode it early.
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
        inst.Physics:Stop()
        inst.Physics:SetMotorVel(0,0,0)
        return false
    end
    return true
end
function M.settle(inst,s)
    local f=s.p.flags
    -- Guidance may keep supplying force. Pure inertia settles for all moving
    -- placements, including finite-lived stars; an impulse can wake an egg.
    if s.drag and not (f.homing or f.homing_short or f.orbit or f.sine or f.spiral)
        and (not f.accelerate or s.age>=.7) and s.vx*s.vx+s.vz*s.vz<M.stop_speed^2 then
        M.stop(inst)
    end
end
function M.start(inst,caster,p,dx,dz,age,saved)
    if require("nw/ground_fields").applies(p) and require("nw/ground_fields").sink(inst) then return false end
    if not require("nw/world_bounds").watch(inst) then return false end
    local f=p.flags or {};p.flags=f
    require("nw/field_effects").attach(inst,caster,p,function() return owner(inst,inst._nw_motion or {owner=caster}) end)
    if (p.speed or 0)<=0 and not (f.homing or f.homing_short) and not saved then return end
    local x,_,z=inst.Transform:GetWorldPosition()
    local s={placement=true,owner=caster,p=p,speed=p.speed or 0,hit={},dx=dx,dz=dz,
        ignore_walls=p.id=="edge_yellowstaff" or p.id=="edge_opalstaff",
        age=age or 0,x=x,z=z,time=GetTime(),remaining=math.huge,travelled=0,
        ignore_self=f.targets and f.targets.self,
        pass_creatures=p.id=="vital_ring" or p.id=="rain_cloud" or p.id=="shock_ring"
            or p.id=="storm_cloud" or p.id=="fireflies" or p.id=="delay_seal",
        bounces=f.bounce and f.bounce.bounces,
        hits_left=f.pierce_all and math.huge or f.pierce and f.pierce.hits,
        drag=M.drag}
    Flight.reset(s,dx,dz)
    if saved then for _,key in ipairs(saved_keys) do if saved[key]~=nil then s[key]=saved[key] end end end
    inst._nw_motion=s
    RemovePhysicsColliders(inst);inst._nw_ground_mask=true
    if s.stopped then M.stop(inst);return end
    inst.entity:SetCanSleep(false)
    Cleanup.watch(inst)
    if M.prepare(inst,s,GetTime()) then
        -- Saved propulsion can exceed the capped orbit's actual motor speed.
        -- Restore the last applied motion until the next steering update.
        local speed=s.motor_speed or math.sqrt(s.vx*s.vx+s.vz*s.vz)
        inst.Transform:SetRotation(s.motor_angle or -s.heading/DEGREES)
        inst.Physics:SetMotorVel(speed,0,0)
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
    data.vx=(data.vx or 0)+dx*impulse;data.vz=(data.vz or 0)+dz*impulse
    data.heading=math.atan2(data.vz,data.vx);data.stopped=false
    data.motor_speed,data.motor_angle=nil,nil -- Apply the new impulse immediately.
    data.actor_userid=require("nw/persistent_fields").userid(actor)
    if old and old.task then old.task:Cancel() end
    local stored=inst._nw_stored
    M.start(inst,actor,stored.p,math.cos(data.heading),math.sin(data.heading),old and old.age or 0,data)
    if not data.actor_userid and inst._nw_motion then
        local s=inst._nw_motion;s.actor=actor;s.owner=actor
        inst.Transform:SetRotation(-s.heading/DEGREES)
        inst.Physics:SetMotorVel(math.sqrt(s.vx*s.vx+s.vz*s.vz),0,0)
    end
    return true
end
return M
