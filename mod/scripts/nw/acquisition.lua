local T=require("nw/locale").t
local Cards = require("nw/cards")
local M = {}
M.atlas = "images/inventoryimages/nw_supplies.xml"
M.station_atlas = "images/inventoryimages/nw_stations.xml"
M.card_atlas = "images/inventoryimages/nw_icons.xml"
M.materials = {
    nw_dust = { T("奥术粉尘"), T("宝石碾出的晶粉，用于制杖和浸染空白卡。"), 40 },
    nw_blank = { T("空白法术卡"), T("用粉尘浸过的莎草纸，可以在奥术台刻写法术。"), 20 },
    nw_beast_core = { T("巨兽核心"), T("季节巨兽留下的核心，用于精良法杖和三重施法卡。"), 10 },
    nw_overlord_core = { T("霸主核心"), T("强大首领的核心，可以在奥术台制作稀有法杖。"), 10 },
}
M.tiers = {T("普通"), T("精良"), T("稀有"), T("史诗")}
M.kinds = {sprout=T("萌芽"), rapid=T("速射"), reservoir=T("蓄能"), renewal=T("复苏"), weaver=T("编织"), chaos=T("混沌")}
M.recipes = {}
M.by_name = {}
local function recipe(name, product, title, ingredients, count, icon, card, tier)
    local row = {name=name, product=product, title=title, ingredients=ingredients,
        count=count or 1, icon=icon or product, card=card, tier=tier}
    table.insert(M.recipes, row)
    M.by_name[name] = row
    row.station = "nw_workbench"
    return row
end
for _, gem in ipairs({"redgem","bluegem","purplegem"}) do
    recipe("nw_dust_"..gem, "nw_dust", M.materials.nw_dust[1], {{gem,1},{"goldnugget",1}}, 4)
end
recipe("nw_blank", "nw_blank", T("空白法术卡"), {{"papyrus",1},{"charcoal",2},{"nw_dust",2}}, 2)
for _, v in ipairs({
    {"deerclops_eyeball",1,"nw_beast_core"}, {"bearger_fur",1,"nw_beast_core"},
    {"goose_feather",5,"nw_beast_core"}, {"dragon_scales",1,"nw_overlord_core"},
    {"royal_jelly",6,"nw_overlord_core"}, {"minotaurhorn",1,"nw_overlord_core"},
}) do
    local core = v[3]
    recipe("nw_extract_"..v[1], core, M.materials[core][1], {{v[1],v[2]}})
