-- Compile and steer real descriptors across the shared speed ceiling.
local C=require("nw/compiler")
local D=require("nw/definitions")
local F=require("nw/flight")
local Limits=require("nw/spell_limits")
local Copy=require("nw/util").copy
local function close(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." ~= "..tostring(b)) end
local function cast(id,modifier,count,definitions)
    local w=require("nw/generator").starter()
    w.stats.mana_max=100000;w.stats.draw_count=1;w.cards={}
    for i=1,count or 0 do w.cards[#w.cards+1]={spell_id=modifier,card_uid="m"..i} end
    w.cards[#w.cards+1]={spell_id=id,card_uid="shot"}
    if (definitions or D.spells)[id].event then
        w.cards[#w.cards+1]={spell_id="spark",card_uid="payload"}
    end
    w.runtime=C.initial(w.cards,w.stats,1)
    local plan,err=C.compile(w,definitions)
    assert(plan,id..": "..tostring(err))
    return assert(plan.blocks[1].projectiles[1])
end
close(Limits.max_speed,95)
for n,speed in ipairs({26,41,62.5,93.75,95}) do close(cast("end_beam","speed_up",n-1).speed,speed) end
for _,id in ipairs({"edge_firestaff","edge_icestaff"}) do
    close(cast(id,"speed_up",1).speed,77)
    close(cast(id,"speed_up",2).speed,95)
end
local travelling,fields=0,0
for _,id in ipairs(D.order) do
    local d=D.spells[id]
    if d.kind=="projectile" or d.kind=="trigger" then
        travelling=travelling+1
        close(cast(id,"speed_up",48).speed,95)
        close(cast(id,"speed_down",48).speed,2)
    elseif d.kind=="field" then
        fields=fields+1
        close(cast(id,"speed_up",48).speed,95)
        close(cast(id,"speed_down",48).speed,0)
        close(cast(id,nil,0).speed,0)
    end
end
-- A future faster base definition must obey the same ceiling too.
local custom=Copy(D.spells);custom.spark.speed=120
close(cast("spark",nil,0,custom).speed,95)
local Field=require("nw/field_effects")
close(Field.shot({child_modifiers={speed_mult=10,speed_add=2}},"spark",14,.36).speed,95)
close(Field.shot({child_modifiers={speed_mult=0}},"spark",14,.36).speed,2)

DEGREES=math.pi/180
-- Direct descriptors and old payloads may bypass the compiler. Limit the
-- initial horizontal vector before any native motor is set, retaining heading.
for _,direction in ipairs({{.6,.8},{-.6,.8},{0,-1}}) do
    local launch={p={flags={}},speed=500}
    F.reset(launch,direction[1],direction[2])
    close(launch.vx,direction[1]*Limits.max_speed)
    close(launch.vz,direction[2]*Limits.max_speed)
end
local owner={Transform={GetWorldPosition=function() return 0,0,0 end}}
local function steering(speed,flags,steps)
    local motor,peak=0,0
    local inst={Transform={SetRotation=function() end},Physics={SetMotorVel=function(_,v) motor=v end}}
    local s={owner=owner,p={id="spark",flags=flags or {}},speed=speed,age=0,x=4,z=0,hit={}}
    F.reset(s,1,0)
    for frame=1,steps or 1 do
        s.age=frame/30
        assert(F.steer(inst,s,1/30))
        peak=math.max(peak,motor)
        assert(motor<=95+1e-6,"motor exceeds the shared ceiling")
        assert(math.sqrt(s.vx*s.vx+s.vz*s.vz)<=95+1e-6,"propulsion retains clipped excess speed")
    end
    return motor,s,peak
end
for _,speed in ipairs({62.5,93.75}) do
    local motor,s=steering(speed,{},30)
    close(motor,speed);close(s.vx,speed)
end
local motor,s=steering(120,{},30)
close(motor,95);close(s.vx,95)
motor,s=steering(93.75,{accelerate=Copy(D.spells.accelerate)},30)
close(motor,95);close(s.vx,95)
-- Curved offsets and orbit correction also share the total motor ceiling.
local _,_,curve_peak=steering(93.75,{sine=Copy(D.spells.sine),spiral=Copy(D.spells.spiral)},60)
assert(curve_peak>60,"curved movement still has the old motor ceiling")
local _,orbit=steering(120,{orbit={}},60)
close(math.sqrt(orbit.vx*orbit.vx+orbit.vz*orbit.vz),95)
print(string.format("speed limits: %d travelling definitions, %d fields, shared 95 ceiling, slow floors and real straight/accelerating/curved/orbit steering",travelling,fields))
