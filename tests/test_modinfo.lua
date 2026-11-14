-- Match ModIndex:InitializeModInfo: no fallback to Lua's global libraries.
-- A normal require/dofile misses startup failures from ipairs/tostring calls.
local locales={"zh","zh_tw","chs","cht","en","fr"}
local no_hover={card_drop_rate=true,wand_drop_rate=true,disable_crafting_filter=true,disable_dark_fog=true}
for i=1,#locales+1 do
    local locale=locales[i]
    local env={folder_name="nw_weave_dev",locale=locale,
        ChooseTranslationTable=function(t) return t[locale] or t[1] end}
    assert(env.ipairs==nil and env.tostring==nil)
    local fn=assert(loadfile("mod/modinfo.lua"))
    setfenv(fn,env)
    fn()
    local chinese=i<=4
    local icon_name=chinese and "modicon" or "modicon_en"
    assert(env.author=="yuejian" and env.icon_atlas==icon_name..".xml" and env.icon==icon_name..".tex")
    for _,extension in ipairs({".xml", ".tex"}) do
        local file=assert(io.open("mod/"..icon_name..extension,"rb"))
        file:close()
    end
    local rows=env.configuration_options
    assert(#rows==23 and rows[1].name=="language" and rows[2].name=="base_damage_multiplier" and rows[3].name=="world_difficulty")
    for _,row in ipairs(rows) do
        if no_hover[row.name] then assert(row.hover==nil,"removed setting hover: "..row.name) end
        for _,option in ipairs(row.options) do
            if row.label and not no_hover[row.name] then
                assert(type(option.hover)=="string" and option.hover:match("%S"),"missing option hover: "..row.name)
            else
                assert(option.hover==nil,"unexpected option hover: "..row.name)
            end
        end
    end
    local damage=table.remove(rows,2)
    assert(damage.label==(chinese and "基础伤害倍率" or "Base damage multiplier") and damage.default==1)
    local damage_multipliers={0.5,0.75,1,1.25,1.5}
    assert(#damage.options==#damage_multipliers)
    for n,value in ipairs(damage_multipliers) do assert(damage.options[n].data==value) end
    local difficulty=table.remove(rows,2)
    assert(difficulty.default=="fun" and #difficulty.options==3 and difficulty.options[1].data=="fun" and difficulty.options[2].data=="balanced")
    local loot=difficulty.options[3]
    assert(loot.data=="balanced_loot" and loot.description==(chinese and "平衡·掉落限定" or "Balanced: Loot Only"))
    assert(loot.hover:find(chinese and "5倍" or "5x",1,true))
    assert(loot.hover:find(chinese and "禁用法术卡配方" or "disable spell card recipes",1,true))
    assert(rows[2].name=="starting_wand")
    assert(rows[6].name==(chinese and "兼容性" or "Compatibility"))
    assert(rows[7].name=="disable_crafting_filter" and rows[7].default==false)
    assert(rows[7].label==(chinese and "禁用制作栏分类与标签" or "Disable crafting classes and tags"))
    assert(rows[8].name=="disable_dark_fog" and rows[8].default==false)
    for n=7,8 do assert(rows[n].options[1].data==false and rows[n].options[2].data==true) end
    assert(env.description:find((chinese and "版本：" or "Version: ")..env.version,1,true))
    assert(env.description:match("%d%d%d%d%-%d%d%-%d%d"))
    assert(rows[3].name==(chinese and "掉落率" or "Drop rates"))
    assert(rows[9].name==(chinese and "性能优化" or "Performance"))
    assert(rows[19].name==(chinese and "开发者设置" or "Developer settings"))
    assert(rows[20].name=="developer_options" and rows[21].name=="development_smoke")
    local seen={}
    for _,row in ipairs(rows) do
        assert(not seen[row.name]);seen[row.name]=true
        local found=false
        for _,option in ipairs(row.options) do if option.data==row.default then found=true end end
        assert(found,"missing default: "..row.name)
    end
    for _,index in ipairs({4,5}) do
        local row=rows[index]
        assert(row.name==(index==4 and "card_drop_rate" or "wand_drop_rate") and row.default==1)
        local rates={0,.5,1,2,3,5,10}
        assert(#row.options==#rates)
        for n,rate in ipairs(rates) do assert(row.options[n].data==rate) end
    end
    local defaults={client_trail_limit=1700,limit_projectiles=600,limit_fields=200,limit_permanent_fields=100,limit_range=0,limit_depth=5,boundary_cleanup=true,permanent_motion_cleanup=true,sync_performance=true}
    for n=10,18 do assert(rows[n].default==defaults[rows[n].name]) end
end
print("modinfo: restricted startup sandbox, seven locales, section order, bilingual option hovers, difficulty modes, rate options and defaults")
