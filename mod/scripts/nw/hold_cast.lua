local Cast = require("nw/cast_action")
local M = {}

local function world_input(pc)
    local p = pc.inst
    return pc.handler and p == ThePlayer and p.HUD and TheFrontEnd:GetActiveScreen() == p.HUD
        and pc:UsingMouse() and pc:IsEnabled() and not IsPaused() and p:IsActionsVisible()
        and not p._nw_editing and not p._nw_hud_dragging and not p:HasTag("playerghost")
        and not pc.placer_recipe and not pc.deployplacer and not pc:IsAOETargeting()
        and not p.replica.inventory:GetActiveItem() and not TheInput:GetHUDEntityUnderMouse()
end

local function state_tag(p, tag)
    if p.sg then return p.sg:HasStateTag(tag) end
    return p:HasTag(tag)
end

local function moving(pc)
    return pc.directwalking or pc.dragwalking or pc.draggingonground or pc.predictwalking
        or TheInput:IsControlPressed(CONTROL_MOVE_UP) or TheInput:IsControlPressed(CONTROL_MOVE_DOWN)
        or TheInput:IsControlPressed(CONTROL_MOVE_LEFT) or TheInput:IsControlPressed(CONTROL_MOVE_RIGHT)
        or TheInput:IsControlPressed(CONTROL_PRIMARY) or state_tag(pc.inst,"moving")
end

function M.install(pc)
    local click, update = pc.OnRightClick, pc.OnUpdate
    local held, retry_at

    local function try_cast()
        local w, p = held, pc.inst
        -- A pending request can outlive the release of the movement key when
        -- prediction is off. Wait for the native attack or replicated cooldown.
        if state_tag(p,"attack") or not w._nw_cancast:value() then
            retry_at = nil
            return
        end
        if moving(pc) or pc:IsBusy() or p:GetBufferedAction()
            or (pc.locomotor and pc.locomotor.bufferedaction) then return end
        if retry_at and GetTime() < retry_at then return end
        local act = pc:GetRightMouseAction()
        if not act or act.action ~= ACTIONS.NW_CAST or act.invobject ~= w then return end
        if not Cast.available(w,p,Cast.aim_point(act)) then return end
        -- The controller rebuilds its mouse actions each update. Submit only the
        -- current wand action, using the game's own host/prediction/no-prediction path.
        retry_at = GetTime() + 1 + (pc.ismastersim and 0 or math.max(0,TheNet:GetAveragePing()) * .002)
        click(pc,true)
    end

    pc.OnRightClick = function(self,down)
        held, retry_at = nil, nil
        if self.inst._nw_hud_dragging then return end
        if down and world_input(self) then
            local w, act = Cast.hand(self.inst), self:GetRightMouseAction()
            if w and (not act or (act.action == ACTIONS.NW_CAST and act.invobject == w)) then
                held = w
                try_cast()
                return
            end
        end
        return click(self,down)
    end

    pc.OnUpdate = function(self,dt)
        update(self,dt)
        if not held then return end
        if not TheInput:IsControlPressed(CONTROL_SECONDARY) or not world_input(self)
            or not held:IsValid() or Cast.hand(self.inst) ~= held then
            held, retry_at = nil, nil
            return
        end
        try_cast()
    end
end

return M
