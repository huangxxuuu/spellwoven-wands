local C=require("nw/compiler")
local Cards=require("nw/cards")
local Kit=require("nw/spellkit")
local entries=require("nw/expansion")
local tiers=require("nw/card_rarity")
local recipes=require("nw/acquisition")
local drop_only={}
for id in ("wild_double near_homing bee_swarm fireflies glass_disc crit_rune star_vortex moon_fall tri_electric shock_ring storm_cloud deer_decoy vortex searing_halo side_embers twin_arc end_beam"):gmatch("%S+") do drop_only[id]=true end
local function cast(ids)
    local w=require("nw/generator").starter()
    w.stats.mana_max,w.stats.spread,w.stats.draw_count=600,6,1
    w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,9)
    return assert(C.compile(w))
end
assert(#entries==47 and #tiers.pool==186 and #Cards.order==220)
local page={}
for n=9,#Kit.pages do for _,id in ipairs(Kit.pages[n][2]) do page[id]=true end end
for i,d in ipairs(entries) do
    assert(page[d.id] and Cards.codes[d.id]==56+i and tiers.tiers[d.id]==d.tier)
    local recipe=recipes.by_name["nw_inscribe_"..d.id]
    assert((recipe~=nil)==(not drop_only[d.id]) and (not recipe or recipe.card==d.id),d.id)
end
for _,id in ipairs({"vital_ring","spore_sentry","rain_cloud","sleep_crystal","delay_seal"}) do
    assert(cast({id}).blocks[1].projectiles[1].speed==0)
    assert(cast({"speed_down",id}).blocks[1].projectiles[1].speed==0)
    assert(cast({"speed_up",id}).blocks[1].projectiles[1].speed==2)
    local home=cast({"near_homing",id}).blocks[1].projectiles[1]
    assert(home.speed==0 and home.flags.homing_short and not home.field_drive)
    assert(cast({"accelerate",id}).blocks[1].projectiles[1].speed==0)
end
local hex=cast({"hex_cast","spark","fire","arrow","frost","flint_lance","slime"})
assert(hex.projectile_count==6 and hex.mana_spent==78)
for i,p in ipairs(hex.blocks[1].projectiles) do assert(p.formation==60*(i-1)) end
local harmless=cast({"harmless","arrow_hit","end_beam"})
local carrier=harmless.blocks[1].projectiles[1]
assert(carrier.damage==0 and carrier.flags.harmless and carrier.payload)
local child=harmless.blocks[carrier.payload].projectiles[1]
assert(child.damage==12 and child.end_damage==16 and not child.flags.harmless)
local seal=cast({"delay_seal","wild_double","arrow","slime"})
local stored=seal.blocks[seal.blocks[1].projectiles[1].payload].projectiles
assert(#stored==2 and stored[1].spread==9 and stored[2].spread==11)
local light=cast({"light_shot","damage_up","flint_lance"}).blocks[1].projectiles[1]
assert(light.damage==22.5 and light.speed==30 and light.spread==0 and light.flags.pierce.hits==2)
local stars=cast({"damage_up","star_vortex"}).blocks[1].projectiles[1]
assert(stars.count==4 and stars.damage==8.5 and stars.lifetime==1)
local echo=cast({"repeat_4","payload_egg","end_beam"})
assert(echo.projectile_count==8)
for _,egg in ipairs(echo.blocks[1].projectiles) do
    local beam=echo.blocks[egg.payload].projectiles[1]
    assert(math.abs(beam.end_damage-7.2)<1e-6)
end
local Flight=require("nw/flight")
DEGREES=math.pi/180
local vel,angle
local obj={Transform={SetRotation=function(_,n) angle=n end},Physics={SetMotorVel=function(_,n) vel=n end}}
local s={x=0,z=0,speed=10,p={flags={accelerate={},reverse={}}},age=0}
Flight.reset(s,1,0);Flight.steer(obj,s,1/30)
assert(math.abs(vel-5.5)<1e-6 and math.abs(angle)<1e-6)
s.age=.7;Flight.steer(obj,s,1/30)
assert(math.abs(vel-14.5)<1e-6 and math.abs(math.abs(angle)-180)<1e-6)
s.age=.8;Flight.steer(obj,s,1/30)
assert(math.abs(math.abs(angle)-180)<1e-6)
local ret={x=4,z=0,speed=12,age=.4,p={flags={returning={}}},owner={Transform={GetWorldPosition=function() return 0,0,3 end}}}
Flight.reset(ret,1,0)
Flight.steer(obj,ret,1/30)
assert(ret.reversed and ret.dx<-.95 and ret.dz>0)
local first=ret.dz
Flight.steer(obj,ret,1/30)
assert(ret.dx<0 and ret.dz>first)
print("expansion: 47 registered, stable codes, recipes, six lanes, stored payloads, damage scopes and reversal")
