local C=require("nw/constants/acquisition")
local Copy=require("nw/util").copy
local T=require("nw/locale").t
local Cards = require("nw/cards")
local M = {}
M.atlas = "images/inventoryimages/nw_supplies.xml"
M.station_atlas = "images/inventoryimages/nw_stations.xml"
M.card_atlas = "images/inventoryimages/nw_icons.xml"
M.materials = {
    nw_dust = { T("奥术粉尘"), T("宝石中沉睡的魔力，研磨后凝成晶粉；吸纳游离魔力的生灵陨落时，也会留下这样的余烬。可用于制杖与浸染空白卡。"), C.material_stacks.nw_dust },
    nw_blank = { T("空白法术卡"), T("用粉尘浸过的莎草纸，可以在奥术台刻写法术。"), C.material_stacks.nw_blank },
    nw_beast_core = { T("巨兽核心"), T("季节巨兽留下的核心，用于精良法杖和三重施法卡。"), C.material_stacks.nw_beast_core },
    nw_overlord_core = { T("霸主核心"), T("强大首领的核心，可以在奥术台制作稀有法杖。"), C.material_stacks.nw_overlord_core },
}
M.tiers = {T("普通"), T("精良"), T("稀有"), T("史诗")}
M.kinds = {sprout=T("萌芽"), rapid=T("速射"), reservoir=T("蓄能"), renewal=T("复苏"), weaver=T("编织"), chaos=T("混沌")}
M.recipes = {}
M.by_name = {}
local function recipe(name, product, title, ingredients, count, icon, card, tier)
    local row = {name=name, product=product, title=title, ingredients=ingredients,
        count=count or C.recipes.default_count, icon=icon or product, card=card, tier=tier}
    table.insert(M.recipes, row)
    M.by_name[name] = row
    row.station = "nw_workbench"
    return row
end
for _, gem in ipairs({"redgem","bluegem","purplegem"}) do
    recipe("nw_dust_"..gem, "nw_dust", M.materials.nw_dust[1], {{gem,C.recipes.dust.gem_count},Copy(C.recipes.dust.ingredients[1])}, C.recipes.dust.count)
end
recipe("nw_blank", "nw_blank", T("空白法术卡"), Copy(C.recipes.blank.ingredients), C.recipes.blank.count)
recipe("nw_dustbox", "nw_dustbox", T("粉尘收纳盒"), Copy(C.recipes.dustbox.ingredients)).description =
    T("随身携带的一格收纳盒，只收纳奥术粉尘，盒内可无限堆叠。")
for _, v in ipairs(C.recipes.core_extraction) do
    local core = v[3]
    recipe("nw_extract_"..v[1], core, M.materials[core][1], {{v[1],v[2]}})
