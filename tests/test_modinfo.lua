-- Match ModIndex:InitializeModInfo: no fallback to Lua's global libraries.
-- A normal require/dofile misses startup failures from ipairs/tostring calls.
local locales={"zh","zh_tw","chs","cht","en","fr"}
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
    assert(#rows==21 and rows[1].name=="language" and rows[2].name=="starting_wand")
    assert(rows[3].name=="crafting_class_filter" and rows[3].default==true)
    assert(rows[3].options[1].data==true and rows[3].options[2].data==false)
    assert(env.description:find((chinese and "版本：" or "Version: ")..env.version,1,true))
    assert(env.description:match("%d%d%d%d%-%d%d%-%d%d"))
    assert(rows[4].name==(chinese and "掉落率" or "Drop rates"))
    assert(rows[7].name==(chinese and "性能优化" or "Performance"))
    assert(rows[19].name==(chinese and "开发者设置" or "Developer settings"))
    assert(rows[20].name=="developer_options" and rows[21].name=="development_smoke")
    local seen={}
    for _,row in ipairs(rows) do
        assert(not seen[row.name]);seen[row.name]=true
        local found=false
        for _,option in ipairs(row.options) do if option.data==row.default then found=true end end
        assert(found,"missing default: "..row.name)
    end
    for _,index in ipairs({5,6}) do
        local row=rows[index]
        assert(row.name==(index==5 and "card_drop_rate" or "wand_drop_rate") and row.default==1)
        local rates={0,.5,1,2,3,5,10}
        assert(#row.options==#rates)
        for n,rate in ipairs(rates) do assert(row.options[n].data==rate) end
    end
    for n=8,18 do assert(rows[n].default==false or rows[n].default==0) end
end
print("modinfo: restricted startup sandbox, seven locales, section order, rate options and defaults")
