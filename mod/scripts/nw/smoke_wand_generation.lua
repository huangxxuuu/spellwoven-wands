local M={}
local function recharge_probe()
    local wand=SpawnPrefab("nw_wand")
    local cmp=wand.components.nw_wand
    cmp:InitializePrototype()
    local recharge=wand.components.rechargeable
    local net=wand.replica.inventoryitem.classified
    assert(wand:HasTag("rechargeable") and recharge:IsCharged() and net.recharge:value()==180)
    local discharged=0
    wand:ListenForEvent("rechargechange",function(_,data)
        if data.percent<1 then discharged=discharged+1 end
    end)
    for i=1,10 do cmp:Sync() end
    assert(discharged==0 and not recharge.updating,"NW_RECHARGE: zero cooldown discharged")
    cmp.data.runtime.remaining_cast=.02;cmp.data.runtime.remaining_recharge=.04
    cmp.cool_total=.04;cmp.last_time=GetTime();cmp:Sync()
    assert(not recharge:IsCharged() and math.abs(recharge:GetTimeToCharge()-.04)<.00001)
    recharge:OnUpdate(99);recharge:LongUpdate(99)
    assert(cmp.data.runtime.remaining_recharge==.04 and not recharge.updating)

    local saved=cmp:OnSave()
    saved.wand.runtime.remaining_cast=3;saved.wand.runtime.remaining_recharge=4
    local cooling=SpawnPrefab("nw_wand")
    cooling.components.nw_wand:OnLoad(saved)
    local record=cooling:GetSaveRecord()
    assert(record.data.rechargeable==nil,"NW_RECHARGE: second cooldown save owner")
    local restored=SpawnSaveRecord(record)
    cooling:Remove()
    local copy=restored.components.rechargeable
    assert(math.abs(copy:GetTimeToCharge()-4)<.00001 and not copy.updating)
    assert(restored.replica.inventoryitem.classified.recharge:value()==0)
    copy:SetChargeTimeMod(restored,"probe",2)
    assert(copy:GetRechargeTime()==4,"NW_RECHARGE: native modifier changed display speed")
    copy:OnUpdate(99)
    copy:OnLoad({chargetime=99,charge=copy.total})
    assert(copy:GetRechargeTime()==4 and not copy:IsCharged() and not copy.updating)
    return function()
        cmp:UpdateTime()
        assert(recharge:IsCharged() and net.recharge:value()==180)
        restored.components.nw_wand:UpdateTime()
        local runtime=restored.components.nw_wand.data.runtime
        assert(runtime.remaining_recharge<4 and runtime.remaining_recharge>3)
        assert(math.abs(copy:GetTimeToCharge()-runtime.remaining_recharge)<.00001)
        wand:Remove();restored:Remove()
        print("NW_WAND_RECHARGE_PASS: native component/classified, zero/short cooldown, save/load, one clock and ignored native modifiers")
    end