end
recipe("nw_starter", "nw_wand", T("入门法杖"), {{"twigs",4},{"goldnugget",2},{"nw_dust",4}}, 1, nil, nil, 0)
recipe("nw_roll_1", "nw_wand", T("普通随机法杖"), {{"twigs",6},{"goldnugget",4},{"nw_dust",12}}, 1, nil, nil, 1)
recipe("nw_roll_2", "nw_wand", T("精良随机法杖"), {{"boards",2},{"purplegem",1},{"nw_dust",24},{"nw_beast_core",1}}, 1, nil, nil, 2)
recipe("nw_roll_3", "nw_wand", T("稀有随机法杖"), {{"livinglog",2},{"purplegem",2},{"nw_dust",40},{"nw_overlord_core",1}}, 1, nil, nil, 3)
-- Inscription ingredients; weapon drop associations are selected separately below.
local ink = {
    gunpowder={{"gunpowder",1},{"charcoal",2}},
    gust={{"feather_robin",2},{"twigs",1}},
    spore_ball={{"spore_small",1},{"livinglog",1}},
    flint_lance={{"flint",3},{"spear",1}},
    crystal_mine={{"purplegem",1},{"gunpowder",1}},
    sleep_crystal={{"bluegem",1},{"moonrocknugget",2}},
    slime={{"slurtleslime",2},{"silk",1}},
    grow_orb={{"yellowgem",1},{"lightbulb",2}},
    heal_bolt={{"mosquitosack",2},{"butterflywings",2}},
    bog_whip={{"tentaclespike",2},{"nightmarefuel",1}},
    detonate={{"flint",2},{"gunpowder",1}},
    delay_seal={{"purplegem",1},{"papyrus",1}},
    rain_cloud={{"mosquitosack",2},{"ice",2}},
    guard_ring={{"slurtle_shellpieces",3},{"bluegem",1}},
    wild_charge={{"nitre",2},{"charcoal",1}},
    long_life={{"livinglog",1},{"cutreeds",2}},
    short_life={{"nitre",2},{"charcoal",2}},
    reverse_path={{"boomerang",1},{"goldnugget",1}},
    return_path={{"boomerang",1},{"nightmarefuel",1}},
    light_shot={{"feather_robin_winter",2},{"goldnugget",1}},
    accelerate={{"gears",1},{"goldnugget",1}},
    chill_touch={{"bluegem",1},{"ice",3}},
    wet_weak={{"mosquitosack",1},{"tentaclespots",1}},
    melee_mark={{"houndstooth",2},{"nightmarefuel",2}},
    two_way={{"boomerang",1},{"twigs",2}},
    land_hook={{"rope",2},{"houndstooth",1}},
    payload_egg={{"bird_egg",1},{"purplegem",1}},
    harmless={{"butterflywings",2},{"papyrus",1}},
    cast_four={{"nw_beast_core",1},{"gears",2}},
    hex_cast={{"nw_overlord_core",1},{"purplegem",1}},
    spore_sentry={{"spore_small",1},{"stinger",2}}, vital_ring={{"greengem",1},{"butterflywings",2}},
    heavy_shot={{"marble",2},{"goldnugget",1}}, giant_shot={{"purplegem",1},{"marble",3}}, trident_cast={{"goose_feather",2},{"houndstooth",3}},
    spark={{"nitre",1},{"flint",1}}, arrow={{"houndstooth",1},{"twigs",2}},
    heavy={{"marble",2},{"rocks",2}}, fire={{"redgem",1},{"charcoal",2}}, frost={{"bluegem",1},{"ice",3}},
    thrust={{"spear",2},{"nightmarefuel",1}}, slash={{"glasscutter",2},{"bluegem",1}}, whirl={{"axe",2},{"livinglog",1}},
    sine={{"tentaclespots",1},{"cutreeds",2}}, spiral={{"slurtle_shellpieces",1},{"slurtleslime",2}},
    precision={{"feather_crow",1},{"flint",1}}, homing={{"batwing",2},{"purplegem",1}},
    homing_rotate={{"feather_crow",2},{"goldnugget",2}},
    bounce={{"slurtleslime",2},{"rocks",2}}, orbit={{"moonrocknugget",2},{"butterflywings",2}},
    speed_up={{"walrus_tusk",1}}, speed_down={{"silk",3}}, damage_up={{"houndstooth",2},{"nightmarefuel",1}},
    pierce={{"tentaclespike",1},{"flint",2}}, explosion={{"gunpowder",1},{"redgem",1}},
    chain={{"purplegem",1},{"lightninggoathorn",1}}, knockback={{"marble",1},{"beefalowool",3}},
    leech={{"greengem",1},{"mosquitosack",2}}, light={{"yellowgem",1},{"lightbulb",2}},
    mana_reduce={{"purplegem",1},{"nightmarefuel",2}}, recharge_down={{"gears",1},{"orangegem",1}},
    double={{"silk",4},{"nightmarefuel",1}}, triple={{"gears",1},{"nightmarefuel",2},{"nw_beast_core",1}},
    repeat_2={{"nw_beast_core",1},{"purplegem",2},{"gears",2}},
}
local arsenal=require("nw/arsenal")
local selectors={}
for _,c in ipairs(arsenal.cards) do
    if c.source_weapon then
        if c.source_weapon~="propsign" and not require("nw/engraved_spells").retired[c.id] then ink[c.id]={{c.source_weapon,2},{"nightmarefuel",1}} end
    elseif c.select_target then
        selectors[c.id]=true
        ink[c.id]={{"papyrus",1},{"nightmarefuel",1}}
    end
