local S=require("nw/sources")
local R=require("nw/card_rarity")
local Catalog=require("nw/natural_loot")
local function never() error("an ineligible victory rolled the fallback") end
assert(#R.pool==188)
local seen={}
local n=0
for _,id in ipairs(R.pool) do
    assert(not seen[id] and R.tiers[id]);seen[id]=true
    if id~="edge_propsign" then
        n=n+1
        assert(S.finish_card(201,nil,false,1,function(size)
            if size then assert(size==187);return n end
            return .00009999
        end)==id)
    end
end
assert(not seen.trigger_hit and not seen.trigger_timer and not seen.weak_homing)
assert(not S.finish_card(200,nil,false,1,never))
assert(not S.finish_card(10000,nil,true,1,never))
assert(not S.finish_card(10000,nil,false,0,never))
assert(S.finish_card(10000,"arrow",false,1,never)=="arrow")
assert(not S.finish_card(300,nil,false,1,function() return .0001 end))

-- Exact fallback boundaries for each configured drop multiplier. Difficulty
-- changes only this last-chance roll, never the ordinary species/material odds.
local B=require("nw/balance")
for _,mode in ipairs({"fun","balanced","balanced_loot"}) do
    B.configure(mode)
    for _,mult in ipairs({.5,1,2,3,5,10}) do
        local chance=(mode=="balanced_loot" and .0005 or .0001)*mult
        assert(S.finish_card(201,nil,false,mult,function(size)
            return size and 1 or chance-1e-10
        end))
        assert(not S.finish_card(201,nil,false,mult,function() return chance end))
    end
    assert(not S.finish_card(200,nil,false,10,never))
    assert(not S.finish_card(10000,nil,true,10,never))
    assert(not S.finish_card(10000,nil,false,0,never))
    assert(S.finish_card(10000,"arrow",false,10,never)=="arrow")
end
B.configure("fun")

local function roll(name, values, mult)
    local rule=S.by_prefab[name] or {}
    local pool=S.material_pool(Catalog[name],rule.group)
    local i=0
    return S.roll(name,rule,pool,mult or 1,1,function()
        i=i+1;return assert(values[i], "unexpected roll "..i)
    end).card
end
local normal=roll("hound",{1,.004})
local pool_before=table.concat(S.material_pool(Catalog.hound),",")
B.configure("balanced_loot")
assert(roll("hound",{1,.004})==normal)
assert(table.concat(S.material_pool(Catalog.hound),",")==pool_before,"crafting bans must preserve material loot pools")
B.configure("fun")
assert(roll("bee",{0,0})=="spore_sentry" and roll("bee",{0,.999})=="spore_sentry")
-- Goose feathers now inscribe both Gust and Trident Cast. The material pool is
-- sorted, then weighted by rarity: common Gust 1, uncommon Trident Cast .65.
local feather_pool=S.material_pool(Catalog.mossling)
assert(#feather_pool==2 and feather_pool[1]=="gust" and feather_pool[2]=="trident_cast")
local feather_split=1/1.65
assert(roll("mossling",{0,0})=="gust" and roll("mossling",{0,feather_split-.00001})=="gust")
assert(roll("mossling",{0,feather_split+.00001})=="trident_cast" and roll("mossling",{0,.999})=="trident_cast")
assert(roll("crabking",{.99,.02999})=="repeat_4")
assert(roll("walrus",{.07799,0})=="speed_up" and roll("walrus",{.07799,.999})=="speed_up" and not roll("walrus",{.07801}))
assert(roll("pigman",{.00499})=="edge_propsign" and not roll("pigman",{.00501}))
local function contains(pool,id)
    for _,item in ipairs(pool) do if item==id then return true end end
end
local rules=require("nw/acquisition")
for name,entries in pairs(S.signature) do
    assert(Catalog[name],name)
    local rule=S.by_prefab[name] or {}
    local lower=0
    for _,entry in ipairs(entries) do
        assert(R.tiers[entry.id] and not rules.by_name["nw_inscribe_"..entry.id],entry.id)
        local midpoint=lower+.5*entry.rate
        local draws={midpoint}
        if (rule.group and rule.group~="D") or rule.dustchance then table.insert(draws,1,.99) end
        assert(roll(name,draws)==entry.id,name.."/"..entry.id)
        lower=lower+entry.rate
    end
    assert(math.abs(lower-entries.total)<1e-10)
end
for _,ids in pairs(rules.by_material) do
    for _,id in ipairs(ids) do
        assert(not require("nw/arsenal").notes[id] and not id:match("^target_"),id)
    end
end
assert(roll("moose",{.99,.2999,0,.9}) and not roll("moose",{.99,.3001}))
assert(roll("minotaur",{.99,.12001})=="twin_arc" and roll("minotaur",{.99,.24001})=="end_beam")
assert(not rules.by_name.nw_inscribe_edge_propsign)
for _,id in ipairs(S.material_pool({nightmarefuel=true,bluegem=true,livinglog=true})) do
    assert(not require("nw/arsenal").weapons[id] and id~="thrust" and id~="slash" and id~="whirl",id)
end
for name,id in pairs({tentacle="edge_tentaclespike",twins="edge_shieldofterror",bat="edge_batbat",lightninggoat="edge_nightstick"}) do
    assert(contains(S.material_pool(Catalog[name]),id))
end
-- Double Cast now uses gears/nightmare fuel, so silk only supplies the two
-- common cards below; the dense-species total chance remains exactly 2%.
local silk_pool=S.material_pool(Catalog.spider)
assert(#silk_pool==2 and silk_pool[1]=="slime" and silk_pool[2]=="speed_down")
assert(roll("spider",{0,.0199,0})=="slime" and roll("spider",{0,.0199,.49999})=="slime")
assert(roll("spider",{0,.0199,.50001})=="speed_down" and not roll("spider",{0,.0201}))
assert(roll("bearger",{.99,.01999})=="pierce_all")
assert(roll("beequeen",{.99,.02999})=="repeat_3")
assert(roll("shrouden",{.15999})=="repeat_3")
assert(not roll("shrouden",{.6601}))
-- 0.65 total x2 caps at 100%. The signature retains its share of that 100%.
assert(roll("shrouden",{.16/.65-.00001},2)=="repeat_3")
assert(roll("shrouden",{.16/.65+.00001,0},2)~="repeat_3")

local function loadout(n,rolls)
    local i=0
    return S.wand_cards(S.by_prefab.dragonfly,n,function()
        i=i+1;return assert(rolls[i])
    end)
end
local two=loadout(2,{0,0})
assert(two[1]=="heal_ally" and two[2]=="heavy" and #two==2)
for i,id in ipairs({"imprint_hit","imprint_timer","heal_ally"}) do
    local three=loadout(3,{0,.119,i})
    assert(three[1]==id and three[2]=="heavy" and three[3]==(i<3 and "spark" or nil))
end
local normal=loadout(3,{0,.121,.14,.99,.29})
assert(normal[1]=="heavy_hit" and normal[2]=="spark_timer")
print("card sources: "..n.." distinct fallback cards, gates, exact single-card odds, capped multiplier and boss slots")
