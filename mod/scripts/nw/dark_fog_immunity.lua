local C = require("nw/constants/dark_fog").control
local M = {}
-- Server-only transient state, independent of the world's current cloud pool.
-- Weak keys and lazy deadlines need neither save data nor per-creature timers.
local records = setmetatable({}, { __mode = "k" })
local function detach(inst, record)
    if record.events and inst.RemoveEventCallback then
        for event, fn in pairs(record.events) do inst:RemoveEventCallback(event, fn) end
        record.events = nil
    end
end
function M.clear(inst)
    local record = records[inst]
    if record then detach(inst, record); records[inst] = nil end
end
function M.is_immune(inst, now)
    local record = records[inst]
    if record and (not inst:IsValid() or inst.components.health and inst.components.health:IsDead()) then
        M.clear(inst)
        return false
    end
    if not record or not record.until_time then return false end
    if (now or GetTime()) < record.until_time then return true end
    M.clear(inst)
    return false
end
function M.leave(inst, now)
    local record = records[inst]
    if not record or not record.affected then return end
    detach(inst, record)
    if not inst:IsValid() or inst.components.health and inst.components.health:IsDead() then
        records[inst] = nil
        return
    end
    record.affected = nil
    record.until_time = (now or GetTime()) + C.exit_immunity
end
function M.mark(inst, now)
    if M.is_immune(inst, now) then return false end
    if records[inst] then return true end
    local record = { affected = true, events = {} }
    records[inst] = record
    -- Native Boss hits can acquire coverage between the shared scan ticks.
    -- Include them in the union's exit cleanup even if this hit removes all fog.
    local pool = TheWorld and TheWorld._nw_dark_fog
    if pool then pool.members[inst] = true end
    if inst.ListenForEvent then
        for _, event in ipairs({ "death", "onremove", "entitysleep" }) do
            local fn = event == "entitysleep" and function(owner) M.leave(owner) end
                or function(owner) M.clear(owner) end
            record.events[event] = fn
            inst:ListenForEvent(event, fn)
        end
    end
    return true
end
return M
