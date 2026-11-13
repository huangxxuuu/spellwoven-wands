local Filter=require("nw/crafting_filter")
local Balance=require("nw/balance")
local Rules=require("nw/acquisition")
local identities=require("nw/card_visuals").cards
local Tags=require("nw/card_tags")
assert(Tags.for_card("repeat_2").copy and not Tags.for_card("repeat_2").modifier)
assert(Tags.for_card("imprint_hit").trigger and not Tags.for_card("imprint_hit").modifier)
assert(Tags.for_card("spark_timer").trigger and not Tags.for_card("spark").trigger)
assert(Rules.menu_entries==Rules.recipes)
for _,row in ipairs(Rules.menu_entries) do
    assert(not row.section_icon and not row.name:find("_section_",1,true))
    if row.card then
        assert(identities[row.card] and identities[row.card].primary_class,"Missing recipe class: "..row.card)
    end
end

local function node(name,x,y)
    local n={name=name,children={},shown=true,pos={x=x or 0,y=y or 0,z=0},scale={x=1,y=1,z=1},
        focus_flow={},focus_flow_args={}}
    function n:GetPosition() return self.pos end
    function n:SetPosition(a,b,c) self.pos={x=a,y=b,z=c or 0} end
    function n:GetScale() error("frame resizing must use local scale, independent of HUD zoom") end
    function n:GetLooseScale() return self.scale.x,self.scale.y,self.scale.z end
    function n:SetScale(a,b,c) self.scale={x=a,y=b,z=c or 1} end
    function n:GetSize() return 500,600 end
    function n:GetChildren() return self.children end
    function n:AddChild(child) self.children[child]=child;return child end
    function n:Show() self.shown=true end
    function n:Hide() self.shown=false end
    function n:SetFocus() self.focus=true end
    function n:ClearFocus() self.focus=false end
    function n:SetFocusChangeDir(dir,target,...)
        self.focus_flow[dir]=target;self.focus_flow_args[dir]={...}
    end
    function n:PopulateRecipeDetailPanel(data) self.data=data end
    return n
end
package.loaded["widgets/widget"]=node
package.loaded["widgets/text"]=function(_,_,text) local n=node("text");n.text=text;return n end
package.loaded["widgets/spinner"]=function(options)
    local n=node("spinner");n.options=options;n.index=1
    function n:SetWrapEnabled(value) self.wrap=value end
    function n:SetSelectedIndex(index) self.index=index end
    function n:SetOnChangedFn(fn) self.change=fn end
    function n:GetHelpText() return "native spinner controller hints" end
    function n:Choose(value)
        for i,row in ipairs(self.options) do if row.data==value then self.index=i;break end end
        self.change(value)
    end
    return n
end
package.loaded["widgets/nw_craftingfilters"]=function(options,onclass,ontag)
    local n=node("station filters")
    n.spinner=package.loaded["widgets/spinner"](options)
    n.spinner:SetOnChangedFn(onclass)
    n.focus_forward=n.spinner
    function n:SetChoices(options) self.spinner.options=options end
    function n:SetChoice(value)
        for i,row in ipairs(self.spinner.options) do
            if row.data==value then self.spinner:SetSelectedIndex(i);break end
        end
    end
    function n:SetTags(list,selected) self.tag_list=list;self.selected=selected end
    function n:HasFilterFocus() return self.spinner.focus or self.tag_focus end
    function n:GetHelpText() return self.tag_focus and "tag filter hints" or self.spinner:GetHelpText() end
    function n:SetNavigation(up,down)
        self.spinner:SetFocusChangeDir(1,up)
        self.spinner:SetFocusChangeDir(2,down)
    end
    function n:ClearFocus() self.focus=false;self.spinner:ClearFocus();self.tag_focus=false end
    function n:ToggleTag(id) ontag(id) end
    return n
