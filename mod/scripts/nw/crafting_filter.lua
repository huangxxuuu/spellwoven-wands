-- Client-only main-class and single-tag filtering. Native search and crafting
-- remain untouched. Disabling the local option installs no menu hooks at all.
local M={}
local stations={nw_workbench=true,nw_engraver=true}
local classes={all=true,basic=true,modifier=true,control=true}
local ROW_HEIGHT=116 -- class heading plus two tag rows
local class_order={"all","basic","modifier","control"}
local class_names={all="全部配方",basic="基础法术",modifier="法术修饰",control="施法控制"}

-- Use the station catalogue, not tag-filtered results or current ingredients:
-- an empty tag intersection must never remove the selected category.
function M.class_options(station)
    local present={all=true}
    local cards=require("nw/card_visuals").cards
    for _,row in ipairs(require("nw/acquisition").menu_entries) do
        local identity=row.card and cards[row.card]
        if row.station==station and identity then present[identity.primary_class]=true end
    end
    local result={}
    for _,id in ipairs(class_order) do
        if present[id] then result[#result+1]={data=id,text=require("nw/locale").t(class_names[id])} end
    end
    return result
end

function M.station(menu)
    -- Native text entry selects EVERYTHING. Its search cache can retain text
    -- after returning to a station, so use the selected page, not that cache.
    if not menu.crafting_hud:IsCraftingOpen() or menu.current_filter_name~="CRAFTING_STATION" then return nil end
    local builder=menu.owner and menu.owner.replica and menu.owner.replica.builder
    local station=builder and builder:GetCurrentPrototyper()
    return station and station:IsValid() and stations[station.prefab] and station.prefab or nil
end

function M.filter(recipes,station,choice,selected)
    local tagged=selected and next(selected)~=nil
    if not station or choice=="all" and not tagged then return recipes end
    local rules=require("nw/acquisition")
    local cards=require("nw/card_visuals").cards
    local tags=require("nw/card_tags")
    local result={}
    for _,data in ipairs(recipes) do
        local row=rules.by_name[data.recipe.name]
        local identity=row and row.card and cards[row.card]
        local matches=row and row.station==station and identity
            and (choice=="all" or identity.primary_class==choice)
        if matches and tagged then
            local own=tags.for_card(row.card)
            for id,enabled in pairs(selected) do
                if enabled and not own[id] then matches=false;break end
            end
        end
        if matches then result[#result+1]=data end
    end
    return result
end

-- Options come from the station's complete recipe catalogue, not a filtered
-- result. Choosing a tag never hides other tags or traps an empty selection.
function M.tags(station,choice)
    local present={}
    local cards=require("nw/card_visuals").cards
    local tags=require("nw/card_tags")
    for _,row in ipairs(require("nw/acquisition").menu_entries) do
        local identity=row.card and cards[row.card]
        if row.station==station and identity and (choice=="all" or identity.primary_class==choice) then
            for id in pairs(tags.for_card(row.card)) do present[id]=true end
        end
    end
    return tags.options(present)
end

local function shift(widget,dy)
    local p=widget:GetPosition()
    widget:SetPosition(p.x,p.y+dy,p.z)
end

-- Extend the stock frame symmetrically; keep all three recipe rows and the
-- detail panel. Only undo our own deltas, preserving unrelated relative moves.
local function layout(menu)
    local move={{menu.filter_panel,1},{menu.itemlist_split,1},{menu.recipe_grid,-1},
        {menu.no_recipes_msg,-1},{menu.itemlist_split2,-1},{menu.details_root,-1},{menu.nav_hint,-1}}
    for _,entry in ipairs(move) do
        if not entry[1] or not entry[1].GetPosition or not entry[1].SetPosition then return end
    end
    if not menu.frame or not menu.frame.GetChildren then return end
    local resize={}
    local found={}
    for _,child in pairs(menu.frame:GetChildren()) do
        local texture=child.texture
        if texture=="top.tex" or texture=="bottom.tex" then
            move[#move+1]={child,texture=="top.tex" and 1 or -1}
            found[texture]=(found[texture] or 0)+1
        elseif texture=="backing.tex" or texture=="side.tex" then
            if not child.GetSize or not child.GetLooseScale or not child.SetScale then return end
            local _,height=child:GetSize()
            local _,sy=child:GetLooseScale()
            if height==0 or sy==0 then return end
            resize[#resize+1]={widget=child}
            found[texture]=(found[texture] or 0)+1
        end
    end
    if found["top.tex"]~=1 or found["bottom.tex"]~=1
        or found["backing.tex"]~=1 or found["side.tex"]~=2 then return end
    return {move=move,resize=resize}
end

local function set_layout(state,active)
    local direction=active and 1 or -1
    for _,entry in ipairs(state.layout.move) do shift(entry[1],entry[2]*direction*ROW_HEIGHT/2) end
    for _,entry in ipairs(state.layout.resize) do
        local widget=entry.widget
        local sx,sy,sz=widget:GetLooseScale()
        if active then
            local _,height=widget:GetSize()
            entry.factor=1+ROW_HEIGHT/math.abs(height*sy)
        end
        widget:SetScale(sx,sy*(active and entry.factor or 1/entry.factor),sz)
    end
end

local function restore_focus(state)
    for _,link in ipairs(state.links or {}) do
        if link.widget.focus_flow[link.dir]==link.route then
            link.widget.focus_flow[link.dir]=link.old
            link.widget.focus_flow_args[link.dir]=link.args
            if link.widget.next_in_tab_order==link.route then link.widget.next_in_tab_order=link.next end
        end
    end
    state.links={}
end

local function set_focus(menu,state,G)
    restore_focus(state)
    for _,entry in ipairs({{menu.recipe_grid,G.MOVE_UP},{menu.filter_panel.filter_grid,G.MOVE_DOWN}}) do
        local widget,dir=entry[1],entry[2]
        local route=function() return state.spinner end
        state.links[#state.links+1]={widget=widget,dir=dir,old=widget.focus_flow[dir],
            args=widget.focus_flow_args[dir],next=widget.next_in_tab_order,route=route}
        widget:SetFocusChangeDir(dir,route)
    end
end

function M.attach(menu,G)
    if menu.nw_class_filter or not menu.filter_panel or not menu.filter_panel.filter_grid
        or not menu.UpdateRecipeGrid or not menu.ApplyFilters or not menu.Refresh
        or not menu.DoFocusHookups then return end
    local geometry=layout(menu)
    if not geometry then return end -- A replaced menu retains its own UI unmodified.
    for _,widget in ipairs({menu.recipe_grid,menu.filter_panel.filter_grid}) do
        if not widget.SetFocusChangeDir or not widget.focus_flow or not widget.focus_flow_args then return end
    end
    local T=require("nw/locale").t
    local Filters=require("widgets/nw_craftingfilters")
    local state={layout=geometry,choices={},tags={},links={}}
    menu.nw_class_filter=state
    function state:selection()
        local station=self.station
        if not station then return {} end
        local choice=self.choices[station] or "all"
        self.tags[station]=self.tags[station] or {}
        self.tags[station][choice]=self.tags[station][choice] or {}
        return self.tags[station][choice]
    end
    function state:refresh_controls()
        local choice=self.choices[self.station] or "all"
        local options=M.class_options(self.station)
        local valid=false
        for _,option in ipairs(options) do if option.data==choice then valid=true;break end end
        if not valid then
            choice="all"
            if self.station then self.choices[self.station]=choice end
        end
        self.root:SetChoices(options)
        self.root:SetChoice(choice)
        self.root:SetTags(self.station and M.tags(self.station,choice) or {},self:selection())
    end
    function state:reset_session()
        self.choices={};self.tags={}
        self:refresh_controls()
    end
    state.root=menu.frame:AddChild(Filters({
        {text=T("全部配方"),data="all"},{text=T("基础法术"),data="basic"},
        {text=T("法术修饰"),data="modifier"},{text=T("施法控制"),data="control"},
    },function(choice)
        state:sync()
        if not state.station or not classes[choice] then return end
        local valid=false
        for _,option in ipairs(M.class_options(state.station)) do if option.data==choice then valid=true;break end end
        if not valid then state:refresh_controls();return end
        state.choices[state.station]=choice
        state:refresh_controls()
        menu:ApplyFilters()
    end,function(tag)
        state:sync()
        if not state.station then return end
        local valid=false
        for _,option in ipairs(M.tags(state.station,state.choices[state.station] or "all")) do
            if option.id==tag then valid=true;break end
        end
        if not valid then return end
        local selected=state:selection()
        local enable=not selected[tag]
        for id in pairs(selected) do selected[id]=nil end
        if enable then selected[tag]=true end
        state:refresh_controls()
        menu:ApplyFilters()
    end))
    state.spinner=state.root.spinner
    state.root:Hide()
    state.root:SetNavigation(menu.filter_panel.filter_grid,function()
        return #menu.filtered_recipes>0 and menu.recipe_grid or menu.filter_panel.filter_grid
    end)

    function state:sync()
        local station=M.station(menu)
        local changed=station~=self.station
        if station and not self.active then
            local p=menu.itemlist_split:GetPosition()
            self.root:SetPosition(0,p.y,p.z)
            set_layout(self,true)
            self.active=true
            self.root:Show()
            set_focus(menu,self,G)
        elseif not station and self.active then
            if self.root:HasFilterFocus() then
                self.root:ClearFocus()
                if menu.crafting_hud:IsCraftingOpen() then menu.filter_panel.filter_grid:SetFocus() end
            end
            restore_focus(self)
            self.root:Hide()
            set_layout(self,false)
            self.active=false
        end
        self.station=station
        if changed then self:refresh_controls() end
        return changed
    end

    local update=menu.UpdateRecipeGrid
    menu.UpdateRecipeGrid=function(self,set_focus,...)
        state:sync()
        local source=self.filtered_recipes==state.filtered and state.source or self.filtered_recipes
        local choice=state.choices[state.station] or "all"
        local filtered=M.filter(source,state.station,choice,state:selection())
        state.source,state.filtered=source,filtered
        self.filtered_recipes=filtered
        -- Native mouse refresh does not clear a detail whose recipe disappeared.
        local selected=self.details_root.data
        if selected and state.station and (choice~="all" or next(state:selection())) then
            local present=false
            for _,data in ipairs(filtered) do if data==selected then present=true;break end end
            if not present then self.details_root:PopulateRecipeDetailPanel(nil,nil) end
        end
        if state.active and state.root:HasFilterFocus() then set_focus=false end
        return update(self,set_focus,...)
    end
    local refresh=menu.Refresh
    menu.Refresh=function(self,...)
        refresh(self,...)
        if state:sync() then self:ApplyFilters() end
    end
    local focus=menu.DoFocusHookups
    menu.DoFocusHookups=function(self,...)
        restore_focus(state)
        focus(self,...)
        if state.active then set_focus(self,state,G) end
    end
    local help=menu.RefreshCraftingHelpText
    if help then
        menu.RefreshCraftingHelpText=function(self,...)
            if state.active and state.root:HasFilterFocus() then return state.root:GetHelpText() end
            return help(self,...)
        end
    end
end

function M.install(env,G)
    if G.TheNet:IsDedicated() or env.GetModConfigData("crafting_class_filter",true)==false then return end
    env.AddClassPostConstruct("widgets/redux/craftingmenu_widget",function(menu) M.attach(menu,G) end)
    env.AddClassPostConstruct("widgets/redux/craftingmenu_hud",function(hud)
        local menu=hud.craftingmenu
        if not menu or not menu.nw_class_filter then return end
        -- Native Open marks is_open only AFTER opening the recipe page.
        for _,method in ipairs({"Open","Close"}) do
            local original=hud[method]
            hud[method]=function(self,...)
                original(self,...)
                if method=="Close" then menu.nw_class_filter:reset_session() end
                if menu.nw_class_filter:sync() then menu:ApplyFilters() end
            end
        end
    end)
end
return M
