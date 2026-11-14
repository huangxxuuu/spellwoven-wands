local C=require("nw/constants/motion")
local Effects=require("nw/spell_effects")
local Targeting=require("nw/targeting")
local Policy=require("nw/target_policy")
local Limits=require("nw/spell_limits")
local M={}
local CONTACT_TARGETS={breakables=true}
local TOOL_TARGETS={default=true}
function M.ground(inst,x,y,z)
    local map=TheWorld.Map
    if not map or not map.IsAboveGroundAtPoint then return end
    local ground=map:IsAboveGroundAtPoint(x,0,z,true)
    if inst._nw_ground_mask~=ground then
        if ground then RemovePhysicsColliders(inst) else inst.Physics:ClearCollisionMask() end
        inst._nw_ground_mask=ground
    end
    if math.abs(y)>C.ground_height_epsilon then inst.Physics:TeleportRespectingInterpolation(x,0,z) end
end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function M.orbit_radius(p,speed)
    local base=math.max(C.orbit.min_radius,C.orbit.radius_scale*math.sqrt(math.max(0,speed or 0)/C.orbit.reference_speed))
    return math.min(C.orbit.max_radius,base*math.sqrt(require("nw/projectile_size").factor(p)))
end
function M.turn(angle,desired,limit)
    local delta=(desired-angle+math.pi)%(2*math.pi)-math.pi
    return angle+clamp(delta,-limit,limit)
end
function M.reset(s,dx,dz)
    s.motor_angle,s.motor_speed=nil,nil
    s.orbit_vx,s.orbit_vz=nil,nil
    s.heading=math.atan2(dz,dx);s.offx=0;s.offz=0;s.phase=0
    local f=s.p and s.p.flags or {}
    local speed=(s.speed or 0)*(f.spiral and C.spiral_speed_mult or 1)*(f.accelerate and C.acceleration.initial_factor or 1)
    s.vx,s.vz=Limits.limit_velocity(dx*speed,dz*speed)
    s.accel_factor=f.accelerate and C.acceleration.initial_factor or 1
end
local function orbit_velocity(s,dt,x,z,tx,tz,tvx,tvz,ax,az)
    local vx,vz=s.orbit_vx or s.vx,s.orbit_vz or s.vz
    local stiffness,damping=C.orbit.stiffness,C.orbit.damping
    local denominator=1+damping*dt+stiffness*dt*dt
    ax=(ax+stiffness*(tx-x-vx*dt)+damping*(tvx-vx))/denominator
    az=(az+stiffness*(tz-z-vz*dt)+damping*(tvz-vz))/denominator
    local acceleration=math.sqrt(ax*ax+az*az)
    if acceleration>C.orbit.max_acceleration then ax,az=ax*C.orbit.max_acceleration/acceleration,az*C.orbit.max_acceleration/acceleration end
    return vx+ax*dt,vz+az*dt
end
function M.seek(s,f)
    local best,best_score
    local hx,hz=math.cos(s.heading),math.sin(s.heading)
    local impact=require("nw/engraved_impact")
    local key=s.p and s.p.engraving
    local filter=impact.filters[key]
    local flags=Policy.flags(s.p)
    local candidates=filter and TheSim:FindEntities(s.x,0,s.z,f.radius,{filter},{"INLIMBO","FX"}) or Effects.scan(s.x,s.z,f.radius,flags)
    for _,e in ipairs(candidates) do
        if e._nw_motion~=s and e._shot~=s
            and (e~=s.owner or flags.targets) and e:IsValid()
            and not (s.p and s.p.id=="gust" and Targeting.breakable(e) and not Targeting.egg(e))
            and (s.placement or not s.hit[e] or s.age+C.velocity_epsilon_squared>=s.hit[e]) then
            local x,_,z=e.Transform:GetWorldPosition()
            local rx,rz=x-s.x,z-s.z
            local d2=rx*rx+rz*rz
            if d2<=f.radius*f.radius and (filter and impact.accepts(key,e) and Targeting.accepts(s.owner,e,flags,TOOL_TARGETS)
                or not filter and Targeting.accepts(s.owner,e,flags,CONTACT_TARGETS)) then
                local dist=math.sqrt(d2)
                local dot=dist>C.distance_epsilon and clamp((hx*rx+hz*rz)/dist,-1,1) or 1
                local speed=s.vx and math.sqrt(s.vx*s.vx+s.vz*s.vz) or s.speed or 0
                local score=(dot<0 and C.homing.behind_penalty or 0)+math.acos(dot)/((f.turn_rate or C.homing.score_turn_rate)*DEGREES)+dist/math.max(C.homing.min_score_speed,speed)
                if not best or score<best_score or score==best_score and e.GUID<best.GUID then
                    best,best_score=e,score
                end
            end
        end
    end
    return best
