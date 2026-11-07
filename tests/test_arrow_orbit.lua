-- Focused integration of the real steering code with a constant-velocity
-- native motor. No graphics, collision mocks, server or full suite required.
local Flight=require("nw/flight")
DEGREES=math.pi/180
local function near(actual,expected,tolerance)
    assert(math.abs(actual-expected)<(tolerance or 1e-7),tostring(actual).." ~= "..tostring(expected))
end
local function magnitude(s) return math.sqrt(s.vx*s.vx+s.vz*s.vz) end
local function make(size,speed,id,extra)
    local owner={x=0,z=0,Transform={}}
    owner.Transform.GetWorldPosition=function() return owner.x,0,owner.z end
    local e={x=1,z=0,motor=0,rotation=0,Transform={},Physics={}}
    e.Transform.SetRotation=function(_,a) e.rotation=a end
    e.Physics.SetMotorVel=function(_,v) e.motor=v end
    local flags={orbit={radius=2}}
    for key,value in pairs(extra or {}) do flags[key]=value end
    local p={id=id or "arrow",flags=flags,size_mult=size or 1}
    if id=="arrow_hit" or id=="arrow_timer" then p.base="arrow" end
    local s={p=p,owner=owner,speed=speed or 25,age=0,x=e.x,z=e.z}
    Flight.reset(s,1,0)
    return {e=e,s=s,owner=owner}
end
local function step(sim,dt,owner_speed)
    local e,s,owner=sim.e,sim.s,sim.owner
    owner.x=owner.x+(owner_speed or 0)*dt
    s.age=s.age+dt
    assert(Flight.steer(e,s,dt),"ordinary owner movement must retain an orbiting projectile")
    local motor=s.p.ballistic and e.components.complexprojectile.velocity.x or e.motor
    e.x=e.x+math.cos(-e.rotation*DEGREES)*motor*dt
    e.z=e.z+math.sin(-e.rotation*DEGREES)*motor*dt
    s.x,s.z=e.x,e.z
    return math.sqrt((e.x-owner.x)^2+(e.z-owner.z)^2)
end
local function run(sim,seconds,dt,owner_speed)
    local radius
    for _=1,math.floor(seconds/dt+.5) do radius=step(sim,dt,owner_speed) end
    return radius
end

-- Ordinary, giant, capped giant and trigger variants settle at larger circles.
local cases={
    {1,25,"arrow",3.2},
    {2.5,25,"arrow",5.0596442562694},
    {5,25,"arrow_hit",7.1554175279993},
    {7.5,25,"arrow_timer",8},
    {1,30,"arrow",3.5054243680331},
    {1,5,"arrow",2.5},
    {1,8.75,"heavy",2.5},
    {2.5,8.75,"heavy",3.9528470752105},
    {5,8.75,"heavy_timer",5.5901699437495},
    {1,15,"scatter",2.5},
    {2.5,15,"fire",3.9528470752105},
    {5,15,"frost",5.5901699437495},
    {1,17.5,"spark",2.6773120849090},
    {2.5,2,"heavy",3.9528470752105},
}
for _,case in ipairs(cases) do
    local sim=make(case[1],case[2],case[3])
    near(run(sim,6,1/30),case[4],1e-5)
    near(magnitude(sim.s),case[2])
end

-- Entry is eased; a single 30 Hz update cannot yank the radius to its target.
local entry=make(5)
local r=step(entry,1/30)
assert(r>1 and r<=1+8/30+1e-9)
assert(entry.s.orbit_angle<=210*DEGREES/30+1e-9)

-- The discrete motor follows the same ring/phase at 30 Hz and 60 Hz.
local coarse,fine=make(2.5),make(2.5)
run(coarse,4,1/30);run(fine,4,1/60)
near(coarse.e.x,fine.e.x,1e-5);near(coarse.e.z,fine.e.z,1e-5)
near(magnitude(coarse.s),magnitude(fine.s))

-- Following a walking owner adds actual motor velocity, not future propulsion.
local moving=make(2.5)
near(run(moving,6,1/30,6),5.0596442562694,1e-5)
near(magnitude(moving.s),25)
assert(moving.e.motor<=60)
local moving_heavy=make(2.5,8.75,"heavy")
near(run(moving_heavy,6,1/30,6),3.9528470752105,1e-5)
near(magnitude(moving_heavy.s),8.75)

-- Native ballistic carriers use the same horizontal ring, preserving height.
local ballistic=make(2.5,8.75,"edge_lighter")
ballistic.s.p.ballistic=true
ballistic.e.components={complexprojectile={velocity={x=8.75,y=7}}}
near(run(ballistic,6,1/30),3.9528470752105,1e-5)
near(ballistic.e.components.complexprojectile.velocity.y,7)

-- An external impulse edits the live vector and survives the next update.
local impulse=make()
run(impulse,1,1/30)
impulse.s.vx,impulse.s.vz=impulse.s.vx*1.2,impulse.s.vz*1.2
step(impulse,1/30)
near(magnitude(impulse.s),30)
near(run(impulse,4,1/30),3.5054243680331,1e-5)

-- Existing acceleration and drag affect propulsion before orbit is computed.
local accelerated=make(1,25,nil,{accelerate={}})
run(accelerated,1,1/30);near(magnitude(accelerated.s),25*1.45)
local damped=make()
damped.s.drag=.3
run(damped,2,1/30);near(magnitude(damped.s),25*math.exp(-.6))

-- Formation phase is applied once, and a truly stationary arrow is not spun.
local fan=make()
fan.s.fan_angle=.5
step(fan,1/30);near(fan.s.orbit_angle,.5+210*DEGREES/30)
step(fan,1/30);near(fan.s.orbit_angle,.5+2*210*DEGREES/30)
local stationary=make(1,0)
run(stationary,1,1/30);near(stationary.e.motor,0);near(stationary.e.x,1)

-- Real wall reflection resets the vector to the reflected actual motor speed
-- and marks escaped. The next updates must continue straight without re-entry.
local reflected=make()
run(reflected,2,1/30)
local reflected_speed=reflected.e.motor
local dx,dz=-reflected.s.dx,-reflected.s.dz
reflected.s.escaped=true
Flight.reset(reflected.s,dx,dz)
reflected.s.vx,reflected.s.vz=dx*reflected_speed,dz*reflected_speed
local bx,bz=reflected.e.x,reflected.e.z
run(reflected,.5,1/30)
near(reflected.e.x,bx+dx*reflected_speed*.5)
near(reflected.e.z,bz+dz*reflected_speed*.5)
near(reflected.e.motor,reflected_speed)

-- Owner teleport cleanup remains unchanged; all ordinary projectile kinds
-- receive the common radius without a kind-specific allowlist.
local teleported=make()
step(teleported,1/30);teleported.owner.x=teleported.owner.x+5
assert(not Flight.steer(teleported.e,teleported.s,1/30))
for id,p in pairs(require("nw/definitions").spells) do
    if p.kind=="projectile" or p.kind=="trigger" then
        local sim=make(2.5,p.speed,id)
        near(run(sim,6,1/30),Flight.orbit_radius(sim.s.p,p.speed),1e-5)
        near(magnitude(sim.s),p.speed)
    end
end
print("Shared orbit: all projectile kinds, giant/slow heavy, ballistic, entry, timestep, owner movement, impulse and escape passed")
