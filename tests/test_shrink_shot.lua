local C=require("nw/compiler")
local D=require("nw/definitions")
local Size=require("nw/projectile_size")
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a).." ~= "..tostring(b)) end
local function cast(...)
    local w=require("nw/generator").starter();w.stats.mana_max=10000;w.cards={}
    for i,id in ipairs({...}) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,5)
    local plan=assert(C.compile(w));return plan.blocks[1].projectiles[1],plan
end
for _,id in ipairs({"spark","grow_orb","end_beam","thrust","slash","chain","sleep_crystal","spore_sentry","bee_swarm","edge_yellowstaff","gunpowder"}) do
    local normal,small=cast(id),cast("shrink_shot",id)
    near(small.size_mult,.4)
    for _,key in ipairs({"damage","speed","lifetime","duration","burn_damage","freeze"}) do assert(small[key]==normal[key],id..": "..key) end
    for _,key in ipairs({"radius","reach","width","work_radius"}) do if normal[key] then near(small[key],normal[key]*.4) end end
end
near(Size.radius(cast("shrink_shot","spark")),.048)
near(Size.radius(cast("shrink_shot","grow_orb"),1),.42*.4)
near(cast("shrink_shot","shrink_shot","spark").size_mult,.16)
near(cast("shrink_shot","shrink_shot","shrink_shot","spark").size_mult,.1)
near(cast("giant_shot","shrink_shot","spark").size_mult,1)
near(cast("shrink_shot","giant_shot","spark").size_mult,1)
near(cast("giant_shot","giant_shot","shrink_shot","spark").size_mult,2)
near(cast("shrink_shot","shrink_shot","shrink_shot","giant_shot","spark").size_mult,.16)
local carrier,plan=cast("shrink_shot","arrow_hit","spark")
near(carrier.size_mult,.4);assert(not plan.blocks[carrier.payload].projectiles[1].size_mult)
carrier,plan=cast("arrow_hit","shrink_shot","spark")
assert(not carrier.size_mult);near(plan.blocks[carrier.payload].projectiles[1].size_mult,.4)
local shot,plan=cast("repeat_2","shrink_shot","sleep_crystal")
near(shot.radius,.72);assert(plan.blocks[1].copies==2 and D.spells.sleep_crystal.radius==1.8)
local cards=require("nw/cards")
assert(cards.order[#cards.order]=="shrink_shot" and cards.order[#cards.order-1]=="dark")
assert(cards.decode(cards.encode({{spell_id="shrink_shot"}},1))[1]=="shrink_shot")
assert(require("nw/card_rarity").tiers.shrink_shot==3)
local recipe=assert(require("nw/acquisition").by_name.nw_inscribe_shrink_shot)
assert(recipe.station=="nw_workbench" and recipe.product=="nw_spellcard" and recipe.card=="shrink_shot")
local ingredients={};for _,v in ipairs(recipe.ingredients) do ingredients[v[1]]=v[2] end
assert(ingredients.purplegem==1 and ingredients.moonrocknugget==3 and ingredients.nw_blank==1)
local tags=require("nw/card_tags").for_card("shrink_shot")
assert(tags.area and not tags.damage and not tags.speed and not tags.lifetime)
local Melee=require("nw/melee")
assert(Melee.contains(cast("thrust"),1.5,0,0,0,1))
assert(not Melee.contains(cast("shrink_shot","thrust"),1.5,0,0,0,1))
assert(Melee.contains(cast("shrink_shot","thrust"),.8,0,0,0,1))
assert(Melee.contains(cast("slash"),1.8,0,0,0,1))
assert(not Melee.contains(cast("shrink_shot","slash"),1.8,0,0,0,1))
local scale,body=1,.1
local inst={Transform={GetScale=function() return scale,scale,scale end,SetScale=function(_,s) scale=s end},
    components={projectile={hitdist=1,SetHitDist=function(self,r) self.hitdist=r end}},
    GetPhysicsRadius=function() return body end,SetPhysicsRadiusOverride=function(_,r) body=r end}
Size.native(inst,shot);Size.native(inst,shot);Size.field(inst,shot);Size.field(inst,shot)
near(scale,.4);near(inst.components.projectile.hitdist,.4);near(body,.04)
print("shrink shot: all spell categories, compatible stacking/floor, payload isolation, stable codes, recipe and one-time physical scaling")
