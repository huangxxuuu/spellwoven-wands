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
assert(retired==31 and cards.codes.edge_voidcloth_scythe<cards.codes.target_self)
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
    local vertical=c.velocity.y
    s.p.speed=500;flight.aim_ground(inst,s,distance)
    assert(c.velocity.x<=require("nw/spell_limits").max_speed+1e-8)
    assert(c.velocity.y==vertical,"horizontal launch cap must not change the vertical arc")
end
local native={IsValid=function() return true end,Transform={GetScale=function() return 2.5,2.5,2.5 end},Physics={}}
native.Physics.Teleport=function() error("native motion must not teleport each tick") end
native.Transform.SetRotation=function(_,r) native.angle=r end
native.Physics.SetMotorVel=function(_,vx,vy,vz) native.speed=vx;assert(vy==0 and vz==0) end
inst.Transform={GetRotation=function() return -73 end}
inst.Physics.GetMotorVel=function() return 22.5,0,0 end
flight.sync_native(inst,{native=native,native_height=1.4})
assert(native.angle==-73 and native.speed==9)
native.Transform.GetScale=function() return .4,.4,.4 end
inst.Physics.GetMotorVel=function() return 95,0,0 end
flight.sync_native(inst,{native=native,native_height=1.4})
assert(native.speed==95/.4,"local scaled motor may exceed 95 while world velocity remains 95")
assert(defs.edge_lighter.kind=="projectile" and cast("giant_shot","edge_lighter").fire_radius==3)
assert(cast("edge_lighter").ballistic,"lighter must use the same aimed arc as other thrown weapons")
local burst=0
local fire=require("nw/engraved_fire")
local original=fire.burst
fire.burst=function(_,_,x,z,r) assert(x==4 and z==6 and r==3);burst=burst+1 end
require("nw/engraved_impact").finish({p={engraving="lighter",ballistic=true,fire_radius=3}},4,6)
assert(burst==1,"landing must burst instead of entering the native dumbbell landing path")
fire.burst=original
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
local fog_steps=0
package.loaded["nw/dark_fog"]={trail=function(inst,_,x,z,nx,nz)
    assert(inst==shield and nx==shield.x and nz==shield.z)
    assert((nx-x)^2+(nz-z)^2<1,"orbit fog follows small accepted steps")
    fog_steps=fog_steps+1
end}
local state={owner=owner,p={flags={dark=true}},remaining=5,time=0}
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
assert(fog_steps==90,"special orbit flight also emits the dark trail")
package.loaded["nw/dark_fog"]=nil
state.p.flags={}
ox,oz=ox+20,oz+10;now=now+FRAMES
orbit.update(shield,state,now)
assert(shield.v==require("nw/spell_limits").max_speed,"shield catch-up must obey the shared horizontal cap")
local angle=(now+FRAMES)*3
local dx,dz=ox+2*math.cos(angle)-shield.x,oz+2*math.sin(angle)-shield.z
assert(math.abs(shield.r+math.atan2(dz,dx))<1e-8,"clipping shield speed must preserve its direction")

-- Only detached spell boomerangs receive the native return wrapper. Cover its
-- immediate launch and subsequent native acceleration in scaled world units.
do
    local Journal=require("nw/journal_damage");local tag=Journal.tag
    Journal.tag=function() end
    local Impact=require("nw/engraved_impact")
    for _,scale in ipairs({.4,2.5,10}) do
        local motor={0,0,0}
        local bolt={components={},Transform={GetScale=function() return scale,scale,scale end},Physics={},
            IsValid=function() return true end,FacePoint=function() end}
        bolt.Physics.GetMotorVel=function() return unpack(motor) end
        bolt.Physics.SetMotorVel=function(_,x,y,z) motor={x,y,z} end
        local native_return=function(inst) inst.Physics:SetMotorVel(35,7,0) end
        bolt.ReturnToThrower=native_return
        local looper={inst=bolt,OnUpdate=function(self) self.inst.Physics:SetMotorVel(300,7,400) end}
        bolt.components.updatelooper=looper
        local s={owner=owner,p={engraving="voidcloth_boomerang"},native=bolt}
        Impact.finish(s,0,0)
        assert(s.native==nil and bolt.ReturnToThrower~=native_return)
        assert(math.abs(motor[1]*scale-35)<1e-8 and motor[2]==7)
        for _=1,2 do
            looper:OnUpdate(FRAMES)
            assert(math.abs(motor[1]*scale-57)<1e-8 and math.abs(motor[3]*scale-76)<1e-8 and motor[2]==7,
                "native return acceleration must remain bounded after every update without altering vertical velocity")
        end
    end
    Journal.tag=tag
end