end
recipe("nw_starter", "nw_wand", T("入门法杖"), Copy(C.recipes.starter.ingredients), C.recipes.starter.count, nil, nil, C.recipes.starter.tier)
recipe("nw_roll_1", "nw_wand", T("普通随机法杖"), Copy(C.recipes.roll_1.ingredients), C.recipes.roll_1.count, nil, nil, C.recipes.roll_1.tier)
recipe("nw_roll_2", "nw_wand", T("精良随机法杖"), Copy(C.recipes.roll_2.ingredients), C.recipes.roll_2.count, nil, nil, C.recipes.roll_2.tier)
recipe("nw_roll_3", "nw_wand", T("稀有随机法杖"), Copy(C.recipes.roll_3.ingredients), C.recipes.roll_3.count, nil, nil, C.recipes.roll_3.tier)
local ink = Copy(C.ink)
local arsenal=require("nw/arsenal")
local engraving_ink = C.engraving_ink
local selectors={}
for _,c in ipairs(arsenal.cards) do
    if c.source_weapon then
        if c.source_weapon~="propsign" and not require("nw/engraved_spells").retired[c.id] then
            ink[c.id]={{c.source_weapon,C.recipes.engraving_weapon_count}}
            for _,v in ipairs(engraving_ink[c.source_weapon] or C.recipes.engraving_fallback) do
                ink[c.id][#ink[c.id]+1]={v[1],v[2]}
            end
        end
    elseif c.select_target then
        selectors[c.id]=true
        ink[c.id]=Copy(C.recipes.selector)
    end
end
for id,note in pairs(arsenal.notes) do
    if not arsenal.legacy_notes[id] then
        ink[id]=Copy(note.instrument=="kantele" and C.recipes.kantele or C.recipes.ocarina)
    end
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
    local inputs=Copy(C.recipes.inscription_base)
    local weapon=weapons[id] and weapons[id].source_weapon or original_weapons[id]
    for _,v in ipairs(ingredients) do
        inputs[#inputs+1]=v
        if not selectors[id] and not arsenal.notes[id] and not require("nw/pitch_modifiers").by_id[id] and (not weapon or v[1]==weapon) then associate(v[1],id) end
    end
    if signature_material[id] then associate(signature_material[id],id) end
    local row=recipe("nw_inscribe_"..id..(suffix or ""), "nw_spellcard", Cards.names[id],
        inputs,C.recipes.inscription_count,"nw_spell_"..id,id)
    if weapon then row.station="nw_engraver" end
end
for _, id in ipairs(Cards.order) do
    if ink[id] then inscribe(id,ink[id]) end
    if id=="scatter" then
        for i, feather in ipairs({"feather_crow","feather_robin","feather_robin_winter","feather_canary"}) do
            inscribe(id,{{feather,C.recipes.scatter_feather_count},Copy(C.recipes.scatter_wool)},i==1 and "" or "_"..feather)
        end
    end
end
local definitions=require("nw/definitions")
local engraving_groups=C.engraving_groups
local engraving_order={}
local engraving_group={}
local rank=0
for i,group in ipairs(engraving_groups) do
    for _,key in ipairs(group) do
        rank=rank+1
        engraving_order[key]=rank
        engraving_group[key]=C.engraving_group_offset+i
    end
end
local bench=C.bench
local bench_override={
    chain=bench.projectile, explosion=bench.effect, guard_ring=bench.other,
    reverse_path=bench.path, return_path=bench.path, homing_rotate=bench.path,
    mana_reduce=bench.wand, recharge_down=bench.wand, wild_charge=bench.wand,
}
local function bench_group(card)
    if not card then return bench.supplies end
    if bench_override[card] then return bench_override[card] end
    local d=definitions.spells[card]
    if arsenal.notes[card] or d.pitch_shift then return bench.note end
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
M.by_name.nw_inscribe_detonate.order=M.by_name.nw_inscribe_sleep_crystal.order+C.detonate_order_offset
table.sort(M.recipes,function(a,b)
    if a.group~=b.group then return a.group<b.group end
    if a.group==bench.note then
        local x,y=arsenal.notes[a.card],arsenal.notes[b.card]
        if x and y then
            if x.instrument~=y.instrument then return x.instrument=="kantele" end
            if x.pitch~=y.pitch then return x.pitch<y.pitch end
        elseif x or y then return x~=nil end
    end
    return a.order<b.order
end)
local headings={
    [bench.projectile]={"projectile",T("远程投射物")}, [bench.field]={"field",T("静态投射物")},
    [bench.path]={"path",T("弹道修正")}, [bench.effect]={"effect",T("法术效果修正")},
    [bench.wand]={"wand",T("法杖修正")}, [bench.multicast]={"multicast",T("多重释放")},
    [bench.target]={"target",T("目标选择")}, [bench.note]={"note",T("音符法术")}, [bench.other]={"other",T("其他")},
    [C.engraving_sections.tools1]={"tools1",T("工具一")}, [C.engraving_sections.tools2]={"tools2",T("工具二")}, [C.engraving_sections.weapons]={"weapons",T("武器")},
    [C.engraving_sections.shrine]={"shrine",T("神龛")}, [C.engraving_sections.other]={"other",T("其他")},
}
function M.card_section(card)
    local recipe=M.by_name["nw_inscribe_"..card]
    if weapons[card] and definitions.spells[card].kind=="field" then return bench.field,headings[bench.field][2] end
    if weapons[card] and definitions.spells[card].kind=="projectile" then return bench.projectile,headings[bench.projectile][2] end
    local group=recipe and recipe.group or (definitions.spells[card].kind=="melee" and C.engraving_sections.other or bench_group(card))
    return group,group==C.engraving_sections.original and T("原创招式") or headings[group][2]
end
M.menu_entries=M.recipes
return M