end
local function seek_cached(s,key,f)
    s.seek_states=s.seek_states or {}
    local state=s.seek_states[key] or {};s.seek_states[key]=state
    if not state.next_search or s.age>=state.next_search then
        state.next_search=s.age+C.homing.search_interval;state.target=M.seek(s,f)
    end
    local e=state.target
    if e and e:IsValid() then
        local impact=require("nw/engraved_impact")
        local kind=s.p and s.p.engraving
        local filter=impact.filters[kind]
        local flags=Policy.flags(s.p)
        if filter and impact.accepts(kind,e) and Targeting.accepts(s.owner,e,flags,TOOL_TARGETS)
            or not filter and Targeting.accepts(s.owner,e,flags,CONTACT_TARGETS) then return e end
        state.target=nil;state.next_search=nil
    end
end
local function propulsion(s,dt)
    local f=s.p.flags
    local ax,az,damping=0,0,s.drag or 0
    local guided=false
    local turn_rate=0
    local before=s.vx*s.vx+s.vz*s.vz>C.velocity_epsilon_squared and math.atan2(s.vz,s.vx) or s.heading
    for _,key in ipairs({"homing","homing_short"}) do
        local h=f[key]
        if h then
            local target=seek_cached(s,key,h)
            if target then
                guided=true
                turn_rate=math.max(turn_rate,h.turn_rate or C.homing.turn_rate)
                local x,_,z=target.Transform:GetWorldPosition()
                local dx,dz=x-s.x,z-s.z
                local distance=math.sqrt(dx*dx+dz*dz)
                local near=key=="homing_short" or h.id=="near_homing"
                local force=h.acceleration or (near and C.homing.near_force or C.homing.force)
                damping=damping+(h.damping or (near and C.homing.near_damping or C.homing.damping))
                if distance>C.distance_epsilon then ax,az=ax+dx/distance*force,az+dz/distance*force end
            end
        end
    end
    local decay=math.exp(-damping*dt)
    local gain=damping>0 and (1-decay)/damping or dt
    s.vx,s.vz=s.vx*decay+ax*gain,s.vz*decay+az*gain
    if guided and s.vx*s.vx+s.vz*s.vz>C.velocity_epsilon_squared then
        local speed=math.sqrt(s.vx*s.vx+s.vz*s.vz)
        local desired=ax*ax+az*az>C.velocity_epsilon_squared and math.atan2(az,ax) or math.atan2(s.vz,s.vx)
        local angle=M.turn(before,desired,turn_rate*DEGREES*dt)
        s.vx,s.vz=speed*math.cos(angle),speed*math.sin(angle)
    end
