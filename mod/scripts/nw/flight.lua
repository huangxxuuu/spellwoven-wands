local Effects=require("nw/spell_effects")
local Targeting=require("nw/targeting")
local M={}
-- Ground support prevents gravity drift on the map. Outside playable tiles,
-- GROUND also acts as an invisible wall: remove it and correct only height,
-- preserving native interpolation. Normal on-map flight needs no writes.
function M.ground(inst,x,y,z)
    local map=TheWorld.Map
    if not map or not map.IsAboveGroundAtPoint then return end
    local ground=map:IsAboveGroundAtPoint(x,0,z,true)
    if inst._nw_ground_mask~=ground then
        if ground then RemovePhysicsColliders(inst) else inst.Physics:ClearCollisionMask() end
        inst._nw_ground_mask=ground
    end
    if math.abs(y)>.0001 then inst.Physics:TeleportRespectingInterpolation(x,0,z) end
end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function M.orbit_radius(p,speed)
    -- Apply the minimum before giant scaling: a slow, large projectile still
    -- needs room to turn. Faster projectiles get a wider base circle.
    local base=math.max(2.5,3.2*math.sqrt(math.max(0,speed or 0)/25))
    return math.min(8,base*math.sqrt(math.max(1,p and p.size_mult or 1)))
end
function M.turn(angle,desired,limit)
    local delta=(desired-angle+math.pi)%(2*math.pi)-math.pi
    return angle+clamp(delta,-limit,limit)
end
function M.reset(s,dx,dz)
    s.motor_angle,s.motor_speed=nil,nil
    s.heading=math.atan2(dz,dx);s.offx=0;s.offz=0;s.phase=0
    local f=s.p and s.p.flags or {}
    local speed=(s.speed or 0)*(f.spiral and .6 or 1)*(f.accelerate and .55 or 1)
    s.vx,s.vz=dx*speed,dz*speed
    s.accel_factor=f.accelerate and .55 or 1
end
function M.seek(s,f)
    local best,best_score
    local hx,hz=math.cos(s.heading),math.sin(s.heading)
    local impact=require("nw/engraved_impact")
    local key=s.p and s.p.engraving
    local filter=impact.filters[key] and not (s.p.flags and s.p.flags.targets) and impact.filters[key]
    local candidates=filter and TheSim:FindEntities(s.x,0,s.z,f.radius,{filter},{"INLIMBO","FX"}) or Effects.scan(s.x,s.z,f.radius,s.p and s.p.flags)
    for _,e in ipairs(candidates) do
        if e._nw_motion~=s and e._shot~=s
            and (e~=s.owner or s.p and s.p.flags and s.p.flags.targets) and e:IsValid()
            and not (s.p and s.p.id=="gust" and Targeting.breakable(e) and not Targeting.egg(e))
            -- Moving placements keep navigating during contact cooldown.
            -- Collision still owns repeat-hit timing and the piercing budget;
            -- ordinary projectiles retain their preference for fresh targets.
            and (s.placement or not s.hit[e] or s.age+.000001>=s.hit[e]) then
            local x,_,z=e.Transform:GetWorldPosition()
            local rx,rz=x-s.x,z-s.z
            local d2=rx*rx+rz*rz
            -- Eggs and dormant crystals are hittable spell props even though
            -- ordinary creature filters exclude nw_breakable. Use the same
            -- exception as collision/area attacks, without broadening teams.
            if d2<=f.radius*f.radius and (filter and impact.accepts(key,e) or not filter and (Targeting.hittable(s.owner,e,s.p and s.p.flags) or Targeting.selected_object(s.owner,e,s.p and s.p.flags))) then
                local dist=math.sqrt(d2)
                local dot=dist>.001 and clamp((hx*rx+hz*rz)/dist,-1,1) or 1
                -- Prefer a forward intercept. Within each hemisphere rank by
                -- estimated turning time plus flight time, then stable GUID.
                local speed=s.vx and math.sqrt(s.vx*s.vx+s.vz*s.vz) or s.speed or 0
                local score=(dot<0 and 100 or 0)+math.acos(dot)/((f.turn_rate or 240)*DEGREES)+dist/math.max(.1,speed)
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
        state.next_search=s.age+.1;state.target=M.seek(s,f)
    end
    local e=state.target
    if e and e:IsValid() then return e end
end
-- Homing is a force, rotation is a separate capability. Force parameters are
-- DST-scale choices; no claim of reproducing Noita's private engine formula.
local function propulsion(s,dt)
    local f=s.p.flags
    local ax,az,damping=0,0,s.drag or 0
    local guided=false
    local turn_rate=0
    local before=s.vx*s.vx+s.vz*s.vz>.000001 and math.atan2(s.vz,s.vx) or s.heading
    for _,key in ipairs({"homing","homing_short"}) do
        local h=f[key]
        if h then
            local target=seek_cached(s,key,h)
            if target then
                guided=true
                turn_rate=math.max(turn_rate,h.turn_rate or 360)
                local x,_,z=target.Transform:GetWorldPosition()
                local dx,dz=x-s.x,z-s.z
                local distance=math.sqrt(dx*dx+dz*dz)
                local near=key=="homing_short" or h.id=="near_homing"
                local force=h.acceleration or (near and 72 or 36)
                damping=damping+(h.damping or (near and 1.44 or .72))
                if distance>.001 then ax,az=ax+dx/distance*force,az+dz/distance*force end
            end
        end
    end
    local decay=math.exp(-damping*dt)
    local gain=damping>0 and (1-decay)/damping or dt
    s.vx,s.vz=s.vx*decay+ax*gain,s.vz*decay+az*gain
    if guided and s.vx*s.vx+s.vz*s.vz>.000001 then
        local speed=math.sqrt(s.vx*s.vx+s.vz*s.vz)
        local desired=ax*ax+az*az>.000001 and math.atan2(az,ax) or math.atan2(s.vz,s.vx)
        local angle=M.turn(before,desired,turn_rate*DEGREES*dt)
        s.vx,s.vz=speed*math.cos(angle),speed*math.sin(angle)
    end