-- Fishing hands a native fish projectile its horizontal launch speed. Cap
-- that handoff too, retaining the native lower floor and gravity selection.
do
    local old_vector,old_spawn=Vector3,SpawnPrefab
    local vec={};vec.__index=vec
    Vector3=function(x,y,z) return setmetatable({x=x,y=y,z=z},vec) end
    function vec:Get() return self.x,self.y,self.z end
    function vec:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
    function vec:GetNormalizedAndLength() local n=self:Length();return self*(1/n),n end
    vec.__add=function(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
    vec.__sub=function(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
    vec.__mul=function(a,n) return Vector3(a.x*n,a.y*n,a.z*n) end
    SpawnPrefab=function() return {Transform={SetPosition=function() end},FacePoint=function() end} end
    local old_map=TheWorld.Map
    TheWorld.Map={IsPassableAtPoint=function() return false end}
    local Native=require("nw/native_targeting");local accepts=Native.accepts
    Native.accepts=function() return true end
    local angler={components={},GetPosition=function() return Vector3(0,0,0) end,
        Transform={GetWorldPosition=function() return 0,0,0 end},PushEvent=function() end}
    for _,speed in ipairs({5,30,500}) do
        local launched=false
        local cp={SetGravity=function(self,g) self.gravity=g end,
            SetLaunchOffset=function() end,SetTargetOffset=function() end,
            CalculateMinimumSpeedForDistance=function(_,distance) assert(distance==20);return speed end,
            SetHorizontalSpeed=function(self,v) self.speed=v end,
            Launch=function() launched=true end}
        local fish={components={complexprojectile=cp},Transform={SetPosition=function() end}}
        local target={components={oceanfishable={MakeProjectile=function() return fish end}},
            GetPosition=function() return Vector3(20,0,0) end,
            Transform={GetWorldPosition=function() return 20,0,0 end}}
        assert(require("nw/engraved_impact").hit({owner=angler,p={engraving="oceanfishingrod",flags={}}},target,20,0))
        assert(launched and cp.speed==math.min(95,math.max(12,speed)) and cp.gravity==-30)
    end
    local Journal=require("nw/journal_damage");local tag=Journal.tag
    Journal.tag=function() end
    local old_tuning=TUNING;TUNING={STAFF_LUNARPLANT_BOUNCES=3,TORNADO_LIFETIME=20}
    local old_orientation=ANIM_ORIENTATION;ANIM_ORIENTATION={BillBoard=1}
    local bounce=Native.bounce;Native.bounce=function() end
    SpawnPrefab=function(name)
        assert(name=="staff_lunarplant")
        return {components={inventoryitem={}},Transform={SetPosition=function() end},RemoveFromScene=function() end}
    end
    for _,scale in ipairs({.4,2.5,10}) do
        local bolt={components={},_nw_size=scale,_nw_hit_scaled=true,
            Transform={GetScale=function() return scale,scale,scale end},
            Physics={Teleport=function() end},entity={SetCanSleep=function() end},
            AnimState={SetOrientation=function() end},ListenForEvent=function() end,IsValid=function() return true end}
        local cp={inst=bolt,speed=15,SetSpeed=function(self,speed) self.speed=speed end,
            Hit=function(self) self:SetSpeed(300) end}
        bolt.components.projectile=cp
        local Impact=require("nw/engraved_impact")
        local target={HasTag=function() return false end}
        Impact.hit({owner=angler,native=bolt,hits_left=1,p={engraving="staff_lunarplant",size_mult=scale}},target,0,0)
        assert(math.abs(cp.speed*scale-95)<1e-8,"native bounce caps its scaled world speed")
        cp:SetSpeed(10)
        assert(math.abs(cp.speed*scale-10)<1e-8,"later native bounce retains its original world speed")

        local resumed=false
        local tornado={components={knownlocations={RememberLocation=function() end},locomotor={walkspeed=30,runspeed=300}},
            Transform={GetScale=function() return scale,scale,scale end},Physics={Teleport=function() end},
            IsValid=function() return true end,SetDuration=function() end,sg={GoToState=function() end},
            RestartBrain=function() resumed=true end}
        Impact.finish({owner=angler,native=tornado,p={engraving="staff_tornado"}},0,0)
        assert(resumed and math.abs(tornado.components.locomotor.walkspeed*scale-30)<1e-8
            and math.abs(tornado.components.locomotor.runspeed*scale-95)<1e-8,
            "native tornado resumes with bounded world speeds at every spell size")
    end
    Native.bounce=bounce;Journal.tag=tag;TUNING=old_tuning
    ANIM_ORIENTATION=old_orientation
    Native.accepts=accepts;TheWorld.Map=old_map;Vector3=old_vector;SpawnPrefab=old_spawn
end
print("engraved spells: retired sources, stable codes, directional boomerang, utility damage and seven ballistic throws")
