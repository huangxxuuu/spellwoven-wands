local C=require("nw/constants/casting")
local Cast = require("nw/cast_action")
local Mode = require("nw/cast_mode")
local Pose = require("nw/hold_pose")
local Binding = require("nw/cast_binding")
local Key = require("nw/cast_key")
local Input = require("nw/cast_input")
local M = {}

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
    local get_action=pc.GetRightMouseAction
    local held, held_key, retry_at, instant_tick
    local dispatching,request_action=false,nil

    pc.GetRightMouseAction=function(self)
        if dispatching then return request_action end
        return get_action(self)
    end
    local function dispatch(act,down)
        dispatching,request_action=true,act
        local ok,result=pcall(click,pc,down)
        dispatching,request_action=false,nil
        if not ok then error(result,0) end
        return result
    end
    local function action() return Cast.input_action(pc.inst) end
    local function cancel()
        local washeld=held~=nil
        held,held_key,retry_at=nil,nil,nil
        Pose.update(pc,nil)
        if washeld then dispatch(nil,false) end
        return washeld
    end
    pc._nw_cast_key_cancel=cancel

    local function update_pose()
        local p = pc.inst
        local w = Mode.enabled() and held or nil
        if w and (moving(pc) or pc:IsBusy() or p:GetBufferedAction()
            or (pc.locomotor and pc.locomotor.bufferedaction)) then w = nil end
        local pos
        if w then
            local act = action()
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
        local act = action()
        if not act or act.action ~= ACTIONS.NW_CAST or act.invobject ~= w then return end
        if not Cast.available(w,p,Cast.aim_point(act)) then return end
        if instant then
            instant_tick = GetTick()
        else
            retry_at = GetTime() + C.hold_retry_delay + (pc.ismastersim and 0 or math.max(0,TheNet:GetAveragePing()) * C.ping_retry_factor)
        end
        dispatch(act,true)
    end

    pc._nw_cast_key_event = function(self,down)
        local washeld=cancel()
        if self.inst._nw_hud_dragging then Pose.update(self,nil);return end
        if down and Binding.ready() and Input.world_input(self) then
            local w, act = Cast.hand(self.inst), action()
            if w and (not act or (act.action == ACTIONS.NW_CAST and act.invobject == w)) then
                held,held_key = w,Binding.get()
                update_pose()
                try_cast()
                return
            end
            -- The right button retains native fallback actions (including
            -- Wortox soul hop) when the wand cannot supply a cast action.
            if w and Binding.get()=="mouse:1001" then return dispatch(act,true) end
        end
        if not down and not washeld then return dispatch(nil,false) end
    end

    pc.OnRightClick = function(self,down)
        if not down then return click(self,false) end
        if self.inst._nw_hud_dragging then Pose.update(self,nil);return end
        if Cast.hand(self.inst) and self:UsingMouse() then
            Pose.update(self,nil)
            -- This is the game's secondary action, not the dedicated cast key.
            -- Its original scene/character action is selected without NW_CAST.
            return dispatch(Cast.input_action(self.inst,true),true)
        end
        return click(self,true)
    end

    pc.OnUpdate = function(self,dt)
        update(self,dt)
        Input.poll(self)
        if not held then return end
        if not Binding.ready() or Binding.get()~=held_key or not Key.down(held_key) or not Input.world_input(self)
            or not held:IsValid() or Cast.hand(self.inst) ~= held then
            cancel()
            return
        end
        update_pose()
        try_cast()
    end
end

return M