end
function M.run()
    local x,z=0,0
    for _,e in pairs(Ents) do if e:HasTag("multiplayer_portal") then x,_,z=e.Transform:GetWorldPosition();break end end
    local player=SpawnPrefab("wilson");player.Transform:SetPosition(x,0,z)
    local bench=SpawnPrefab("nw_workbench");bench.Transform:SetPosition(x+1,0,z)
    local builder,inv=player.components.builder,player.components.inventory
    builder:EvaluateTechTrees()
    assert(builder.current_prototyper==bench and not builder.freebuildmode)
    local built
    player:ListenForEvent("builditem",function(_,data) built=data.item end)
    local rules=require("nw/acquisition")
    local ruleset=require("nw/wand_generation")
    local hover=require("nw/hover_data")
    local retained={}
    for _,name in ipairs({"nw_starter","nw_roll_1","nw_roll_2","nw_roll_3"}) do
        local row=rules.by_name[name]
        local recipe_layers=assert(AllRecipes[name].layeredimagefn)()
        assert(#recipe_layers==3 and recipe_layers[1].image:find("body_",1,true))
        local capacities,variants={},{}
        for n=1,60 do
            for _,ingredient in ipairs(row.ingredients) do
                local item=SpawnPrefab(ingredient[1])
                if ingredient[2]>1 then item.components.stackable:SetStackSize(ingredient[2]) end
                assert(inv:GiveItem(item))
            end
            built=nil
            assert(builder:HasIngredients(AllRecipes[name]) and builder:DoBuild(name) and built)
            local wand=built.components.nw_wand
            local d=wand.data
            assert(d.source==name and d.tier==math.max(1,row.tier) and d.starter==(row.tier==0))
            assert(built._nw_capacity:value()==d.stats.capacity)
            local shown=hover.decode(built._nw_stats:value())
            for _,key in ipairs(ruleset.keys) do
                assert(shown[key]==d.stats[key],"NW_WAND: display mismatch "..key)
            end
            assert(shown.draw_count==d.stats.draw_count and shown.shuffle==d.stats.shuffle)
            if row.tier==0 then assert(d.stats.capacity==2 and d.cards[1].spell_id=="spark")
            else
                assert(d.generator_version==3 and d.generation_budget==nil and d.budget_remaining==nil)
                assert(d.stats.draw_count<=d.stats.capacity)
                for _,key in ipairs(ruleset.keys) do
                    local lo,hi=ruleset.distribution(row.tier,d.archetype,key)
                    assert(d.stats[key]>=lo and d.stats[key]<=hi)
                end
                for _,card in ipairs(d.cards) do assert(card==false) end
            end
            local copy=SpawnSaveRecord(built:GetSaveRecord())
            assert(copy.components.nw_wand.data.wand_uid==d.wand_uid)
            assert(copy._nw_stats:value()==built._nw_stats:value())
            assert(copy._nw_cards:value()==built._nw_cards:value())
            local layers=copy.layeredinvimagefn(copy)
            local expected=require("nw/visual").icon_parts(copy._nw_look:value(),false)
            for i,layer in ipairs(layers) do assert(layer.image==expected[i]) end
            copy.components.nw_wand.data.broken=true;copy.components.nw_wand:Sync()
            assert(copy.layeredinvimagefn(copy)[3].image:find("_broken_",1,true))
            copy.components.nw_wand.data.broken=false;copy.components.nw_wand:Sync()
            assert(not copy.layeredinvimagefn(copy)[3].image:find("_broken_",1,true))
            local box=copy.components.container
            assert(box and box:OnSave()==nil)
            local installed=0
            for slot=1,d.stats.capacity do
                local card=d.cards[slot]
                local item=box:GetItemInSlot(slot)
                assert((item~=nil)==(card~=false and card~=nil))
                if card then
                    installed=installed+1
                    assert(item.spell_id==card.spell_id and item:GetCardUID()==card.card_uid)
                end
            end
            assert(box:NumItems()==installed)
            capacities[d.stats.capacity]=(capacities[d.stats.capacity] or 0)+1
            variants[built._nw_stats:value()]=true
            if n==1 then retained[#retained+1]={copy,copy._nw_stats:value()} else copy:Remove() end
            built:Remove()
        end
        local count=0;for _ in pairs(variants) do count=count+1 end
        assert(row.tier==0 and count==1 or row.tier>0 and count>1)
        print("NW_WAND_CRAFT_SAMPLE:",name,json.encode(capacities),"distinct stats",count)
    end
    for version=1,2 do
        local old=SpawnPrefab("nw_wand")
        old.components.nw_wand:InitializeNew(0,"legacy-test")
        local d=old.components.nw_wand.data
        d.generator_version=version;d.stats.capacity=2;d.stats.draw_count=6
        d.stats.mana_max=24;d.stats.mana_regen=2;d.stats.cast_delay=2.4;d.stats.recharge=6
        d.runtime=require("nw/compiler").initial(d.cards,d.stats,d.seed)
        d.config_revision=d.config_revision+1;old.components.nw_wand:Sync()
        local copy=SpawnSaveRecord(old:GetSaveRecord())
        assert(copy._nw_stats:value()==old._nw_stats:value())
        assert(copy.components.nw_wand.data.generator_version==version)
        retained[#retained+1]={copy,copy._nw_stats:value()};old:Remove()
    end
    local check_recharge=recharge_probe()
    TheWorld:DoTaskInTime(.2,function()
        check_recharge()
        for _,row in ipairs(retained) do
            assert(row[1]._nw_stats:value()==row[2],"NW_WAND: deferred starter overwrote crafted stats")
            row[1]:Remove()
        end
        player:Remove();bench:Remove()
        print("NW_WAND_GENERATION_PASS: 240 paid native crafts, recipe tiers, rarity ranges, network stats, save/load, preserved v1/v2 rolls and deferred initialization")
    end)
end
return M
