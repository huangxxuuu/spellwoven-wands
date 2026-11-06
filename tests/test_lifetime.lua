local C=require("nw/compiler")
local D=require("nw/definitions").spells
local function cast(...)
    local w=require("nw/generator").starter();w.stats.mana_max=2000;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,5)
    local plan=assert(C.compile(w));return plan.blocks[1].projectiles[1],plan
end
local function near(a,b) assert(math.abs(a-b)<1e-9,tostring(a).." ~= "..tostring(b)) end
-- Extension remains proportional beyond the former 7.5 second ceiling.
local many={};for i=1,10 do many[i]="long_life" end;many[11]="heavy"
near(cast(unpack(many)).lifetime,D.heavy.lifetime*1.35^10)
assert(cast(unpack(many)).lifetime>30)
near(cast("short_life","spark").lifetime,D.spark.lifetime*.5)
near(cast("short_life","short_life","spark").lifetime,D.spark.lifetime*.25)
near(cast("short_life","long_life","heavy").lifetime,D.heavy.lifetime*.5*1.35)
near(cast("long_life","short_life","heavy").lifetime,D.heavy.lifetime*.5*1.35)
local p=cast("short_life","spark")
assert(p.speed==D.spark.speed and p.damage==D.spark.damage)
near(cast("orbit","short_life","spark").lifetime,2)
near(cast("short_life","orbit","spark").lifetime,2)
near(cast("orbit","long_life","long_life","long_life","spark").lifetime,4*1.35^3)
near(cast("short_life","short_life","short_life","short_life","spark").lifetime,.1)
-- Parent and triggered payload have independent lifetime modifiers.
local carrier,plan=cast("short_life","arrow_hit","spark")
near(carrier.lifetime,D.arrow.lifetime*.5)
near(plan.blocks[carrier.payload].projectiles[1].lifetime,D.spark.lifetime)
carrier,plan=cast("arrow_hit","short_life","spark")
near(carrier.lifetime,D.arrow.lifetime)
near(plan.blocks[carrier.payload].projectiles[1].lifetime,D.spark.lifetime*.5)
carrier=cast("short_life","short_life","arrow_timer","spark")
near(carrier.time,.5);assert(carrier.lifetime<carrier.time)
-- Instant effects and permanent/native fields keep their own rules.
for _,id in ipairs({"chain","crystal_mine","sleep_crystal","payload_egg","edge_yellowstaff","edge_opalstaff"}) do
    local base=cast(id);p=cast("short_life",id)
    assert(p.kind==base.kind and p.lifetime==base.lifetime and p.cooldown==base.cooldown)
end
assert(require("nw/card_rarity").tiers.short_life==2)
assert(require("nw/spell_info").playable.short_life)
local recipe=require("nw/acquisition").by_name.nw_inscribe_short_life
assert(recipe and recipe.station=="nw_workbench")
