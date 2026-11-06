local hooks={}
package.loaded["widgets/widgetutil"]=true
local global={STRINGS={NAMES={TEST_HEADER="工具一"}},DoRecipeClick=function() return false,"crafted" end}
require("nw/crafting_sections").install({AddClassPostConstruct=function(path,fn) hooks[path]=fn end},global)
local title={recipe={name="test_header",nw_section=true,station_tag="nw_engraver"}}
local card={recipe={name="nw_inscribe_edge_pickaxe"}}
assert(global.DoRecipeClick(nil,title.recipe)==true)
local stay,message=global.DoRecipeClick(nil,card.recipe)
assert(not stay and message=="crafted")

local function control() return {Hide=function(self) self.hidden=true end} end
local panel={data=title,build_button_root={button=control(),teaser=control()},fav_button=control(),
    UpdateBuildButton=function(self) self.normal=true end}
hooks["widgets/redux/craftingmenu_details"](panel)
panel:UpdateBuildButton()
assert(panel.build_button_root.button.hidden and panel.build_button_root.teaser.hidden and not panel.normal)
panel.data=card
panel:UpdateBuildButton()
assert(panel.normal)

local station={HasTag=function(_,tag) return tag=="nw_engraver" end}
local grid={update_fn=function(_,cell,data) cell.data=data end}
local menu={recipe_grid=grid,current_filter_name="CRAFTING_STATION",sort_mode=1,
    owner={replica={builder={GetCurrentPrototyper=function() return station end}}},
    UpdateRecipeGrid=function(self) return #self.filtered_recipes end}
hooks["widgets/redux/craftingmenu_widget"](menu)
local slots={{"CRAFTING_STATION",1,2},{"EVERYTHING",1,1},{"CRAFTING_STATION",2,1}}
for _,case in ipairs(slots) do
    menu.current_filter_name,menu.sort_mode=case[1],case[2]
    menu.filtered_recipes={title,card}
    assert(menu:UpdateRecipeGrid()==case[3] and menu.filtered_recipes[case[3]]==card)
end
local cell={cell_root={SetHoverText=function(self,text) self.text=text end,
    ClearHoverText=function(self) self.text=nil end}}
grid.update_fn(nil,cell,title,1)
assert(cell.cell_root.text=="工具一")
grid.update_fn(nil,cell,card,2)
assert(cell.data==card and not cell.cell_root.text)