end
for id,note in pairs(arsenal.notes) do
    ink[id]=note.instrument=="kantele" and {{"slurtle_shellpieces",2},{"cutreeds",3}} or {{"cutreeds",3},{"goldnugget",1}}
end
M.by_material={}
local weapons=require("nw/arsenal").weapons
local original_weapons={thrust="spear",slash="glasscutter",whirl="axe"}
local signature_material={edge_batbat="batwing",edge_nightstick="lightninggoathorn"}
local function associate(material,id)
    local ids=M.by_material[material] or {}
    M.by_material[material]=ids
    ids[#ids+1]=id
end
local function inscribe(id, ingredients, suffix)
    local inputs={{"nw_blank",1}}
    local weapon=weapons[id] and weapons[id].source_weapon or original_weapons[id]
    for _,v in ipairs(ingredients) do
        inputs[#inputs+1]=v
        if not selectors[id] and not arsenal.notes[id] and (not weapon or v[1]==weapon) then associate(v[1],id) end
    end
    if signature_material[id] then associate(signature_material[id],id) end
    local row=recipe("nw_inscribe_"..id..(suffix or ""), "nw_spellcard", Cards.names[id],
        inputs,1,"nw_spell_"..id,id)
    if weapon then row.station="nw_engraver" end
end
for _, id in ipairs(Cards.order) do
    if ink[id] then inscribe(id,ink[id]) end
    if id=="scatter" then
        for i, feather in ipairs({"feather_crow","feather_robin","feather_robin_winter","feather_canary"}) do
            inscribe(id,{{feather,2}},i==1 and "" or "_"..feather)
        end
    end
end
-- AddRecipe2 and craftingstation:LearnItem consume this same ordered list.
-- Keep display categories separate from the saved/networked card codes.
local definitions=require("nw/definitions")
-- Display order for the engraving station only.
local engraving_groups={
    { -- 原创招式
        "thrust", "slash", "whirl",
    },
    { -- 工具1
        "pickaxe", "shovel", "hammer", "farm_hoe", "pitchfork", "goldenaxe", "goldenpickaxe",
        "goldenshovel", "golden_farm_hoe", "goldenpitchfork", "fumaroleaxe", "fumarolepickaxe",
        "fumaroleshovel", "fumarolehammer", "fumarole_farm_hoe", "moonglassaxe",
        "multitool_axe_pickaxe", "voidcloth_scythe", "shadow_battleaxe", "pickaxe_lunarplant",
        "shovel_lunarplant",
    },
    { -- 工具2
        "torch", "bugnet", "thulecitebugnet", "compass", "minifan", "cane", "orangestaff",
        "yellowstaff", "opalstaff", "witchbroom", "fence_rotator", "wateringcan", "premiumwateringcan", "fishingrod",
        "oceanfishingrod", "saddlehorn", "brush", "chum", "oar", "oar_driftwood", "lighter",
        "lucy", "merm_tool", "merm_tool_upgraded",
    },
    { -- 武器
        "spear_wathgrithr", "spear_wathgrithr_lightning", "spear_wathgrithr_lightning_charged",
        "wathgrithr_shield", "dumbbell", "dumbbell_golden", "dumbbell_marble", "dumbbell_gem",
        "dumbbell_heat", "dumbbell_redgem", "dumbbell_bluegem", "wortox_nabbag",
        "pocketwatch_weapon", "hambat", "batbat", "nightstick", "whip", "tentaclespike",
        "nightsword", "trident", "ruins_bat", "sword_lunarplant", "houndstooth_blowpipe",
        "gestalt_cage", "voidcloth_boomerang", "firestaff", "icestaff", "staff_lunarplant", "staff_tornado",
    },
    { -- 神龛
        "handpillow_petals", "handpillow_kelp", "handpillow_beefalowool", "handpillow_steelwool",
        "yoth_knightstick",
    },
    { -- 其他
        "bullkelp_root", "carnivalgame_golfclub", "yoth_lance", "cutless", "oar_monkey",
        "vault_compass", "rabbitkingspear", "shieldofterror", "malbatross_beak", "king_cane",
        "queen_torch",
    },
}
local engraving_order={}
local engraving_group={}
local rank=0
for i,group in ipairs(engraving_groups) do
    for _,key in ipairs(group) do
        rank=rank+1
        engraving_order[key]=rank
        engraving_group[key]=10+i
    end
end
local bench={supplies=0,projectile=1,field=2,path=3,effect=4,wand=5,multicast=6,target=7,note=8,other=9}
local bench_override={
    chain=bench.projectile, explosion=bench.effect, guard_ring=bench.other,
    reverse_path=bench.path, return_path=bench.path, homing_rotate=bench.path,
    mana_reduce=bench.wand, recharge_down=bench.wand, wild_charge=bench.wand,
}
local function bench_group(card)
    if not card then return bench.supplies end
    if bench_override[card] then return bench_override[card] end
    local d=definitions.spells[card]
    if arsenal.notes[card] then return bench.note end
    if d.select_target then return bench.target end
    if d.kind=="projectile" then return bench.projectile end
    if d.kind=="field" then return bench.field end
    if definitions.trajectory[card] then return bench.path end
    if d.kind=="multicast" or d.copies then return bench.multicast end
    if d.kind=="modifier" then return bench.effect end
    return bench.other
end
for index,row in ipairs(M.recipes) do
    row.order=index
    if row.station=="nw_engraver" then
        local weapon=weapons[row.card]
        local key=weapon and weapon.source_weapon or row.card
        row.group=engraving_group[key]
        row.order=assert(engraving_order[key],"Missing engraving display order: "..key)
    else
        row.group=bench_group(row.card)
    end
end
-- Place the detonator immediately after the second crystal, preserving all other ties.
M.by_name.nw_inscribe_detonate.order=M.by_name.nw_inscribe_sleep_crystal.order+.5
table.sort(M.recipes,function(a,b)
    if a.group~=b.group then return a.group<b.group end
    if a.group==bench.note then
        local x,y=arsenal.notes[a.card],arsenal.notes[b.card]
        if x.instrument~=y.instrument then return x.instrument=="kantele" end
        if x.pitch~=y.pitch then return x.pitch<y.pitch end
    end
    return a.order<b.order
end)
-- Both the registration order and the station's learned list include these
-- dividers. Keep them out of the gameplay recipe catalog.
local headings={
    [bench.projectile]={"projectile",T("远程投射物")}, [bench.field]={"field",T("静态投射物")},
    [bench.path]={"path",T("弹道修正")}, [bench.effect]={"effect",T("法术效果修正")},
    [bench.wand]={"wand",T("法杖修正")}, [bench.multicast]={"multicast",T("多重释放")},
    [bench.target]={"target",T("目标选择")}, [bench.note]={"note",T("音符法术")}, [bench.other]={"other",T("其他")},
    [12]={"tools1",T("工具一")}, [13]={"tools2",T("工具二")}, [14]={"weapons",T("武器")},
    [15]={"shrine",T("神龛")}, [16]={"other",T("其他")},
}
-- The field guide also lists cards without recipes, under the same headings.
function M.card_section(card)
    local recipe=M.by_name["nw_inscribe_"..card]
    if weapons[card] and definitions.spells[card].kind=="field" then return bench.field,headings[bench.field][2] end
    if weapons[card] and definitions.spells[card].kind=="projectile" then return bench.projectile,headings[bench.projectile][2] end
    local group=recipe and recipe.group or (definitions.spells[card].kind=="melee" and 16 or bench_group(card))
    return group,group==11 and T("原创招式") or headings[group][2]
end
M.menu_entries={}
local last_group
for _,row in ipairs(M.recipes) do
    local heading=headings[row.group]
    if heading and row.group~=last_group then
        table.insert(M.menu_entries,{name=row.station.."_section_"..heading[1],station=row.station,
            title=heading[2],section_icon=heading[1]})
    end
    table.insert(M.menu_entries,row)
    last_group=row.group
end
return M
