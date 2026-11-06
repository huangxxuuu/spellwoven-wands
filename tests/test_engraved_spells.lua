local roster=require("nw/engraved_spells")
local acquisition=require("nw/acquisition")
local rarity=require("nw/card_rarity")
local cards=require("nw/cards")
local defs=require("nw/definitions").spells
local compile=require("nw/compiler")

local retired=0
for id in pairs(roster.retired) do
    assert(cards.codes[id] and defs[id],id)
    assert(not acquisition.by_name["nw_inscribe_"..id] and not rarity.tiers[id],id)
    for _,ids in pairs(acquisition.by_material) do
        for _,candidate in ipairs(ids) do assert(candidate~=id,id) end
    end
    retired=retired+1
end
assert(retired==30 and cards.codes.edge_voidcloth_scythe<cards.codes.target_self)
for _,row in ipairs(roster.extra) do
    local id="edge_"..row[1]
    assert(cards.codes[id]>205 and acquisition.by_name["nw_inscribe_"..id].station=="nw_engraver")
    assert((defs[id].kind=="projectile" or defs[id].native_field) and rarity.tiers[id])
end

local function cast(...)
    local w=require("nw/generator").starter()
    w.stats.mana_max=600;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=compile.initial(w.cards,w.stats,1)
    return assert(compile.compile(w)).blocks[1].projectiles[1]
end
for _,id in ipairs({"chum","orangestaff","fishingrod","oceanfishingrod","voidcloth_scythe","farm_hoe","propsign"}) do
    assert(cast("damage_up","edge_"..id).damage==0)
end
assert(defs.edge_chum.delay==10)
local blink=cast("edge_orangestaff")
assert(blink.speed*blink.lifetime==27)
local boomerang=cast("edge_voidcloth_boomerang")
assert(boomerang.damage==5 and boomerang.planar==5 and boomerang.speed==15 and boomerang.speed*boomerang.lifetime==20)
local modified=cast("damage_up","speed_up","homing","edge_voidcloth_boomerang")
assert(modified.damage==15 and modified.speed==24.5 and modified.flags.homing)
assert(cast("edge_yoth_lance").flags.pierce.hits==3)
for _,id in ipairs({"dumbbell","dumbbell_golden","dumbbell_marble","dumbbell_gem","dumbbell_heat","dumbbell_redgem","dumbbell_bluegem"}) do
    local p=cast("speed_down","edge_"..id)
    assert(p.ballistic and p.speed<defs["edge_"..id].speed)
end
assert(defs.edge_hambat.damage==59.5 and defs.edge_whip.reach==4)
assert(defs.edge_shovel_lunarplant.work[1]=="DIG" and #defs.edge_shovel_lunarplant.work==1)
local flight=require("nw/engraved_flight")
local c={velocity={},SetGravity=function(self,g) self.gravity=g end}
local inst={components={complexprojectile=c},Physics={SetMotorVel=function() end}}
for _,distance in ipairs({1,8,20,30}) do
    local s={height=1.4,dx=1,dz=0,p={id="edge_farm_hoe",speed=18,flags={}}}
    flight.aim_ground(inst,s,distance)
    local time=distance/c.velocity.x
    assert(math.abs(1.4+c.velocity.y*time+.5*c.gravity*time*time)<1e-8)
    local speed=c.velocity.x
    s.p.speed=27;flight.aim_ground(inst,s,distance)
    assert(math.abs(c.velocity.x-speed*1.5)<1e-8)
    assert(s.vx==c.velocity.x and s.vz==0,"aimed arc must update shared steering velocity")
end
local native={IsValid=function() return true end,Transform={},Physics={}}
native.Physics.Teleport=function() error("native motion must not teleport each tick") end
native.Transform.SetRotation=function(_,r) native.angle=r end
native.Physics.SetMotorVel=function(_,vx,vy,vz) native.speed=vx;assert(vy==0 and vz==0) end
inst.Transform={GetRotation=function() return -73 end}
inst.Physics.GetMotorVel=function() return 22.5,0,0 end
flight.sync_native(inst,{native=native,native_height=1.4})
assert(native.angle==-73 and native.speed==22.5)
assert(defs.edge_lighter.kind=="projectile" and cast("giant_shot","edge_lighter").fire_radius==3)
local _,section=acquisition.card_section("explosion")
assert(section=="法术效果修正")
-- Orbit motors must move the body continuously; only the initial placement may teleport.
FRAMES=1/30;DEGREES=math.pi/180
local now=0
GetTime=function() return now end
local ox,oz=0,0
local owner={Transform={GetWorldPosition=function() return ox,0,oz end}}
local shield={x=0,z=0,Transform={},Physics={}}
shield.Transform.GetWorldPosition=function() return shield.x,0,shield.z end
shield.Transform.SetRotation=function(_,r) shield.r=r*DEGREES end
shield.Physics.Teleport=function(_,x,_,z) shield.x,shield.z=x,z end
shield.Physics.SetMotorVel=function(_,v) shield.v=v end
shield.Physics.Stop=function() shield.v=0 end
shield.ListenForEvent=function() end
local state={owner=owner,p={},remaining=5,time=0}
local orbit=require("nw/orbit_shield")
orbit.add(shield,state)
shield.Physics.Teleport=function() error("orbit must not teleport every frame") end
for i=1,90 do
    now=i*FRAMES;ox=ox+.03
    orbit.update(shield,state,now)
    shield.x=shield.x+math.cos(shield.r)*shield.v*FRAMES
    shield.z=shield.z-math.sin(shield.r)*shield.v*FRAMES
    assert(math.abs(math.sqrt((shield.x-ox)^2+(shield.z-oz)^2)-2)<1e-8)
end
print("engraved spells: retired sources, stable codes, directional boomerang, utility damage and seven ballistic throws")
