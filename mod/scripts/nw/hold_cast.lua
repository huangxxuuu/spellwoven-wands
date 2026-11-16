local C=require("nw/constants/casting")
local Cast = require("nw/cast_action")
local Mode = require("nw/cast_mode")
local Pose = require("nw/hold_pose")
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
    local held, retry_at, instant_tick

    local function update_pose()
        local p = pc.inst
        local w = Mode.enabled() and held or nil
        if w and (moving(pc) or pc:IsBusy() or p:GetBufferedAction()
            or (pc.locomotor and pc.locomotor.bufferedaction)) then w = nil end
        local pos
        if w then
            local act = pc:GetRightMouseAction()
            if act and (act.action ~= ACTIONS.NW_CAST or act.invobject ~= w) then
                w = nil
            else
                -- Even an empty/cooling wand has a hold pose and an aim point.
                pos = act and Cast.aim_point(act) or TheInput:GetWorldPosition()
            end
        end
        Pose.update(pc,w,pos)
    end

    local function try_cast()
        local w, p = held, pc.inst
        local instant = Mode.enabled()
        if state_tag(p,"attack") or (not instant and not w._nw_cancast:value()) then
            retry_at = nil
            return
        end
        if moving(pc) or pc:IsBusy() or p:GetBufferedAction()
            or (pc.locomotor and pc.locomotor.bufferedaction) then return end
        if instant then
            -- Readiness replication is not a per-shot acknowledgement. Keep
            -- requests bounded even when zero-cooldown casts never toggle it.
            if instant_tick == GetTick() then return end
        elseif retry_at and GetTime() < retry_at then return end
        local act = pc:GetRightMouseAction()
        if not act or act.action ~= ACTIONS.NW_CAST or act.invobject ~= w then return end
        if not Cast.available(w,p,Cast.aim_point(act)) then return end
        if instant then
            instant_tick = GetTick()
        else
            retry_at = GetTime() + C.hold_retry_delay + (pc.ismastersim and 0 or math.max(0,TheNet:GetAveragePing()) * C.ping_retry_factor)
        end
        click(pc,true)
    end

    pc.OnRightClick = function(self,down)
        held, retry_at = nil, nil
        if self.inst._nw_hud_dragging then Pose.update(self,nil);return end
        if down and world_input(self) then
            local w, act = Cast.hand(self.inst), self:GetRightMouseAction()
            if w and (not act or (act.action == ACTIONS.NW_CAST and act.invobject == w)) then
                held = w
                update_pose()
                try_cast()
                return
            end
        end
        Pose.update(self,nil)
        return click(self,down)
    end

    pc.OnUpdate = function(self,dt)
        update(self,dt)
        if not held then return end
        if not TheInput:IsControlPressed(CONTROL_SECONDARY) or not world_input(self)
            or not held:IsValid() or Cast.hand(self.inst) ~= held then
            held, retry_at = nil, nil
            Pose.update(self,nil)
            return
        end
        update_pose()
        try_cast()
    end
end

return M
