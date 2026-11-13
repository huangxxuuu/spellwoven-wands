-- Direct recipe gates and filter options; native station/builder is covered by smoke_loot_only.
local Balance=require("nw/balance")
local Rules=require("nw/acquisition")
local Craft=require("nw/crafting")
local Filter=require("nw/crafting_filter")
local Factory=require("nw/wand_factory")
local registered={}
STRINGS={NAMES={},RECIPE_DESC={},CHARACTERS={GENERIC={DESCRIBE={}}}}
TECH={SCIENCE_ONE={},SCIENCE_TWO={},LOST={}}
Ingredient=function(name,amount) return {type=name,amount=amount} end
GetInventoryItemAtlas=function() return "test.xml" end
local old_info=package.loaded["nw/spell_info"]
local old_icon=package.loaded["nw/wand_icon"]
package.loaded["nw/spell_info"]={tooltip=function() return "card" end}
package.loaded["nw/wand_icon"]={recipe=function() return function() end end}
Craft.install({RegisterInventoryItemAtlas=function() end,AddPrototyperDef=function() end,
    AddRecipe2=function(name,ingredients,tech,config) config.name=name;registered[name]=config end})
package.loaded["nw/spell_info"]=old_info
package.loaded["nw/wand_icon"]=old_icon
local function station(prefab)
    return {prefab=prefab,IsValid=function() return true end,
        components={prototyper={CanUsePrototyper=function() return true end}}}
end
local function empty(data)
    assert(#data.cards==data.stats.capacity)
    for _,card in ipairs(data.cards) do assert(card==false,"crafted wand leaked a card") end
end
for _,mode in ipairs({"balanced_loot","balanced","fun","balanced_loot"}) do
    Balance.configure(mode)
    local loot=mode=="balanced_loot"
    assert(Balance.is_loot_only()==loot and Balance.is_balanced()==(mode~="fun"))
    assert(require("nw/definitions").spells.mana_reduce.mana==(mode=="fun" and -30 or -20))
    local counts={cards=0,blank=0,wands=0,other=0}
    for _,prefab in ipairs({"nw_workbench","nw_engraver"}) do
        local inst=station(prefab)
        for _,row in ipairs(Rules.menu_entries) do
            if row.station==prefab then
                local blocked=row.card~=nil or row.product=="nw_spellcard"
                local enabled=not (loot and blocked)
                assert(Craft.recipe_enabled(row)==enabled,row.name)
                assert(not not registered[row.name].canbuild(registered[row.name],{},nil,0,inst)==enabled,
                    "live server gate: "..row.name)
                local wrong=station(prefab=="nw_workbench" and "nw_engraver" or "nw_workbench")
                assert(not registered[row.name].canbuild(registered[row.name],{},nil,0,wrong))
                local kind=row.card and "cards" or row.product=="nw_blank" and "blank" or row.tier and "wands" or "other"
                counts[kind]=counts[kind]+1
            end
        end
        if loot then
            local options=Filter.class_options(prefab)
            assert(#options==1 and options[1].data=="all")
            assert(#Filter.tags(prefab,"all")==0)
        else
            assert(#Filter.class_options(prefab)>1 and #Filter.tags(prefab,"all")>0)
        end
    end
    assert(counts.cards==154 and counts.blank==1 and counts.wands==4 and counts.other==10,
        "all cards (including note variants), blank, wands and material/core recipes must be checked")
    local crafted=Factory.build(0,"nw_starter",nil,42)
    assert(crafted.cards[1].spell_id=="spark","crafted starter must retain spark")
    assert(Factory.build(0,"starter",nil,42).cards[1].spell_id=="spark","first spawn gift lost spark")
    for tier=1,3 do empty(Factory.build(tier,"nw_roll_"..tier,nil,42)) end
end
assert(not Balance.configure("balanced_loot"),"same mode must not report a change")
Balance.configure("fun")
print("loot-only crafting: 154 card recipes, blank, four wands, materials/cores, live gates and mode restoration")
