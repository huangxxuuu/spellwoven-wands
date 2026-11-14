local M={}
function M.run()
    local Balance=require("nw/balance")
    local Rules=require("nw/acquisition")
    local Filter=require("nw/crafting_filter")
    local oldmode=Balance.mode
    local x,z=0,0
    for _,e in pairs(Ents) do
        if e:HasTag("multiplayer_portal") then x,_,z=e.Transform:GetWorldPosition();break end
    end
    local player=assert(SpawnPrefab("wilson"))
    local builder,inv=player.components.builder,player.components.inventory
    local stations={}
    Balance.configure("balanced")
    for i,prefab in ipairs({"nw_workbench","nw_engraver"}) do
        local inst=assert(SpawnPrefab(prefab))
        inst.Transform:SetPosition(x+i*24,0,z+24)
        stations[prefab]=inst
    end
    local saved={}
    for prefab,inst in pairs(stations) do
        assert(inst.components.craftingstation.nosave)
        saved[prefab]=inst:GetSaveRecord()
        assert(not (saved[prefab].data and saved[prefab].data.craftingstation),"station catalogue persisted")
    end
    local built
    player:ListenForEvent("builditem",function(_,data) built=data.item end)
    local function clear()
        for _,item in ipairs(inv:FindItems(function() return true end)) do item:Remove() end
    end
    local function supply(row)
        clear()
        for _,v in ipairs(row.ingredients) do
            local remaining=v[2]
            while remaining>0 do
                local item=assert(SpawnPrefab(v[1]),"missing ingredient "..v[1])
                local count=item.components.stackable and math.min(remaining,item.components.stackable.maxsize) or 1
                if item.components.stackable then item.components.stackable:SetStackSize(count) end
                assert(inv:GiveItem(item),"cannot give "..v[1])
                remaining=remaining-count
            end
        end
        assert(builder:HasIngredients(AllRecipes[row.name]),"fixture lacks ingredients: "..row.name)
    end
    local function select_station(inst)
        local sx,_,sz=inst.Transform:GetWorldPosition()
        player.Transform:SetPosition(sx+1,0,sz)
        builder:EvaluateTechTrees()
        assert(builder.current_prototyper==inst,"station selection")
        assert(not builder.freebuildmode,"freebuild would bypass the ingredient fixture")
    end
    local function catalogue(inst,loot)
        select_station(inst)
        local learned=inst.components.craftingstation:GetItems()
        local n=0
        for _,row in ipairs(Rules.menu_entries) do
            if row.station==inst.prefab then
                local enabled=not (loot and (row.card or row.product=="nw_spellcard"))
                if enabled then n=n+1;assert(learned[n]==row.name,"catalogue order "..row.name) end
                assert(not not builder:KnowsRecipe(AllRecipes[row.name])==enabled,"builder catalogue "..row.name)
            end
        end
        assert(#learned==n,"extra station recipes")
        if loot then
            assert(#Filter.class_options(inst.prefab)==1 and #Filter.tags(inst.prefab,"all")==0)
        else
            assert(#Filter.class_options(inst.prefab)>1 and #Filter.tags(inst.prefab,"all")>0)
        end
    end
    local denied,crafted=0,0
    Balance.configure("balanced_loot")
    assert(Balance.is_balanced() and require("nw/definitions").spells.mana_reduce.mana==-20)
    for prefab,record in pairs(saved) do
        stations[prefab]:Remove()
        stations[prefab]=assert(SpawnSaveRecord(record))
        catalogue(stations[prefab],true)
    end
    for _,row in ipairs(Rules.recipes) do
        local inst=stations[row.station]
        select_station(inst)
        supply(row)
        built=nil
        if row.card or row.product=="nw_spellcard" then
            inst.components.craftingstation:LearnItem(row.name,row.name)
            builder:EvaluateTechTrees()
            assert(builder:KnowsRecipe(AllRecipes[row.name]))
            assert(not builder:DoBuild(row.name) and built==nil,"forced card build succeeded: "..row.name)
            for _,v in ipairs(row.ingredients) do
                assert(inv:Has(v[1],v[2]),"blocked build spent ingredient: "..row.name.."/"..v[1])
            end
            denied=denied+1
        else
            assert(builder:DoBuild(row.name) and built and built.prefab==row.product,"allowed build failed: "..row.name)
            if row.tier then
                local data=built.components.nw_wand.data
                assert(data.source==row.name)
                if row.tier==0 then assert(data.cards[1] and data.cards[1].spell_id=="spark","starter lost spark")
                else for _,card in ipairs(data.cards) do assert(card==false,"random crafted wand gained a card") end end
            end
            crafted=crafted+1
            built:Remove()
        end
    end
    assert(denied==154 and crafted==15,"recipe coverage changed")
    assert(require("nw/wand_factory").build(0,"starter",nil,42).cards[1].spell_id=="spark","spawn gift lost spark")
    for _,mode in ipairs({"balanced","fun","balanced_loot"}) do
        Balance.configure(mode)
        for prefab,inst in pairs(stations) do
            local record=inst:GetSaveRecord()
            inst:Remove()
            stations[prefab]=assert(SpawnSaveRecord(record))
        end
        for _,inst in pairs(stations) do catalogue(inst,mode=="balanced_loot") end
        if mode~="balanced_loot" then
            local row=Rules.by_name.nw_inscribe_spark
            select_station(stations[row.station]);supply(row);built=nil
            assert(builder:DoBuild(row.name) and built and built.spell_id=="spark","restored card crafting failed")
            built:Remove()
        end
    end
    clear()
    for _,inst in pairs(stations) do inst:Remove() end
    player:Remove()
    Balance.configure(oldmode)
    print("NW_LOOT_ONLY_PASS: 154 forbidden recipes reject forced DoBuild without consumption; 15 allowed recipes crafted including blank; starter spark retained; native station/builder catalogue and old-record rebuild")
end
return M
