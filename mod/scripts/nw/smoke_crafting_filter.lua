local M={}
function M.run()
    local Rules=require("nw/acquisition")
    local Filter=require("nw/crafting_filter")
    local Visuals=require("nw/card_visuals").cards
    local Menu=require("widgets/redux/craftingmenu_widget")
    local HUD=require("widgets/redux/craftingmenu_hud")
    local player=SpawnPrefab("wilson")
    local builder=player.components.builder
    local x,_,z=player.Transform:GetWorldPosition()
    local hud={owner=player,valid_recipes={},is_open=false,IsCraftingOpen=function(self) return self.is_open end}
    local menu={owner=player,crafting_hud=hud,recipe_grid={},sort_class={},
        current_filter_name="CRAFTING_STATION",search_text="",last_search_text="",
        searched_recipes={},last_searched_recipes={},filter_buttons={},StartUpdating=function() end}
    menu.ApplyFilters=Menu.ApplyFilters
    menu.IsRecipeValidForSearch=Menu.IsRecipeValidForSearch
    menu.ValidateRecipeForSearch=Menu.ValidateRecipeForSearch
    menu.SetSearchText=Menu.SetSearchText
    for name in pairs(CRAFTING_FILTERS) do
        menu.filter_buttons[name]={button={Select=function() end,Unselect=function() end}}
    end
    for _,row in ipairs(Rules.recipes) do menu.sort_class[#menu.sort_class+1]=row.name end
    for name,recipe in pairs(AllRecipes) do
        assert(not name:match("^nw_workbench_section_") and not name:match("^nw_engraver_section_"),"retired header registered")
        assert(not recipe.nw_section,"retired section recipe")
    end
    local total=0
    for i,prefab in ipairs({"nw_workbench","nw_engraver"}) do
        local station=SpawnPrefab(prefab)
        station.Transform:SetPosition(x+i*16,0,z)
        player.Transform:SetPosition(x+i*16+1,0,z)
        builder:EvaluateTechTrees()
        assert(builder.current_prototyper==station,"native station selection")
        assert(station.components.craftingstation.nosave,"station recipes should rebuild on load")
        local learned=station.components.craftingstation:GetItems()
        local expected={basic=0,modifier=0,control=0}
        local count=0
        for _,row in ipairs(Rules.recipes) do
            if row.station==prefab then
                count=count+1
                assert(learned[count]==row.name and AllRecipes[row.name],"station recipe order")
                if row.card then local class=assert(Visuals[row.card]).primary_class;expected[class]=expected[class]+1 end
            end
        end
        assert(#learned==count,"station contains placeholder entries")
        HUD.RebuildRecipes(hud)
        menu.current_filter_name="CRAFTING_STATION"
        Menu.ApplyFilters(menu)
        assert(#menu.filtered_recipes==count,"native station filter lost recipes")
        assert(Filter.filter(menu.filtered_recipes,prefab,"all")==menu.filtered_recipes)
        for class,n in pairs(expected) do
            assert(#Filter.filter(menu.filtered_recipes,prefab,class)==n,"class result count: "..class)
        end
        local options=Filter.tags(prefab,"all")
        assert(#options>0,"station tag options missing")
        local both=Filter.filter(menu.filtered_recipes,prefab,"all",{speed=true,lifetime=true})
        if prefab=="nw_workbench" then assert(#both==1 and both[1].recipe.name=="nw_inscribe_speed_down","native recipe AND tag intersection")
        else assert(#both==0,"tags must not cross station boundaries") end
        assert(#Filter.filter(menu.filtered_recipes,prefab,"all",{mana=true,recovery=true})==0,
            "incompatible tags must yield an empty result")
        hud.is_open=true
        assert(Filter.station(menu)==prefab)
        hud.is_open=false
        assert(Filter.station(menu)==nil)
        menu:SetSearchText(STRINGS.NAMES.NW_WORKBENCH)
        Menu.SelectFilter(menu,nil,false)
        assert(menu.current_filter_name=="EVERYTHING" and Filter.station(menu)==nil,"native global search changed")
        menu:SetSearchText("")
        total=total+count
        station:Remove()
    end
    player:Remove()
    print("NW_CRAFTING_FILTER_PASS: "..total.." real station recipes; class counts, AND tags, local activation and global search")
end
return M