end
function M.steer(inst,s,dt)
    local f=s.p.flags
    if s.vx==nil then M.reset(s,s.dx or 1,s.dz or 0) end
    dt=math.max(0,dt)
    if dt==0 then return true end
    local heading_before=s.vx*s.vx+s.vz*s.vz>C.velocity_epsilon_squared and math.atan2(s.vz,s.vx) or s.heading
    propulsion(s,dt)
    if f.accelerate then
        local factor=C.acceleration.initial_factor+C.acceleration.gain*math.min(1,s.age/C.acceleration.duration)
        local ratio=factor/(s.accel_factor or C.acceleration.initial_factor)
        s.vx,s.vz=s.vx*ratio,s.vz*ratio;s.accel_factor=factor
    end
    local base_speed=math.sqrt(s.vx*s.vx+s.vz*s.vz)
    local a=base_speed>C.distance_epsilon and math.atan2(s.vz,s.vx) or s.heading
    local orbiting=f.orbit and not s.escaped
    local vx,vz
    if orbiting then
        local ox,_,oz=s.owner.Transform:GetWorldPosition()
        if s.ox and (ox-s.ox)^2+(oz-s.oz)^2>C.orbit.owner_jump_squared then return false end
        local ovx,ovz=s.ox and (ox-s.ox)/dt or 0,s.oz and (oz-s.oz)/dt or 0
        s.ox,s.oz=ox,oz
        local x,z=s.x-s.offx,s.z-s.offz
        local rx,rz=x-ox,z-oz
        local radius=math.sqrt(rx*rx+rz*rz)
        local target_radius=M.orbit_radius(s.p,base_speed)
        local return_radius=target_radius+math.max(C.orbit.return_margin,target_radius*C.orbit.return_radius_fraction)
        if radius>return_radius then
            local tvx,tvz=ovx-rx/radius*base_speed,ovz-rz/radius*base_speed
            vx,vz=orbit_velocity(s,dt,x,z,x+tvx*dt,z+tvz*dt,tvx,tvz,0,0)
            s.orbit_angle=nil;s.orbit_radius=nil
        else
            s.orbit_angle=s.orbit_angle or (radius>C.orbit.heading_radius and math.atan2(rz,rx) or a)
            if not s.orbit_started then
                s.orbit_angle=s.orbit_angle+(s.fan_angle or 0);s.orbit_started=true
            end
            local angular_speed=math.min(base_speed/target_radius,C.orbit.max_turn_rate*DEGREES)
            local angle=s.orbit_angle
            local turn=dt*angular_speed
            s.orbit_angle=angle+turn
            local step=math.min(C.orbit.max_radial_speed,base_speed*C.orbit.radial_speed_fraction)*dt
            local previous=s.orbit_radius or radius
            local r=previous+clamp((target_radius-previous)*(1-math.exp(-dt/C.orbit.radius_response)),-step,step)
            s.orbit_radius=r
            local qx,qz=previous*math.cos(angle),previous*math.sin(angle)
            local nx,nz=r*math.cos(s.orbit_angle),r*math.sin(s.orbit_angle)
            local centripetal=-4*math.sin(turn*.5)^2/(dt*dt)
            vx,vz=orbit_velocity(s,dt,x,z,ox+nx,oz+nz,
                ovx+(nx-qx)/dt,ovz+(nz-qz)/dt,centripetal*qx,centripetal*qz)
        end
        s.orbit_vx,s.orbit_vz=vx,vz
        a=math.atan2(vz,vx)
    else
        if not s.reversed and ((f.reverse and s.age>=C.returning.reverse_delay) or (f.returning and s.age>=C.returning.delay)) then
            a=a+math.pi;s.reversed=true
            if s.p.ballistic then local v=inst.components.complexprojectile.velocity;v.y=math.abs(v.y) end
        end
        if f.returning and s.age>=C.returning.delay then
            local ox,_,oz=s.owner.Transform:GetWorldPosition()
            a=M.turn(a,math.atan2(oz-s.z,ox-s.x),C.returning.turn_rate*DEGREES*dt)
        elseif f.homing_rotate then
            local target=seek_cached(s,"homing_rotate",f.homing_rotate)
            if target then
                local tx,_,tz=target.Transform:GetWorldPosition()
                a=M.turn(a,math.atan2(tz-s.z,tx-s.x),f.homing_rotate.turn_rate*DEGREES*dt)
            end
        end
        if f.homing_rotate and (f.homing or f.homing_short) then
            a=M.turn(heading_before,a,math.max(f.homing and f.homing.turn_rate or 0,
                f.homing_short and f.homing_short.turn_rate or 0,f.homing_rotate.turn_rate or C.homing.turn_rate)*DEGREES*dt)
        end
        vx,vz=base_speed*math.cos(a),base_speed*math.sin(a)
    end
    if orbiting then
        local drive=math.min(Limits.max_speed,base_speed)
        s.vx,s.vz=drive*math.cos(a),drive*math.sin(a)
    else
        s.vx,s.vz=vx,vz
    end
    s.heading=a;s.phase=s.phase+dt
    local side,forward=0,0
    if f.sine then side=f.sine.amplitude*math.sin(2*math.pi*f.sine.frequency*s.phase) end
    if f.spiral then
        local t=2*math.pi*f.spiral.frequency*s.phase
        side=side+f.spiral.amplitude*math.sin(t)
        forward=f.spiral.amplitude*(math.cos(t)-1)
    end
    local offx=math.cos(a)*forward-math.sin(a)*side
    local offz=math.sin(a)*forward+math.cos(a)*side
    local offvx,offvz=(offx-s.offx)/dt,(offz-s.offz)/dt
    vx=vx+offvx;vz=vz+offvz
    s.offx,s.offz=offx,offz
    local speed=math.sqrt(vx*vx+vz*vz)
    if speed>C.distance_epsilon then
        s.dx,s.dz=vx/speed,vz/speed
        local rotation=-math.atan2(vz,vx)/DEGREES
        if speed>Limits.max_speed then
            local scale=Limits.max_speed/speed
            if not orbiting then s.vx,s.vz=s.vx*scale,s.vz*scale end
            if orbiting then s.orbit_vx,s.orbit_vz=vx*scale-offvx,vz*scale-offvz end
            speed=Limits.max_speed
        end
        if rotation~=s.motor_angle or speed~=s.motor_speed then
            s.motor_angle,s.motor_speed=rotation,speed
            inst.Transform:SetRotation(rotation)
            if s.p.ballistic then inst.components.complexprojectile.velocity.x=speed
            else Limits.set_motor_velocity(inst,speed,0,0) end
        end
    elseif s.motor_speed~=0 then
        s.motor_speed=0
        if s.p.ballistic then inst.components.complexprojectile.velocity.x=0
        else inst.Physics:SetMotorVel(0,0,0) end
    end
    return true
end
return M
