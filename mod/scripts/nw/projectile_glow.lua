local C=require("nw/constants/visuals/projectile_glow")
local M={threshold=C.threshold,fade_time=C.fade_time}
local FRAME=C.frame

local function dedicated()
    return TheNet and TheNet:IsDedicated()
end

local function viewer_has_nightvision()
    local player=ThePlayer
    if not player or not player.IsValid or not player:IsValid() then return false end
    local vision=player.components and player.components.playervision
    if vision then return vision:HasNightVision() end
    local inventory=player.replica and player.replica.inventory
    return player:HasTag("canseeindark") or inventory and inventory:EquipHasTag("nightvision")
end

local function ambient_at(fx)
    if viewer_has_nightvision() then return M.threshold end
    local light=0
    if TheSim and TheSim.GetLightAtPoint and fx.Transform and fx.Transform.GetWorldPosition then
        local x,y,z=fx.Transform:GetWorldPosition()
        light=TheSim:GetLightAtPoint(x,y,z) or 0
    end
    local ambient=TheWorld and TheWorld.components and TheWorld.components.ambientlighting
    if ambient then light=math.max(light,ambient:GetVisualAmbientValue()) end
    return math.max(0,light)
end

local function strength(state,light,now)
    if light>0 then
        state.dark_since=nil;state.dark_from=nil
        return math.min(1,light/M.threshold)
    end
    if not state.dark_since then
        state.dark_since=now
        state.dark_from=state.strength or 0
    end
    local elapsed=math.max(0,now-state.dark_since)
    if elapsed>=M.fade_time-.000001 then return 0 end
    return state.dark_from*(1-elapsed/M.fade_time)
end

local function set_material(fx,settings,value)
    local anim=fx.AnimState
    if anim.SetLightOverride then anim:SetLightOverride(value) end
    if anim.ClearBloomEffectHandle then anim:ClearBloomEffectHandle() end
    for _,symbol in ipairs(settings.symbol_bloom or {}) do anim:ClearSymbolBloom(symbol) end
    for _,symbol in ipairs(settings.symbol_light or {}) do anim:SetSymbolLightOverride(symbol,value) end
end

local function set_native_mask(fx,value)
    local anim=fx.AnimState
    anim:OverrideMultColour()
    if value<1 then
        local r,g,b,a=1,1,1,1
        if anim.GetMultColour then r,g,b,a=anim:GetMultColour() end
        anim:OverrideMultColour(r*value,g*value,b*value,value>0 and a or 0)
    end
end

function M.detach(fx)
    local state=fx and fx._nw_projectile_glow
    local pool=state and state.pool
    if not pool then return end
    state.pool=nil
    fx:RemoveEventCallback("onremove",state.onremove)
    state.onremove=nil
    local index=state.index
    local last=pool.items[#pool.items]
    pool.items[index]=last;pool.items[#pool.items]=nil
    if last~=fx then last._nw_projectile_glow.index=index end
    state.index=nil
    if #pool.items==0 then
        pool.task:Cancel()
        pool.world:RemoveEventCallback("onremove",pool.onremove)
        if pool.world._nw_projectile_glows==pool then pool.world._nw_projectile_glows=nil end
    end
end

function M.update(fx,options)
    if not fx or not fx.IsValid or not fx:IsValid() or dedicated() then return end
    local state=fx._nw_projectile_glow
    if not state then state={};fx._nw_projectile_glow=state end
    if options then state.options=options end
    local settings=state.options or {}
    if state.native and not state.ready then return end
    local value=strength(state,ambient_at(fx),GetTime and GetTime() or 0)
    state.strength=value
    if state.native then
        set_native_mask(fx,value)
    else
        set_material(fx,settings,value)
        if settings.local_mask and fx.AnimState.OverrideMultColour then
            fx.AnimState:OverrideMultColour()
        elseif settings.visible==false then
            fx:Hide();state.hidden=true
        elseif state.hidden or settings.manage_visibility then
            fx:Show();state.hidden=nil
        end
    end
    return settings.visible~=false
end

local function tick(world)
    local pool=world._nw_projectile_glows
    if not pool then return end
    for index=#pool.items,1,-1 do
        local fx=pool.items[index]
        if fx:IsValid() then M.update(fx) else M.detach(fx) end
    end
end

local function enter_pool(fx)
    local state=fx._nw_projectile_glow
    if state.pool then return end
    local world=TheWorld
    local pool=world._nw_projectile_glows
    if not pool then
        pool={world=world,items={}}
        world._nw_projectile_glows=pool
        pool.task=world:DoPeriodicTask(FRAME,tick)
        pool.onremove=function()
            for index=#pool.items,1,-1 do M.detach(pool.items[index]) end
        end
        world:ListenForEvent("onremove",pool.onremove)
    end
    state.pool=pool;state.index=#pool.items+1
    pool.items[state.index]=fx
    state.onremove=function() M.detach(fx) end
    fx:ListenForEvent("onremove",state.onremove)
end

function M.prepare_native(fx,native)
    if not fx or not fx:IsValid() then return end
    local settings={}
    if native=="voidcloth_boomerang_proj" then settings.symbol_light={"lightning"} end
    set_material(fx,settings,1)
    if dedicated() then return end
    local state=fx._nw_projectile_glow or {}
    fx._nw_projectile_glow=state
    state.options=settings;state.native=true;state.ready=false
    state.strength=nil;state.dark_since=nil;state.dark_from=nil
    fx.AnimState:OverrideMultColour(1,1,1,0)
end

function M.native(fx)
    if not fx or not fx:IsValid() or dedicated() then return end
    if not fx._nw_projectile_glow then M.prepare_native(fx,fx._nw_native_prefab or fx.prefab) end
    fx._nw_projectile_glow.ready=true
    return M.attach(fx)
end

function M.attach(fx,options)
    local result=M.update(fx,options)
    if result~=nil then enter_pool(fx) end
    return result
end

return M
