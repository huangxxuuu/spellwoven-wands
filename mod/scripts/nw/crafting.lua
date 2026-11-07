local T=require("nw/locale").t
local Rules = require("nw/acquisition")
local Visual = require("nw/visual")
local M = {}
local function at_station(recipe, player, _, rotation, station)
    local row=Rules.by_name[recipe.name]
    local required=row and row.station or "nw_workbench"
    return station and station:IsValid() and station.prefab == required
        and station.components.prototyper:CanUsePrototyper(player) or false
end
function M.install(env)
    STRINGS.NAMES.NW_SPELL_PUNCHINGBAG=T("法术测试拳击袋")
    STRINGS.RECIPE_DESC.NW_SPELL_PUNCHINGBAG=T("统计连续法术伤害，间隔达到 1 秒后重新计数。")
    STRINGS.CHARACTERS.GENERIC.DESCRIBE.NW_SPELL_PUNCHINGBAG=T("头顶的火花标记着这一轮法术实验。")
    env.AddRecipe2("nw_spell_punchingbag",{Ingredient("cutgrass",3),Ingredient("boards",1)},
        TECH.SCIENCE_ONE,{placer="nw_spell_punchingbag_placer",min_spacing=2,
            atlas=GetInventoryItemAtlas("punchingbag.tex"),image="punchingbag.tex"},{"COMBAT","MAGIC"})
    for name, spec in pairs(Rules.materials) do
        env.RegisterInventoryItemAtlas(Rules.atlas, name..".tex")
        STRINGS.NAMES[name:upper()] = spec[1]
        STRINGS.CHARACTERS.GENERIC.DESCRIBE[name:upper()] = spec[2]
    end
    env.RegisterInventoryItemAtlas(Rules.atlas, "nw_workbench.tex")
    STRINGS.RECIPE_DESC.NW_WORKBENCH = T("研磨宝石，制作法杖，刻写和更换法术卡。")
    env.AddPrototyperDef("nw_workbench", {icon_atlas=Rules.atlas, icon_image="nw_workbench_station.tex",
        is_crafting_station=true, action_str="USE", filter_text=T("奥术台")})
    env.RegisterInventoryItemAtlas(Rules.station_atlas,"nw_engraver.tex")
    env.RegisterInventoryItemAtlas(Rules.station_atlas,"nw_disassembler.tex")
    env.AddPrototyperDef("nw_engraver",{icon_atlas=Rules.station_atlas,icon_image="nw_engraver_station.tex",
        is_crafting_station=true,action_str="USE",filter_text=T("武器刻印台")})
    env.AddRecipe2("nw_engraver",{Ingredient("boards",2),Ingredient("cutstone",2),Ingredient("purplegem",1)},
        TECH.SCIENCE_TWO,{placer="nw_engraver_placer",atlas=Rules.station_atlas,image="nw_engraver.tex"},{"PROTOTYPERS","MAGIC"})
    env.AddRecipe2("nw_workbench", {Ingredient("boards",2), Ingredient("cutstone",2),
        Ingredient("goldnugget",4), Ingredient("purplegem",2)}, TECH.SCIENCE_TWO,
        {placer="nw_workbench_placer", atlas=Rules.atlas,image="nw_workbench.tex"}, {"PROTOTYPERS","MAGIC"})
    env.AddRecipe2("nw_disassembler",{Ingredient("cutstone",2),Ingredient("purplegem",1),
        Ingredient("nw_dust",4,Rules.atlas)},TECH.SCIENCE_TWO,{placer="nw_disassembler_placer",
        image="nw_disassembler.tex",atlas=Rules.station_atlas},{"PROTOTYPERS","MAGIC"})
    local function register_product(row)
        local ingredients = {}
        for i, v in ipairs(row.ingredients) do
            local c=row.card and require("nw/arsenal").weapons[row.card]
            local image=c and c.source_weapon==v[1] and c.source_image or nil
            ingredients[i] = Ingredient(v[1], v[2], Rules.materials[v[1]] and Rules.atlas or nil,nil,image)
        end
        local key = row.name:upper()
        STRINGS.NAMES[key] = row.title
        STRINGS.RECIPE_DESC[key] = row.card and require("nw/spell_info").tooltip(row.card)
            or row.tier == 0 and T("两格，非乱序，内置一张火花弹。")
            or row.tier and T("随机属性，空槽可自行装卡。")
            or Rules.materials[row.product][2]
        local image,atlas=row.icon,row.card and Rules.card_atlas or Rules.atlas
        if row.tier then
            local code=Visual.recipe_code(row.tier)
            image,atlas=Visual.icon(code),Visual.atlas(code)
        end
        env.AddRecipe2(row.name, ingredients, TECH.LOST, {product=row.product, nounlock=true,
            station_tag=row.station, numtogive=row.count, nameoverride=row.name, description=row.name, canbuild=at_station,
            image=image..".tex", atlas=atlas,
            layeredimagefn=row.tier and require("nw/wand_icon").recipe(row.tier) or nil,
            no_deconstruction=true}, {})
    end
    for _,row in ipairs(Rules.recipes) do register_product(row) end
end
return M
