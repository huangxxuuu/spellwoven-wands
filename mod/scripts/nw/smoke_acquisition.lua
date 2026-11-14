local M = {}
function M.run(x,z,starting_wand)
    for _,e in ipairs(TheSim:FindEntities(x,0,z,8,{"prototyper"})) do
        if e.prefab=="nw_workbench" or e.prefab=="nw_engraver" or e.prefab=="researchlab2" then e:Remove() end
    end
    local rules = require("nw/acquisition")
    local player = SpawnPrefab("wilson")
    player.Transform:SetPosition(x,0,z)
    local inv, builder = player.components.inventory, player.components.builder
    player.userid=player.userid or ""
    if TheWorld.components.playerspawner:IsPlayersInitialSpawn(player) and player.OnNewSpawn then
        player:OnNewSpawn()
        local starter=inv:FindItem(function(item) return item.prefab=="nw_wand" end)
        if starting_wand then
            assert(starter and starter.components.nw_wand.data.cards[1].spell_id=="spark","NW_STARTER: missing spark wand")
            starter:Remove()
        else
            assert(not starter,"NW_STARTER: disabled gift")
        end
        print("NW_STARTER_PASS: first spawn matches world setting",starting_wand)
    end
    player:AddComponent("playeractionpicker");player:AddComponent("playercontroller")
    player.components.playercontroller:Enable(true)
    for _,count in ipairs({1,7}) do
        local dust=SpawnPrefab("nw_dust")
        dust.Transform:SetPosition(x+.4,0,z)
        dust.components.stackable:SetStackSize(count)
        local clicks=player.components.playeractionpicker:GetLeftClickActions(dust:GetPosition(),dust)
        assert(clicks[1] and clicks[1].action==ACTIONS.PICKUP and clicks[1]:Do(),"NW_DUST: ground left-click failed")
        assert(inv:Has("nw_dust",count),"NW_DUST: missing picked-up stack")
        inv:ConsumeByName("nw_dust",count)
    end
    print("NW_DUST_PICKUP_PASS: native left-click action picks up single and seven-unit stacks")
    local function give(name, count)
        local item = SpawnPrefab(name)
        if item.components.stackable then item.components.stackable:SetStackSize(count) end
        assert(inv:GiveItem(item),"NW_CRAFT: cannot give "..name)
        if count>1 and not item.components.stackable then give(name,count-1) end
        return item
    end
    local built
    local function capture(_,data) built=data.item end
    player:ListenForEvent("buildstructure",capture)
    player:ListenForEvent("builditem",capture)
    builder:EvaluateTechTrees()
    assert(not builder.current_prototyper and not builder.freebuildmode,"NW_MENU: expected no station or free build")
    local design=AllRecipes.nw_engraver
    for _,v in ipairs(design.ingredients) do give(v.type,v.amount) end
    inv:Open(player)
    assert(not builder:KnowsRecipe(design) and not CanPrototypeRecipe(design.level,builder.accessible_tech_trees))
    builder:BufferBuild(design.name)
    assert(not builder:IsBuildBuffered(design.name),"NW_CRAFT: learned engraver in open field")
    local lab = SpawnPrefab("researchlab2")
    lab.Transform:SetPosition(x+24,0,z)
    player.Transform:SetPosition(x+23,0,z)
    builder:EvaluateTechTrees()
    assert(builder.current_prototyper==lab and CanPrototypeRecipe(design.level,builder.accessible_tech_trees))
    local hud={owner=player,valid_recipes={},IsCraftingOpen=function() return false end}
    require("widgets/redux/craftingmenu_hud").RebuildRecipes(hud)
    local data=assert(hud.valid_recipes.nw_engraver)
    assert(data.meta.build_state~="hide","NW_MENU: engraver hidden at alchemy engine")
    local widget={owner=player,crafting_hud=hud,recipe_grid={},sort_class={"nw_engraver"}}
    for _,filter in ipairs({"PROTOTYPERS","MAGIC","MODS"}) do
        widget.current_filter_name=filter
        require("widgets/redux/craftingmenu_widget").ApplyFilters(widget)
        assert(widget.filtered_recipes[1]==data,"NW_MENU: native filter omitted engraver: "..filter)
    end
    print("NW_MENU_PASS: native HUD lists engraver in all three filters")
    for _,name in ipairs({"PROTOTYPERS","MAGIC","MODS"}) do
        assert(table.contains(CRAFTING_FILTERS[name].recipes,design.name),"NW_MENU: missing engraver in "..name)
    end
    assert(IsRecipeValid(design.name) and not design.nounlock and not design.canbuild and not design.station_tag,"NW_MENU: hint/station invalid")
    builder:BufferBuild(design.name)
    assert(builder:IsBuildBuffered(design.name),"NW_MENU: unable to prototype beside alchemy engine")
    for _,v in ipairs(design.ingredients) do assert(not inv:Has(v.type,1),"NW_MENU: materials not consumed") end
    player.Transform:SetPosition(x+4,0,z)
    builder:EvaluateTechTrees()
    assert(not builder.current_prototyper and builder:KnowsRecipe(design) and builder:IsBuildBuffered(design.name),
        "NW_CRAFT: prebuilt or learned engraver lost away from engine")
    assert(builder:DoBuild(design.name,Vector3(x+4,0,z),0))
    assert(not builder:IsBuildBuffered(design.name),"NW_MENU: placement remained buffered")
    local engraver=built
    assert(engraver and engraver.prefab=="nw_engraver","NW_CRAFT: wrong new station")
    print("NW_ENGRAVER_PASS: science 2 prototype, consumed materials, retained knowledge and remote placement")
    player.Transform:SetPosition(x,0,z)
    lab.Transform:SetPosition(x-1,0,z)
    builder:EvaluateTechTrees()
    local recipe = AllRecipes.nw_workbench
    assert(CanPrototypeRecipe(recipe.level,builder.accessible_tech_trees),"NW_CRAFT: no science 2")
    for _,v in ipairs(recipe.ingredients) do give(v.type,v.amount) end
    assert(builder:DoBuild(recipe.name, Vector3(x+1,0,z),0))
    local bench=built
    assert(bench and bench.prefab=="nw_workbench")
    assert(PROTOTYPER_DEFS.nw_workbench.icon_image=="nw_workbench_station.tex","NW_CRAFT: station button art")
    lab:Remove()
    builder:EvaluateTechTrees()
    assert(builder.current_prototyper==bench,"NW_CRAFT: station not selected")
    local seen,weapon_count={},0
    for _,row in ipairs(rules.recipes) do
        local weapon=row.station=="nw_engraver"
        local expected=weapon and engraver or bench
        if builder.current_prototyper~=expected then
            player.Transform:SetPosition(x+(weapon and 4 or 0),0,z)
            builder:EvaluateTechTrees()
        end
        assert(builder.current_prototyper==expected)
        assert(not (weapon and bench or engraver).components.craftingstation:KnowsRecipe(row.name))
        if weapon then weapon_count=weapon_count+1 end
        assert(builder:KnowsRecipe(AllRecipes[row.name]),"NW_CRAFT: locked "..row.name)
        local melee=row.card=="thrust" or row.card=="slash" or row.card=="whirl"
        for i,v in ipairs(row.ingredients) do give(v[1],melee and i==2 and 1 or v[2]) end
        if melee then
            assert(not builder:HasIngredients(AllRecipes[row.name]),"NW_CRAFT: one weapon was sufficient")
            local weapon=give(row.ingredients[2][1],1)
            weapon.components.finiteuses:SetPercent(.1)
        end
        assert(builder:HasIngredients(AllRecipes[row.name]),"NW_CRAFT: missing ingredients "..row.name)
        built=nil
        assert(builder:DoBuild(row.name) and built and built.prefab==row.product,"NW_CRAFT: "..row.name)
        if row.card then assert(built.spell_id==row.card) end
        if melee then assert(not inv:Has(row.ingredients[2][1],1),"NW_CRAFT: did not consume both weapons") end
        if row.tier then
            local visual=require("nw/visual")
            local code=visual.recipe_code(row.tier)
            local _,length=visual.parts(code)
            local expected=({"short","short","medium","long"})[row.tier+1]
            assert(length==expected and AllRecipes[row.name].image==visual.icon(code)..".tex"
                and AllRecipes[row.name].atlas==resolvefilepath(visual.atlas(code)),"NW_CRAFT: wand recipe artwork")
            local d=built.components.nw_wand.data
            assert(d.tier==math.max(1,row.tier) and d.source==row.name and not seen[d.wand_uid])
            seen[d.wand_uid]=true
            if row.tier==0 then assert(d.stats.capacity==2 and d.cards[1].spell_id=="spark" and not d.cards[2]) end
            local copy=SpawnSaveRecord(built:GetSaveRecord())
            assert(copy.components.nw_wand.data.wand_uid==d.wand_uid)
            copy:Remove()
        end
        if row.count>1 then assert(built.components.stackable:StackSize()==row.count) end
        built:Remove()
    end
    assert(weapon_count==63,"NW_CRAFT: weapon recipe split")
    for _,station in ipairs({bench,engraver}) do
        player.Transform:SetPosition(station.Transform:GetWorldPosition())
        builder:EvaluateTechTrees()
        assert(builder.current_prototyper==station)
        local slots=station.components.craftingstation:GetItems()
        local index=0
        for _,row in ipairs(rules.menu_entries) do
            if row.station==station.prefab then
                index=index+1
                assert(slots[index]==row.name,"NW_MENU: incorrect station slot "..index)
                assert(not row.section_icon and not AllRecipes[row.name].nw_section,"NW_MENU: obsolete heading")
            end
        end
        assert(#slots==index)
    end
    print("NW_STATION_RECIPES_PASS: both stations contain real recipes only")
    print("NW_STATIONS_PASS: crafted both stations and all recipes, 63 exclusive weapon cards")
    local gem= give("redgem",1)
    give("goldnugget",1)
    player.Transform:SetPosition(x+20,0,z)
    assert(not builder:DoBuild("nw_dust_redgem") and gem:IsValid(),"NW_CRAFT: stale bench spent gem")
    builder:EvaluateTechTrees()
    assert(not builder:KnowsRecipe(AllRecipes.nw_dust_redgem),"NW_CRAFT: learned portable recipe")
    player.Transform:SetPosition(x,0,z)
    require("nw/smoke_coast").run(x,z)
    require("nw/smoke_furnace").run(x+10,z+8)
    local bear=SpawnPrefab("mutatedbearger")
    bear.Transform:SetPosition(x+3,0,z)
    local drops={}
    bear:ListenForEvent("loot_prefab_spawned",function(_,data)
        if data.loot.prefab:sub(1,3)=="nw_" then table.insert(drops,data.loot) end
    end)
    bear.components.health:ForceKill()
    bear:PushEvent("death")
    assert((#drops==3 or #drops==4) and bear.components.nw_rewarded,"NW_LOOT: epic encounter did not settle exactly once")
    local loot={}
    for _,item in ipairs(drops) do loot[item.prefab]=item end
    assert(loot.nw_wand.components.nw_wand.data.tier==4 and loot.nw_overlord_core.components.stackable:StackSize()==1)
    assert(loot.nw_dust.components.stackable:StackSize()==16)
    assert(loot.nw_wand.components.nw_wand:PreviewCast().projectile_count>0)
    for _,item in ipairs(drops) do item:Remove() end
    bear:Remove()
    local bat = SpawnPrefab("bat_boss_shadow")
    local twin = SpawnPrefab("bat_boss_shadow")
    bat.Transform:SetPosition(x+3,0,z)
    twin.Transform:SetPosition(x+4,0,z)
    bat:StartTrackingClone(twin)
    twin:StartTrackingClone(bat)
    local batcores = 0
    local function countcore(_,data)
        if data.loot.prefab=="nw_overlord_core" then batcores=batcores+1 end
    end
    bat:ListenForEvent("loot_prefab_spawned",countcore)
    twin:ListenForEvent("loot_prefab_spawned",countcore)
    bat.components.health:ForceKill()
    assert(batcores==0,"NW_LOOT: surviving clone still present")
    twin.components.health:ForceKill()
    assert(batcores==1,"NW_LOOT: missing last-clone reward")
    bat:Remove(); twin:Remove()
    engraver:Remove(); bench:Remove(); player:Remove()
    print("NW_ACQUISITION_PASS: science 2 + bench + all station recipes, identity restore, distance and recycle guards, real epic death + dedup")
end
return M
