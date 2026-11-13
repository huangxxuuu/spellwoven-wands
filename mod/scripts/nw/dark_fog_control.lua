-- Server-only, transient control shared by every fog source in this world.
-- The manager supplies UNION coverage; no source owns an individual brain stop.
local Profiles = require("nw/dark_fog_profiles")
local M = { radius = 3, fear_time = 1, blind_time = .8, shadow_speed = 1.25 }
local REASON = "nw_fog_control"
local fear_cooldowns = setmetatable({}, { __mode = "k" })
local lifecycle = { "onremove", "death", "entitysleep" }

M.classify = Profiles.classify

local function tagged(inst, tag)
    return inst.sg ~= nil and inst.sg:HasStateTag(tag)
end

local function disabled(inst)
    local c = inst.components
    return (inst.IsAsleep and inst:IsAsleep())
        or (c.sleeper and c.sleeper:IsAsleep())
        or (c.freezable and c.freezable:IsFrozen())
        or (c.petrifiable and c.petrifiable.IsPetrified and c.petrifiable:IsPetrified())
        or (c.rideable and c.rideable:IsBeingRidden())
        or tagged(inst, "sleeping") or tagged(inst, "frozen")
        or tagged(inst, "petrified") or tagged(inst, "statue")
        or tagged(inst, "knockback") or tagged(inst, "knockout")
        or tagged(inst, "sinking") or tagged(inst, "drowning")
        or tagged(inst, "jumping") or tagged(inst, "flight")
        or tagged(inst, "transform")
end

local function busy(inst)
    return tagged(inst, "busy") or tagged(inst, "attack") or disabled(inst)
end

local function near(inst, target)
    -- Only the proximity query sees a lost target, never the steering code.
    return target ~= nil and target:IsValid() and not target:HasTag("INLIMBO")
        and inst:IsNear(target, M.radius)
end

local function allowed(inst, state, target)
    return target == nil or (state.kind == "normal" and near(inst, target))
end

local function install_filters(inst, state)
    local combat = inst.components.combat
    if not combat then return end
    state.combat = combat
    state.hooks = {}
    for _, name in ipairs({ "SetTarget", "CanTarget", "CanAttack" }) do
        local original = combat[name]
        if original then
            local wrapper = function(self, target, ...)
                if state.active and not allowed(inst, state, target) then
                    return false
                end
                return original(self, target, ...)
            end
            state.hooks[name] = { original = original, wrapper = wrapper }
            combat[name] = wrapper
        end
    end
end

local function uninstall_filters(state)
    if state.hooks then
        for name, hook in pairs(state.hooks) do
            -- Do not overwrite a later mod's wrapper. Ours becomes a passthrough
            -- even if another mod retained it in its own closure.
            if state.combat[name] == hook.wrapper then
                state.combat[name] = hook.original
            end
        end
    end
    state.hooks = nil
end

local function clear_intent(inst, state)
    if busy(inst) then return false end
    local locomotor = inst.components.locomotor
    locomotor:Stop() -- cancels destination/path, NOT buffered actions
    if locomotor.SetBufferedAction then locomotor:SetBufferedAction(nil) end
    if inst.ClearBufferedAction then inst:ClearBufferedAction() end
    state.moving = false
    state.needs_clear = false
    return true
end

local function deactivate(inst, state)
    state.active = false
    uninstall_filters(state)
    local live = not state.removing and inst:IsValid()
    if state.speed then
        if live then inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, REASON) end
        state.speed = nil
    end
    if state.stopped_brain then
        -- EntityScript removes an entity from BrainManager before onremove.
        -- Restarting here would reinsert a retiring brain into that manager.
        if live then inst:RestartBrain(REASON) end
        state.stopped_brain = nil
    end
end

function M.leave(inst)
    if not inst then return end
    local state = inst._nw_dark_control
    if not state then
        if inst._nw_fog_boss_covered or inst._nw_fog_boss_cast or inst._nw_fog_boss_wait then
            require("nw/dark_fog_boss").leave(inst)
        end
        return
    end
    if state.kind == "large" then
        require("nw/dark_fog_boss").leave(inst)
        return
    end
    if state.moving and not state.removing and inst:IsValid() and not busy(inst) then
        inst.components.locomotor:Stop()
    end
    deactivate(inst, state)
    inst._nw_dark_control = nil
    if state.onleave and inst.RemoveEventCallback then
        for _, event in ipairs(lifecycle) do
            inst:RemoveEventCallback(event, event == "onremove" and state.onremove or state.onleave)
        end
    end
end

local function activate(inst, state)
    state.active = true
    if state.kind == "shadow" then
        local loco = inst.components.locomotor
        if loco then
            loco:SetExternalSpeedMultiplier(inst, REASON, M.shadow_speed)
            state.speed = true
        else
            state.speed_unavailable = true
        end
        return
    end
    inst:StopBrain(REASON)
    state.stopped_brain = true
    install_filters(inst, state)
    local combat = inst.components.combat
    if combat then combat:SetTarget(nil) end
    state.needs_clear = true
    clear_intent(inst, state)
end

