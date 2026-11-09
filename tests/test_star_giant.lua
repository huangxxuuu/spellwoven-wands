RemovePhysicsColliders=function(e) e.no_terrain_collision=true end
local C=require("nw/compiler")
local D=require("nw/definitions").spells
local Size=require("nw/projectile_size")
local function cast(...)
    local w=require("nw/generator").starter();w.stats.mana_max=2000;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,5)
    local plan=assert(C.compile(w));return plan.blocks[1].projectiles[1],plan
end
local hot,plan=cast("edge_yellowstaff")
assert(hot.kind=="field" and hot.speed==0 and plan.cooldown==240)
local cold,plan=cast("recharge_down","edge_opalstaff")
assert(cold.speed==0 and plan.cooldown==60)
local carrier,plan=cast("arrow_hit","edge_yellowstaff")
assert(plan.cooldown==240 and plan.blocks[carrier.payload].projectiles[1].native_field=="stafflight")
assert(cast("speed_up","edge_yellowstaff").speed==2)
assert(cast("speed_down","edge_yellowstaff").speed==0)
local following=cast("target_self","homing","edge_opalstaff")
assert(following.speed==0 and following.flags.targets.self)
assert(math.abs(cast("speed_up","speed_down","edge_opalstaff").speed-2)<1e-9)
local normal=cast("spark")
local big=cast("giant_shot","giant_shot","spark")
assert(big.size_mult==5 and big.damage==normal.damage and big.speed==normal.speed and big.lifetime==normal.lifetime)
assert(math.abs(Size.radius(big)-.6)<1e-9)
assert(Size.radius(cast("giant_shot","edge_voidcloth_scythe"))==4)
assert(math.abs(Size.radius(cast("giant_shot","grow_orb"),1)-1.05)<1e-9)
for _,id in ipairs({"chain","slash","crystal_mine","edge_yellowstaff"}) do assert(cast("giant_shot",id).size_mult==2.5) end
assert(cast("giant_shot","giant_shot","giant_shot","spark").size_mult==7.5)
local area=cast("giant_shot","giant_shot","explosion","spark")
assert(area.flags.explosive_hit.radius==3 and area.flags.explosive_hit.explosion_damage==25 and area.size_mult==5)
local stab=cast("giant_shot","giant_shot","thrust")
assert(stab.reach==12 and stab.width==5 and stab.damage==27.2)
local crystal=cast("giant_shot","giant_shot","sleep_crystal")
assert(crystal.radius==9 and crystal.damage==22)
local copied,copyplan=cast("repeat_2","giant_shot","giant_shot","sleep_crystal")
assert(copied.radius==9 and copyplan.blocks[1].copies==2 and #copyplan.blocks[1].projectiles==1)
assert(D.explosion.radius==3 and D.thrust.reach==2.4 and D.sleep_crystal.radius==1.8)
local carrier,plan=cast("giant_shot","arrow_hit","spark")
assert(carrier.size_mult==2.5 and not plan.blocks[carrier.payload].projectiles[1].size_mult)
local carrier,plan=cast("arrow_hit","giant_shot","spark")
assert(not carrier.size_mult and plan.blocks[carrier.payload].projectiles[1].size_mult==2.5)
local n={components={projectile={hitdist=1,SetHitDist=function(self,v) self.hitdist=v end}},Transform={}}
local s=1;n.Transform.GetScale=function() return s,s,s end;n.Transform.SetScale=function(_,v) s=v end
Size.native(n,big);Size.native(n,big)
assert(s==5 and n.components.projectile.hitdist==5)
-- An offline star must stop without looking up crystal persistence state.
local time,task,motor=0,nil,nil
GetTime=function() return time end;FRAMES=1/30;DEGREES=math.pi/180
local active=false
local caster={IsValid=function() return true end,HasTag=function() return false end,components={}}
TheSim={FindEntities=function() return {} end}
local star={entity={SetCanSleep=function() end},Transform={GetWorldPosition=function() return 0,0,0 end,SetRotation=function() end},
    Physics={Stop=function() end,SetMotorVel=function(_,v) motor=v end,ClearCollisionMask=function() end},_nw_motion_owner=function() return active and caster or nil end,
    IsValid=function() return true end,
    DoPeriodicTask=function(_,_,fn) task=fn;return {Cancel=function() end} end}
require("nw/field_motion").start(star,nil,cast("speed_up","edge_yellowstaff"),1,0)
assert(motor==0);time=1;task();assert(star._nw_motion.age==0)
active=true;time=2;task()
assert(math.abs(motor-2*math.exp(-require("nw/field_motion").drag))<1e-9 and star._nw_motion.age==1)
print("stars and giant: native placements, cooldown in payloads, steering, selective scale, no double scale and offline motion")
