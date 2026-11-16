local C=require("nw/constants/wands").cast
local M={}

local function stop(self)
    if self.updating then
        self.inst:StopUpdatingComponent(self)
        self.updating=false
    end
end
local function noop() end

function M.setup(inst)
    inst:AddComponent("rechargeable")
    local recharge=inst.components.rechargeable
    -- Keep the native itemtile/replica interface, but only nw_wand owns time
    -- and saved state. Native setters may start updates again: stop after sync.
    recharge.OnUpdate=stop
    recharge.LongUpdate=stop
    recharge.OnSave=noop
    recharge.OnLoad=noop
    recharge.GetRechargeTime=function(self) return self.chargetime end
end

function M.sync(wand)
    local inst=wand.inst
    local recharge=inst.components and inst.components.rechargeable
    if not recharge then return end
    local runtime=wand.data.runtime
    local raw_remaining=math.max(runtime.remaining_cast,runtime.remaining_recharge)
    -- Sync can also be called without UpdateTime (editing, naming, etc.).
    -- Extrapolate for display without advancing the authoritative runtime.
    local remaining=math.max(0,raw_remaining-math.max(0,GetTime()-wand.last_time))
    local cooling=remaining>C.cooldown_epsilon
    local total=cooling and math.max(wand.cool_total or 0,raw_remaining) or 0
    local deadline=cooling and (wand.last_time+raw_remaining) or nil
    local changed=recharge._nw_total~=total or (cooling and
        (recharge._nw_runtime~=runtime or not recharge._nw_deadline
            or math.abs(deadline-recharge._nw_deadline)>C.cooldown_epsilon))
    local percent=cooling and (1-remaining/total) or 1
    local charge=recharge.total*percent
    local same=recharge.current==charge
    recharge:SetChargeTime(total)
    recharge:SetCharge(charge,not changed)
    if changed then
        -- SetCharge does not emit when two cycles happen to have equal charge.
        if same then inst:PushEvent("rechargechange",{percent=percent}) end
        local inventoryitem=inst.replica and inst.replica.inventoryitem
        local classified=inventoryitem and inventoryitem.classified
        if classified then
            -- Native ForcePerishDirty pattern: restart client interpolation even
            -- when the new cycle quantizes to the same network percentage.
            local net=classified.recharge
            net:set_local(net:value())
            net:set(net:value())
        end
    end
    recharge._nw_total=total
    recharge._nw_deadline=deadline
    recharge._nw_runtime=runtime
    stop(recharge)
end

return M