local function enter(inst, kind, now)
    local state = { kind = kind, phase = "panic", entered = now, next_search = now }
    if kind == "small" then
        if now >= (fear_cooldowns[inst] or -math.huge) then
            state.phase = "fear_hold"
            state.until_time = now + M.fear_time
            fear_cooldowns[inst] = now + 2
        else
            state.phase = "blind_wander"
        end
    elseif kind == "normal" then
        local combat = inst.components.combat
        -- A former near target is an existing hostility source, not a new enemy
        -- invented by CanTarget. Drop it immediately; recheck on the next tick.
        state.candidate = combat and near(inst, combat.target) and combat.target or nil
    end
    inst._nw_dark_control = state
    state.onleave = function() M.leave(inst) end
    state.onremove = function() state.removing = true; M.leave(inst) end
    if inst.ListenForEvent then
        for _, event in ipairs(lifecycle) do
            inst:ListenForEvent(event, event == "onremove" and state.onremove or state.onleave)
        end
    end
    if not disabled(inst) then activate(inst, state) end
    return state
end

local function safe_walk(inst, state, angle, duration)
    local loco = inst.components.locomotor
    local point = inst:GetPosition()
    local speed = loco.GetWalkSpeed and loco:GetWalkSpeed() or 4
    local distance = math.max(.5, speed * duration + .25)
    local aquatic = loco.IsAquatic and loco:IsAquatic()
    local finder = aquatic and FindSwimmableOffset or FindWalkableOffset
    if not finder then return false end
    local water = loco.CanPathfindOnWater and loco:CanPathfindOnWater() or false
    -- One attempt preserves the remembered heading during blind_continue.
    -- No wall-ignoring fallback and no land->ocean teleport.
    local offset, heading = finder(point, angle, distance, 1, true, false, nil, water)
    if not offset then
        if state.moving then loco:Stop(); state.moving = false end
        return false
    end
    loco:WalkInDirection((heading or angle) * 180 / math.pi)
    state.moving = true
    return true
end

local function wander(inst, state, now)
    if now < (state.next_turn or 0) then return end
    local duration = .25 + math.random() * .25
    state.next_turn = now + duration
    safe_walk(inst, state, math.random() * 2 * math.pi, duration)
end

local function acceptable(combat, inst, target)
    return near(inst, target) and combat:CanTarget(target)
        and (not combat.keeptargetfn or combat.keeptargetfn(inst, target))
end

local function search(inst, state, now)
    local combat = inst.components.combat
    if not combat then return nil end
    if combat.target ~= nil and acceptable(combat, inst, combat.target) then
        return combat.target
    end
    local candidate = state.candidate
    state.candidate = nil
    if candidate and acceptable(combat, inst, candidate) then
        combat:SetTarget(candidate)
        if combat.target then return combat.target end
    end
    if now >= state.next_search then
        state.next_search = now + .25
        -- Native predicates see the CanTarget distance gate while selecting,
        -- so hound/pigman searches skip far priority candidates and continue.
        if combat.targetfn then
            local target = combat.targetfn(inst)
            if target and acceptable(combat, inst, target) then combat:SetTarget(target) end
        end
        local profile = Profiles.get(inst)
        if not combat.target and profile and profile.near_target then
            local target = profile.near_target(inst, M.radius)
            if target and acceptable(combat, inst, target) then combat:SetTarget(target) end
        end
    end
    return combat.target
end

function M.update(inst, now, covered)
    if TheWorld and not TheWorld.ismastersim then return end
    if not covered then M.leave(inst); return end
    local kind = M.classify(inst)
    if not kind then M.leave(inst); return end
    local state = inst._nw_dark_control
    if state and state.kind ~= kind then M.leave(inst); state = nil end
    if kind == "large" then
        require("nw/dark_fog_boss").update(inst, now, covered)
        return
    end
    if not state then enter(inst, kind, now); return end
    if disabled(inst) then
        if state.active then deactivate(inst, state) end
        state.candidate = nil
        state.sensed_target = nil
        state.last_direction = nil
        state.moving = false
        return
    elseif not state.active then
        activate(inst, state)
    end
    if kind == "shadow" then return end

    local combat = inst.components.combat
    local target = combat and combat.target
    if state.sensed_target and not near(inst, state.sensed_target) then
        -- Deliberately retain ONLY the angle sampled while inside perception.
        state.sensed_target = nil
        state.candidate = nil
        state.phase = "blind_continue"
        state.until_time = now + M.blind_time
        state.next_turn = nil
    end
    if target and not allowed(inst, state, target) then combat:SetTarget(nil) end
    if busy(inst) then return end
    if state.needs_clear then clear_intent(inst, state) end

    if kind == "small" then
        if state.phase == "fear_hold" and now < state.until_time then return end
        state.phase = "blind_wander"
        wander(inst, state, now)
        return
    end
    target = search(inst, state, now)
    if target and acceptable(combat, inst, target) then
        local x, _, z = inst.Transform:GetWorldPosition()
        local tx, _, tz = target.Transform:GetWorldPosition()
        state.last_direction = math.atan2(-(tz - z), tx - x)
        state.sensed_target = target
        state.phase = "near_combat"
        if combat:TryAttack(target) then
            -- Do not Stop locomotor after doattack: the native SG owns its move.
            state.moving = false
        else
            safe_walk(inst, state, state.last_direction, .1)
        end
    elseif state.phase == "blind_continue" and now < state.until_time then
        if state.last_direction then safe_walk(inst, state, state.last_direction, .1) end
    else
        state.sensed_target = nil
        state.last_direction = nil
        state.phase = "panic"
        wander(inst, state, now)
    end
end

return M