end
-- Predict only the next native-physics velocity. Collision always sweeps the
-- actual replicated motion in projectiles.lua, including curved paths.
function M.steer(inst,s,dt)
    local f=s.p.flags
    if s.vx==nil then M.reset(s,s.dx or 1,s.dz or 0) end
    dt=math.max(0,dt)
    if dt==0 then return true end
    local heading_before=s.vx*s.vx+s.vz*s.vz>.000001 and math.atan2(s.vz,s.vx) or s.heading
    propulsion(s,dt)
    if f.accelerate then
        local factor=.55+.9*math.min(1,s.age/.7)
        local ratio=factor/(s.accel_factor or .55)
        s.vx,s.vz=s.vx*ratio,s.vz*ratio;s.accel_factor=factor
    end
    local base_speed=math.sqrt(s.vx*s.vx+s.vz*s.vz)
    local a=base_speed>.001 and math.atan2(s.vz,s.vx) or s.heading
    local orbiting=f.orbit and not s.escaped
    local vx,vz
    if orbiting then
        local ox,_,oz=s.owner.Transform:GetWorldPosition()
        if s.ox and (ox-s.ox)^2+(oz-s.oz)^2>16 then return false end
        s.ox,s.oz=ox,oz
        local rx,rz=s.x-ox,s.z-oz
        local radius=math.sqrt(rx*rx+rz*rz)
        local target_radius=M.orbit_radius(s.p,base_speed)
        local return_radius=target_radius+math.max(1.5,target_radius*.5)
        if radius>return_radius then
            vx,vz=-rx/radius*base_speed,-rz/radius*base_speed
            -- Rejoin from the current position instead of chasing an old phase.
            s.orbit_angle=nil;s.orbit_radius=nil
        else
            s.orbit_angle=s.orbit_angle or (radius>.05 and math.atan2(rz,rx) or a)
            if not s.orbit_started then
                s.orbit_angle=s.orbit_angle+(s.fan_angle or 0);s.orbit_started=true
            end
            local angular_speed=math.min(base_speed/target_radius,210*DEGREES)
            s.orbit_angle=s.orbit_angle+dt*angular_speed
            -- Ease into the ring with a 0.25 s time constant and a bounded
            -- radial speed. Owner translation must not perturb its radius.
            local step=math.min(8,base_speed*.5)*dt
            local previous=s.orbit_radius or radius
            local r=previous+clamp((target_radius-previous)*(1-math.exp(-dt/.25)),-step,step)
            s.orbit_radius=r
            vx=(ox+r*math.cos(s.orbit_angle)-s.x)/dt
            vz=(oz+r*math.sin(s.orbit_angle)-s.z)/dt
        end
        a=math.atan2(vz,vx)
    else
        if not s.reversed and ((f.reverse and s.age>=.45) or (f.returning and s.age>=.4)) then
            a=a+math.pi;s.reversed=true
            if s.p.ballistic then local v=inst.components.complexprojectile.velocity;v.y=math.abs(v.y) end
        end
        if f.returning and s.age>=.4 then
            local ox,_,oz=s.owner.Transform:GetWorldPosition()
            a=M.turn(a,math.atan2(oz-s.z,ox-s.x),180*DEGREES*dt)
        elseif f.homing_rotate then
            local target=seek_cached(s,"homing_rotate",f.homing_rotate)
            if target then
                local tx,_,tz=target.Transform:GetWorldPosition()
                a=M.turn(a,math.atan2(tz-s.z,tx-s.x),f.homing_rotate.turn_rate*DEGREES*dt)
            end
        end
        if f.homing_rotate and (f.homing or f.homing_short) then
            a=M.turn(heading_before,a,math.max(f.homing and f.homing.turn_rate or 0,
                f.homing_short and f.homing_short.turn_rate or 0,f.homing_rotate.turn_rate or 360)*DEGREES*dt)
        end
        vx,vz=base_speed*math.cos(a),base_speed*math.sin(a)
    end
    if orbiting then
        -- Keep propulsion separate from radial/owner-following corrections.
        -- External impulses still edit this same vector before propulsion;
        -- no private cached speed can overwrite them on the following tick.
        local drive=math.min(60,base_speed)
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
    vx=vx+(offx-s.offx)/dt;vz=vz+(offz-s.offz)/dt
    s.offx,s.offz=offx,offz
    local speed=math.sqrt(vx*vx+vz*vz)
    if speed>.001 then
        s.dx,s.dz=vx/speed,vz/speed
        local rotation=-math.atan2(vz,vx)/DEGREES
        if speed>60 then
            local scale=60/speed
            if not orbiting then s.vx,s.vz=s.vx*scale,s.vz*scale end
            speed=60
        end
        if rotation~=s.motor_angle or speed~=s.motor_speed then
            s.motor_angle,s.motor_speed=rotation,speed
            inst.Transform:SetRotation(rotation)
            if s.p.ballistic then inst.components.complexprojectile.velocity.x=speed
            else inst.Physics:SetMotorVel(speed,0,0) end
        end
    elseif s.motor_speed~=0 then
        s.motor_speed=0
        if s.p.ballistic then inst.components.complexprojectile.velocity.x=0
        else inst.Physics:SetMotorVel(0,0,0) end
    end
    return true
end
return M