end
local G={UIFONT="test",MOVE_UP=1,MOVE_DOWN=2,TheNet={IsDedicated=function() return false end}}
local hooks={}
local setting=true
local env={GetModConfigData=function(name,local_only)
    assert(name=="disable_crafting_filter" and local_only==true,"must honor the player's local setting")
    return setting
end,AddClassPostConstruct=function(name,fn) hooks[name]=fn end}
Filter.install(env,G)
assert(next(hooks)==nil,"disabled setting must not install any UI hook")
setting=nil
Filter.install(env,G)
assert(hooks["widgets/redux/craftingmenu_widget"] and hooks["widgets/redux/craftingmenu_hud"])
local hook_count=0
Filter.install({GetModConfigData=function() error("dedicated server read local config") end,
    AddClassPostConstruct=function() hook_count=hook_count+1 end},{TheNet={IsDedicated=function() return true end}})
assert(hook_count==0)

local function recipe(name) return {recipe={name=name}} end
local basic=recipe("nw_inscribe_spark")
local modifier=recipe("nw_inscribe_homing")
local control=recipe("nw_inscribe_double")
local blank=recipe("nw_blank")
local engraving=recipe("nw_inscribe_thrust")
local unrelated=recipe("another_mod_card")
local original=recipe("axe")
local lists={nw_workbench={blank,basic,modifier,control,unrelated},nw_engraver={engraving},researchlab2={original}}
assert(Filter.filter(lists.nw_workbench,"nw_workbench","all")==lists.nw_workbench)
assert(Filter.filter({engraving,modifier},"nw_workbench","basic")[1]==nil)
-- Semantic fixtures distinguish intersection from union and preserve sort order.
local plain_modifier=recipe("nw_inscribe_sine")
local tag_source={blank,basic,plain_modifier,modifier,unrelated}
local trajectory_tag,homing_tag="trajectory","homing"
assert(Filter.filter(tag_source,"nw_workbench","all",{})==tag_source)
local tagged=Filter.filter(tag_source,"nw_workbench","all",{[trajectory_tag]=true,[homing_tag]=true})
assert(#tagged==1 and tagged[1]==modifier,"selected tags must use AND, including in All Recipes")
local sorted_tags=Filter.filter(tag_source,"nw_workbench","all",{[trajectory_tag]=true})
assert(#sorted_tags==2 and sorted_tags[1]==plain_modifier and sorted_tags[2]==modifier,"tag filtering preserves native recipe order")
assert(#Filter.filter(tag_source,"nw_workbench","basic",{[homing_tag]=true})==0,"class and tags must intersect")
assert(Filter.filter(tag_source,nil,"modifier",{[homing_tag]=true})==tag_source,"ordinary crafting pages stay native")
assert(#Filter.class_options("nw_workbench")==4)
assert(#Filter.class_options("nw_engraver")==2)
local available=Filter.tags("nw_workbench","modifier")
local available_ids={}
for _,tag in ipairs(available) do
    assert(tag.id and tag.text and not available_ids[tag.id],"tag list must have unique stable IDs and labels")
    available_ids[tag.id]=true
end
assert(available_ids[trajectory_tag] and available_ids[homing_tag])
local station={prefab="nw_workbench",IsValid=function() return true end}
local hud={is_open=false,IsCraftingOpen=function(self) return self.is_open end}
local menu={crafting_hud=hud,owner={replica={builder={GetCurrentPrototyper=function() return station end}}},
    current_filter_name="CRAFTING_STATION",search_text="",filtered_recipes={},sort_mode=1}
hud.craftingmenu=menu
menu.frame=node("frame")
for _,texture in ipairs({"backing.tex","top.tex","bottom.tex","side.tex","side.tex"}) do
    local n=menu.frame:AddChild(node(texture));n.texture=texture
    if texture=="side.tex" then n:SetScale(-.1,-1,1) end
end
for _,key in ipairs({"filter_panel","itemlist_split","recipe_grid","no_recipes_msg","itemlist_split2","details_root","nav_hint"}) do
    menu[key]=node(key,0,100)
end
menu.filter_panel.filter_grid=node("native filters")
local native_up=function() return menu.filter_panel.filter_grid end
local native_down=function() return menu.recipe_grid end
function menu:DoFocusHookups()
    self.recipe_grid:SetFocusChangeDir(G.MOVE_UP,native_up,"native up argument")
    self.filter_panel.filter_grid:SetFocusChangeDir(G.MOVE_DOWN,native_down,"native down argument")
end
function menu:UpdateRecipeGrid(set_focus)
    self.displayed=self.filtered_recipes
    self.last_set_focus=set_focus
    return "native return"
end
function menu:ApplyFilters()
    self.filtered_recipes={}
    local source=self.current_filter_name=="CRAFTING_STATION" and station and lists[station.prefab] or {original}
    for _,data in ipairs(source or {}) do self.filtered_recipes[#self.filtered_recipes+1]=data end
    if self.sort_mode==2 then
        local reversed={};for i=#self.filtered_recipes,1,-1 do reversed[#reversed+1]=self.filtered_recipes[i] end
        self.filtered_recipes=reversed
    end
    if self.crafting_hud:IsCraftingOpen() then self:UpdateRecipeGrid(true) end
end
function menu:Refresh() self.details_root.native_refreshed=true end
function menu:SelectFilter(name)
    self.current_filter_name=name;self.search_text="";self:ApplyFilters()
end
function menu:Search(text)
    self.search_text=text;self.current_filter_name="EVERYTHING";self:ApplyFilters()
end
function hud:Open()
    -- Match the native order: populate first, mark open last.
    self.craftingmenu:ApplyFilters();self.is_open=true
end
function hud:Close() self.is_open=false end
local native_search=menu.Search
menu.RefreshCraftingHelpText=function() return "native menu hints" end
hooks["widgets/redux/craftingmenu_widget"](menu)
menu:DoFocusHookups()
hooks["widgets/redux/craftingmenu_hud"](hud)
local state=assert(menu.nw_class_filter)
assert(not state.root.shown and not state.active and Filter.station(menu)==nil)
assert(menu.itemlist_split:GetPosition().y==100)
Balance.configure("balanced_loot")
hud:Open()
assert(not state.active and not state.root.shown and Filter.station(menu)==nil)
assert(#menu.filtered_recipes==5 and menu.itemlist_split:GetPosition().y==100 and menu.recipe_grid:GetPosition().y==100,
    "loot-only starts with native recipes and layout")
assert(menu.recipe_grid.focus_flow[G.MOVE_UP]==native_up)
Balance.configure("fun")
menu:Refresh()
assert(state.root.shown and state.active and #menu.displayed==5)
assert(menu.itemlist_split:GetPosition().y==158 and menu.recipe_grid:GetPosition().y==42)
assert(menu.recipe_grid.focus_flow[G.MOVE_UP]()==state.spinner)
assert(menu.filter_panel.filter_grid.focus_flow[G.MOVE_DOWN]()==state.spinner)
state.spinner.focus=true
assert(menu:RefreshCraftingHelpText()=="native spinner controller hints")
menu.details_root.data=basic
state.spinner:Choose("modifier")
assert(#menu.displayed==1 and menu.displayed[1]==modifier)
assert(not menu.last_set_focus,"controller must stay on selector while changing class")
assert(menu.details_root.data==nil,"filtered-out recipe must not remain craftable in details")
assert(menu:UpdateRecipeGrid(false)=="native return" and #menu.displayed==1,"repeat grid refresh")
state.spinner:Choose("control")
assert(#menu.displayed==1 and menu.displayed[1]==control)
state.spinner:Choose("all")
assert(#menu.displayed==5 and menu.displayed[1]==blank and menu.displayed[5]==unrelated)
assert(#lists.nw_workbench==5,"native source table mutated")
menu.sort_mode=2
menu:ApplyFilters()
assert(menu.displayed[1]==unrelated and menu.displayed[5]==blank,"preserve native sort order")
state.spinner:Choose("basic")
assert(#menu.displayed==1 and menu.displayed[1]==basic)
-- Each main class remembers one selected tag until the drawer closes.
local ordinary_workbench=lists.nw_workbench
lists.nw_workbench=tag_source
state.spinner:Choose("all")
assert(not next(state.root.selected),"new class starts with no selected tags")
state.root.tag_focus=true;state.spinner.focus=false
state.root:ToggleTag(trajectory_tag)
assert(#menu.displayed==2 and not menu.last_set_focus,"tag click keeps focus in the filter row")
assert(menu:RefreshCraftingHelpText()=="tag filter hints")
local tag_count=#state.root.tag_list
menu.details_root.data=plain_modifier
state.root:ToggleTag(homing_tag)
assert(#menu.displayed==1 and menu.displayed[1]==modifier)
assert(menu.details_root.data==nil,"tag filtering must clear an excluded recipe detail")
assert(#state.root.tag_list==tag_count,"filtered results must not erase tag controls")
assert(not state.root.selected[trajectory_tag] and state.root.selected[homing_tag],"a new tag replaces the previous selection")
state.root:ToggleTag("unknown_tag")
assert(state.root.selected[homing_tag],"an invalid tag must not clear the current selection")
state.spinner:Choose("modifier")
assert(not next(state.root.selected),"a different class has an independent selection")
state.root:ToggleTag(homing_tag)
assert(#menu.displayed==1 and menu.displayed[1]==modifier)
state.spinner:Choose("all")
assert(not state.root.selected[trajectory_tag] and state.root.selected[homing_tag],"return restores the single selected tag")
state.root:ToggleTag(homing_tag)
assert(#menu.displayed==#tag_source and not next(state.root.selected),"clicking the selected tag restores all class recipes")
state.root:ToggleTag(homing_tag)
state.root:ToggleTag(trajectory_tag)
assert(#menu.displayed==2 and state.root.selected[trajectory_tag] and not state.root.selected[homing_tag],"replacing a narrow filter must broaden results without a stale intersection")
menu:SelectFilter("TOOLS")
menu:SelectFilter("CRAFTING_STATION")
assert(state.root.selected[trajectory_tag] and #menu.displayed==2,"native category round trip preserves selection")
menu:Search("axe")
assert(not state.active and menu.displayed[1]==original)
menu:SelectFilter("CRAFTING_STATION")
assert(state.root.selected[trajectory_tag] and #menu.displayed==2,"native search round trip preserves selection")
station={prefab="nw_engraver",IsValid=function() return true end}
menu:Refresh()
assert(not next(state.root.selected) and menu.displayed[1]==engraving,"station tag selections are independent")
station={prefab="nw_workbench",IsValid=function() return true end}
menu:Refresh()
assert(state.root.selected[trajectory_tag] and #menu.displayed==2,"station round trip restores tags")
state.root:ToggleTag(trajectory_tag)
assert(#menu.displayed==#tag_source and not next(state.root.selected))
state.spinner:Choose("modifier")
assert(state.root.selected[homing_tag] and #menu.displayed==1,"other class selection remained intact")
state.root:ToggleTag(homing_tag)
state.root.tag_focus=false;state.spinner.focus=true
state.spinner:Choose("basic")
lists.nw_workbench=ordinary_workbench;menu:ApplyFilters()
assert(#menu.displayed==1 and menu.displayed[1]==basic)
menu:SelectFilter("TOOLS")
assert(not state.active and not state.root.shown and menu.displayed[1]==original)
assert(menu.recipe_grid:GetPosition().y==100 and menu.itemlist_split:GetPosition().y==100)
assert(menu.recipe_grid.focus_flow[G.MOVE_UP]==native_up)
assert(menu.recipe_grid.focus_flow_args[G.MOVE_UP][1]=="native up argument")
assert(menu:RefreshCraftingHelpText()=="native menu hints")
menu.details_root.data=control
menu:UpdateRecipeGrid(false)
assert(menu.details_root.data==control,"must not change native detail behavior outside our page")
menu:SelectFilter("CRAFTING_STATION")
assert(state.spinner.options[state.spinner.index].data=="basic" and menu.displayed[1]==basic)
menu:Search("axe")
assert(menu.Search==native_search and menu.current_filter_name=="EVERYTHING" and not state.active)
assert(menu.displayed[1]==original and menu.recipe_grid.focus_flow[G.MOVE_UP]==native_up)
menu:SelectFilter("CRAFTING_STATION")
menu.search_text="old native search cache"
assert(Filter.station(menu)=="nw_workbench","native search cache must not disable the selected station page")
menu.search_text=""
station={prefab="nw_engraver",IsValid=function() return true end}
menu:Refresh()
assert(state.station=="nw_engraver" and #menu.displayed==1 and menu.displayed[1]==engraving)
assert(state.spinner.options[state.spinner.index].data=="all","separate station preference")
state.spinner:Choose("modifier")
assert(#state.spinner.options==2 and state.spinner.options[1].data=="all" and state.spinner.options[2].data=="basic")
assert(#menu.displayed==1,"hidden class cannot be selected on engraving station")
assert(state.spinner.options[state.spinner.index].data=="all")
station={prefab="nw_workbench",IsValid=function() return true end}
menu:Refresh()
assert(menu.displayed[1]==basic,"restore previous station preference")
station=nil
menu:Refresh()
assert(not state.active and menu.recipe_grid:GetPosition().y==100)
station={prefab="researchlab2",IsValid=function() return true end}
menu:Refresh()
assert(not state.active,"unrelated station")
station={prefab="nw_workbench",IsValid=function() return false end}
menu:Refresh()
assert(not state.active,"destroyed station")
station={prefab="nw_workbench",IsValid=function() return true end}
menu:Refresh()
assert(state.active)
state.spinner:Choose("basic")
state.root:ToggleTag("element")
assert(#menu.displayed==0 and state.root.selected.element)
local empty_tag_count=#state.root.tag_list
assert(empty_tag_count>0,"empty result retains tag row so it can be cleared")
hud:Close()
assert(not state.active)
hud:Open()
assert(state.spinner.options[state.spinner.index].data=="all")
assert(not next(state.root.selected) and #menu.displayed==5,"closing the drawer resets filters")
-- A world-mode reply received after the menu was built disables both class
-- and tag filtering, restores native layout/focus, and keeps all native rows.
state.spinner:Choose("modifier")
state.root:ToggleTag(homing_tag)
state.root.tag_focus=true
Balance.configure("balanced_loot")
menu:Refresh()
assert(not state.active and not state.root.shown and #menu.displayed==5)
assert(menu.recipe_grid:GetPosition().y==100 and menu.itemlist_split:GetPosition().y==100)
assert(menu.recipe_grid.focus_flow[G.MOVE_UP]==native_up and not state.root:HasFilterFocus())
hud:Close();hud:Open()
assert(not state.active and not state.root.shown and #menu.displayed==5)
Balance.configure("balanced")
menu:Refresh()
assert(state.active and state.root.shown and #menu.displayed==5,"other world difficulties keep the existing local preference")
Balance.configure("fun")
-- Repeated entries must never accumulate offsets or scale drift.
for i=1,10 do hud:Close();hud:Open() end
assert(menu.recipe_grid:GetPosition().y==42)
menu:DoFocusHookups()
assert(menu.recipe_grid.focus_flow[G.MOVE_UP]()==state.spinner)
-- Another mod's later focus assignment and relative move survive our exit.
local foreign=function() return "foreign focus" end
menu.recipe_grid:SetFocusChangeDir(G.MOVE_UP,foreign)
menu.recipe_grid:SetPosition(7,49,0)
hud:Close()
assert(not state.active and not state.root.shown and menu.recipe_grid:GetPosition().y==107)
assert(menu.recipe_grid:GetPosition().x==7 and menu.recipe_grid.focus_flow[G.MOVE_UP]==foreign)
for _,n in pairs(menu.frame:GetChildren()) do
    if n.texture=="side.tex" then local _,sy=n:GetLooseScale();assert(math.abs(sy+1)<1e-10) end
end
local replaced={crafting_hud=hud,filter_panel={filter_grid={}},UpdateRecipeGrid=function() end,
    ApplyFilters=function() end,Refresh=function() end,DoFocusHookups=function() end}
Filter.attach(replaced,G)
assert(replaced.nw_class_filter==nil,"unknown replacement menu must stay untouched")
print("crafting filter: local opt-out, single-tag replacement/cancellation, drawer-scoped selections, native search/sort, focus, details and reversible layout")
