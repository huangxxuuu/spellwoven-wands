local C=require("nw/constants/ui").inventory_hint
local T=require("nw/locale").t
local Data=require("nw/hover_data")
local Cards=require("nw/cards")
local M={}
local shared_panel

function M.position(x,y,w,h,sw,sh,radius,scale)
    local margin=C.margin*scale
    x=math.max(w/2+margin,math.min(sw-margin-w/2,x))
    local above,below=sh-y-margin,y-margin
    local gap=math.max(radius+margin,C.gap*scale)
    if above>=h+radius+margin or above>=below then
        return x,math.min(y+gap+h/2,sh-margin-h/2)
    end
    return x,math.max(y-gap-h/2,margin+h/2)
end

local function place(panel,tile,root,halfsize)
    local sw,sh=TheSim:GetScreenSize()
    local pos=tile:GetWorldPosition()
    local scale=root:GetScale()
    local radius=halfsize*tile:GetScale().y
    local space=math.max(pos.y,sh-pos.y)-radius-C.fit_padding*scale.y
    local fit=math.min(1,(sw-C.fit_padding*scale.x)/(panel.width*scale.x),space/(panel.height*scale.y))
    if fit<=0 then root:Hide();return end
    root:Show()
    panel:SetScale(fit)
    local x,y=M.position(pos.x,pos.y,panel.width*scale.x*fit,panel.height*scale.y*fit,sw,sh,radius,scale.y)
    root:SetPosition(x,y,0)
end

function M.setup_root(tile)
    tile:SetHoverText(" ",{bg=false})
    tile.hovertext:Hide()
    tile.hovertext_root:SetClickable(false)
end

local function panel_for(root)
    if not shared_panel or not shared_panel.inst:IsValid() then
        shared_panel=require("widgets/nw_itemhint")()
    end
    local moved=shared_panel.parent~=root
    if moved then root:AddChild(shared_panel) end
    return shared_panel,moved
end

function M.actions(tile)
    if not tile.GetDescriptionString then return "" end
    local description=tile:GetDescriptionString() or ""
    return description:match("\n(.*)") or ""
end
function M.show_card(tile,id,halfsize)
    local root=tile.hovertext_root
    local inv=ThePlayer and ThePlayer.replica.inventory
    local held=inv and inv:GetActiveItem()
    if held and held:HasTag("nw_spellcard") and not tile.item then root:Hide();return end
    local panel,moved=panel_for(root)
    local actions=M.actions(tile)
    local damage_rate=require("nw/base_damage").multiplier
    if moved or panel._nw_spell~=id or panel._nw_actions~=actions or panel._nw_damage_rate~=damage_rate then
        local data=id==false and {title=T("空法术槽")} or Data.card(id)
        if actions~="" then data.title=data.title.."\n"..actions end
        panel:Display(data)
        panel._nw_spell=id;panel._nw_actions=actions;panel._nw_damage_rate=damage_rate
    end
    place(panel,tile,root,halfsize)
end

function M.install(tile,wand)
    local item=tile.item
    M.setup_root(tile)
    tile.UpdateTooltip=function(self) self:SetTooltip(nil) end
    local task,cursor_owner
    local last_stats,last_slots,last_look,last_title
    local function refresh()
        local root=tile.hovertext_root
        if not root then return end
        if not tile.focus or not tile:IsVisible() or not item:IsValid() then root:Hide();return end
        if not wand then
            M.show_card(tile,Cards.bycode[item._spell:value()],C.halfsize)
            return
        end
        local panel,moved=panel_for(root)
        local stats,slots,look=item._nw_stats:value(),item._nw_cards:value(),item._nw_look:value()
        local title=item:GetDisplayName()
        local broken=item._nw_broken and item._nw_broken:value()
        if broken then title=title..T(" · 破损") end
        local actions=M.actions(tile)
        if actions~="" then title=title.."\n"..actions end
        if moved or stats~=last_stats or slots~=last_slots or look~=last_look or title~=last_title then
            local data=Data.wand(stats,slots,look,title)
            data.wand_broken=broken
            if broken then data.icon=require("nw/visual").icon(look,true)..".tex";data.subtitle=T("无法施法：用 5 份奥术粉尘修复") end
            panel:Display(data)
            last_stats,last_slots,last_look,last_title=stats,slots,look,title
        end
        place(panel,tile,root,C.halfsize)
    end
    local function stop()
        if task then task:Cancel();task=nil end
        if cursor_owner then
            tile.inst:RemoveEventCallback("newactiveitem",refresh,cursor_owner)
            cursor_owner=nil
        end
        if tile.hovertext_root then tile.hovertext_root:Hide() end
    end
    local gain,lose=tile.OnGainFocus,tile.OnLoseFocus
    tile.OnGainFocus=function(self)
        gain(self)
        if not wand and ThePlayer and not cursor_owner then
            cursor_owner=ThePlayer
            self.inst:ListenForEvent("newactiveitem",refresh,cursor_owner)
        end
        refresh()
        if not task then task=self.inst:DoPeriodicTask(C.refresh_interval,refresh) end
    end
    tile.OnLoseFocus=function(self) stop();lose(self) end
    local function dirty() if tile.focus then refresh() end end
    tile.inst:ListenForEvent(wand and "nw_wanddirty" or "nw_carddirty",dirty,item)
    if wand then tile.inst:ListenForEvent("nw_lookdirty",dirty,item) end
    tile.inst:ListenForEvent("onremove",stop,item)
end
return M
