local M={}

function M.install(env,global)
    -- Grid double-click, held click, pin slots and controller shortcuts
    -- share this entry point. Consume a title click before it sends an RPC.
    require("widgets/widgetutil")
    local click=global.DoRecipeClick
    global.DoRecipeClick=function(owner,recipe,...)
        if recipe and recipe.nw_section then return true end
        return click(owner,recipe,...)
    end

    env.AddClassPostConstruct("widgets/redux/craftingmenu_details",function(panel)
        local update=panel.UpdateBuildButton
        panel.UpdateBuildButton=function(self,...)
            if self.data and self.data.recipe.nw_section then
                self.first_sub_ingredient_to_craft=nil
                self.build_button_root.button:Hide()
                self.build_button_root.teaser:Hide()
                self.fav_button:Hide()
                return
            end
            return update(self,...)
        end
    end)

    -- A divider only describes adjacent cards in the station's default order.
    -- Exclude it from free-build browsing, search results and alternative sorts.
    env.AddClassPostConstruct("widgets/redux/craftingmenu_widget",function(menu)
        local grid=menu.recipe_grid
        local set_cell=grid.update_fn
        grid.update_fn=function(context,cell,data,index)
            set_cell(context,cell,data,index)
            local title=data and data.recipe.nw_section and data.recipe.name
            if title~=cell.nw_section_title then
                if cell.nw_section_title then cell.cell_root:ClearHoverText() end
                if title then
                    cell.cell_root:SetHoverText(global.STRINGS.NAMES[title:upper()],{offset_y=32})
                end
                cell.nw_section_title=title
            end
        end
        local update=menu.UpdateRecipeGrid
        menu.UpdateRecipeGrid=function(self,...)
            local builder=self.owner.replica.builder
            local station=self.current_filter_name=="CRAFTING_STATION" and self.sort_mode==1
                and builder and builder:GetCurrentPrototyper()
            for i=#self.filtered_recipes,1,-1 do
                local recipe=self.filtered_recipes[i].recipe
                if recipe.nw_section and not (station and station:HasTag(recipe.station_tag)) then
                    table.remove(self.filtered_recipes,i)
                end
            end
            return update(self,...)
        end
    end)
end

return M
