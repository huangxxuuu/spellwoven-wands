require("prefabutil")

local storage = require("nw/arcane_storage")
local assets = {
    Asset("ANIM", "anim/nw_emberlamp.zip"),
    Asset("ANIM", "anim/ui_chest_1x1.zip"),
    Asset("ATLAS", storage.atlas),
    Asset("IMAGE", "images/inventoryimages/nw_arcane_storage.tex"),
}
local prefabs = { "nw_dust", "collapse_small" }
local BURN_PERIOD = 1

local function ScaleLamp(inst)
    -- Match the Alchemy Engine's height; share the same visual with its placer.
    inst.AnimState:SetScale(storage.LAMP_SCALE, storage.LAMP_SCALE)
end

local function Play(inst, animation, loop)
    if inst._nw_animation ~= animation then
        inst._nw_animation = animation
        inst.AnimState:PlayAnimation(animation, loop or false)
    end
end

local function ShowIdle(inst)
    inst._nw_transition = nil
    Play(inst, (inst._nw_lit and "burn_" or "off_")..inst._nw_fuelstate, inst._nw_lit)
end

local function UpdateLight(inst)
    if inst._nw_lit and inst._nw_fuelstate ~= "empty" then
        inst._nw_lastlitstate = inst._nw_fuelstate
    end
    inst.Light:SetRadius(inst._nw_fuelstate == "full"
        and storage.LIGHT.full_radius or storage.LIGHT.half_radius)
    inst.Light:Enable(inst._nw_lit)
end

local function StopBurnTask(inst)
    if inst._nw_burntask then
        inst._nw_burntask:Cancel()
        inst._nw_burntask = nil
    end
end

local function RefreshFuel(inst, state, count)
    if inst._nw_removing then return end
    inst._nw_fuelstate = state
    if count == 0 then
        inst:AddTag("fueldepleted")
        if inst._nw_lit then
            inst.components.machine:TurnOff()
        end
    else
        inst:RemoveTag("fueldepleted")
    end
    UpdateLight(inst)
    if not inst._nw_transition then ShowIdle(inst) end
end

local function BurnElapsed(inst, dt, settledebt)
    if (not inst._nw_lit and not settledebt) or dt < 0 or inst._nw_removing then return end
    local container = inst.components.container
    local count = storage.Count(container)
    if count == 0 then
        -- The last item can be withdrawn between ticks. Keep those lit seconds
        -- too, so repeated brief withdrawal/refill cycles cannot reset the bill.
        inst._nw_burnprogress = inst._nw_burnprogress + dt
        inst._nw_storage_refresh()
        return
    end

    -- A unit remains in the tray until its 60 lit seconds have elapsed.
    -- Pausing or removing the contents keeps the partial clock, not hidden fuel.
    local elapsed = inst._nw_burnprogress + dt
    local spent = math.min(count, math.floor(elapsed / storage.DUST_SECONDS))
    -- Ordinary exhaustion discards future unlit time. Debt represents light
    -- already provided, so even its fractional remainder survives repayment.
    inst._nw_burnprogress = spent == count and not settledebt
        and 0 or elapsed - spent * storage.DUST_SECONDS
    if spent > 0 then
        local item = container:GetItemInSlot(1)
        if spent < count then
            item.components.stackable:SetStackSize(count - spent)
        else
            -- Native whole-stack removal ejects overstacked excess. Reduce it
            -- first, then consume the last unit through the original container.
            if item.components.stackable then item.components.stackable:SetStackSize(1) end
            container:ConsumeByName("nw_dust", 1)
        end
        inst._nw_storage_refresh()
    end
end

local function SettleClock(inst)
    if inst._nw_settling then return end
    local now = GetTime()
    local previous = inst._nw_lastburntime
    inst._nw_lastburntime = inst._nw_lit and now or nil
    if inst._nw_lit and previous then
        inst._nw_settling = true
        BurnElapsed(inst, math.max(0, now - previous))
        inst._nw_settling = nil
    end
end

local function StartBurnTask(inst)
    if inst._nw_burntask == nil then
        -- Like stock fueled, this task keeps ticking while the entity sleeps.
        inst._nw_burntask = inst:DoPeriodicTask(BURN_PERIOD, SettleClock)
    end
end

local function TurnOn(inst)
    if inst._nw_lit or storage.Count(inst.components.container) == 0 then return end
    inst._nw_storage_refresh()
    inst._nw_lit = true
    inst._nw_lastburntime = GetTime()
    inst._nw_transition = "ignite"
    Play(inst, "ignite_"..inst._nw_fuelstate)
    UpdateLight(inst)
    StartBurnTask(inst)
    if not POPULATING and not inst:IsAsleep() then
        inst.SoundEmitter:PlaySound("dontstarve/wilson/lantern_on")
    end
end

local function TurnOff(inst)
    local waslit = inst._nw_lit
    inst._nw_lit = false
    inst._nw_lastburntime = nil
    StopBurnTask(inst)
    UpdateLight(inst)
    if waslit then
        -- The tray may just have become empty; extinguish the previous flame.
        local state = inst._nw_lastlitstate or "half"
        inst._nw_transition = "extinguish"
        Play(inst, "extinguish_"..state)
        if not POPULATING and not inst:IsAsleep() then
            inst.SoundEmitter:PlaySound("dontstarve/wilson/lantern_off")
        end
    else
        ShowIdle(inst)
    end
end

local function OnLongUpdate(inst, dt)
    -- LongUpdate supplies skipped game time in addition to ordinary sim time.
    SettleClock(inst)
    BurnElapsed(inst, math.max(0, dt))
    inst._nw_lastburntime = inst._nw_lit and GetTime() or nil
    ShowIdle(inst)
end

local function OnWake(inst)
    SettleClock(inst)
    inst._nw_storage_refresh()
    -- animover may have occurred while the entity was out of the active scene.
    ShowIdle(inst)
end

local function OnSave(inst, data)
    SettleClock(inst)
    data.nw_burnprogress = inst._nw_burnprogress
    data.nw_lit = inst._nw_lit
    -- Components save in unspecified order. This is the final, settled state.
    data.machine = { ison = inst._nw_lit }
end

local function OnLoad(inst, data)
    StopBurnTask(inst)
    local progress = data and tonumber(data.nw_burnprogress) or 0
    inst._nw_burnprogress = math.max(0, progress or 0)
    local restore = data and data.nw_lit
    if restore == nil then restore = inst._nw_restore_on end
    inst._nw_restore_on = nil
    inst._nw_lit = false
    inst._nw_storage_refresh()
    inst._nw_lit = restore == true and storage.Count(inst.components.container) > 0
    inst.components.machine.ison = inst._nw_lit
    inst._nw_lastburntime = inst._nw_lit and GetTime() or nil
    UpdateLight(inst)
    ShowIdle(inst)
    if inst._nw_lit then StartBurnTask(inst) end
end

local function OnHammered(inst)
    SettleClock(inst)
    inst._nw_removing = true
    StopBurnTask(inst)
    inst.components.container:Close()
    inst.components.container:DropEverything()
    inst.components.lootdropper:DropLoot()
    local fx = SpawnPrefab("collapse_small")
    if fx then
        fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
        fx:SetMaterial("stone")
    end
    inst:Remove()
end

local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddLight()
    inst.entity:AddMiniMapEntity()
    inst.MiniMapEntity:SetIcon("nw_emberlamp.tex")
    inst.entity:AddNetwork()

    MakeObstaclePhysics(inst, storage.LAMP_COLLISION_RADIUS)
    inst.AnimState:SetBank("nw_emberlamp")
    inst.AnimState:SetBuild("nw_emberlamp")
    inst.AnimState:PlayAnimation("off_empty")
    ScaleLamp(inst)
    inst:AddTag("structure")
    inst:AddTag("light")
    inst:AddTag("wildfireprotected")
    inst:AddTag("fueldepleted")
    -- Ground contact and stone shadows are already painted into the build.
    inst.Light:SetIntensity(storage.LIGHT.intensity)
    inst.Light:SetFalloff(storage.LIGHT.falloff)
    inst.Light:SetColour(unpack(storage.LIGHT.colour))
    inst.Light:SetRadius(storage.LIGHT.half_radius)
    inst.Light:Enable(false)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst._nw_fuelstate = "empty"
    inst._nw_lit = false
    inst._nw_burnprogress = 0
    inst._nw_animation = "off_empty"
    inst:AddComponent("inspectable")
    inst:AddComponent("container")
    local container = inst.components.container
    container:WidgetSetup("nw_emberlamp")
    container:EnableInfiniteStackSize(true)
    local savecontainer = container.OnSave
    container.OnSave = function(self, ...)
        -- Settle before taking the item snapshot, never after serializing it.
        SettleClock(self.inst)
        return savecontainer(self, ...)
    end

    inst:AddComponent("machine")
    local machine = inst.components.machine
    machine.turnonfn = TurnOn
    machine.turnofffn = TurnOff
    machine.cooldowntime = .75
    machine:SetGroundOnlyMachine(true)
    local machineturnon, machineturnoff = machine.TurnOn, machine.TurnOff
    machine.TurnOn = function(self, ...)
        -- Stock TurnOn calls its callback before writing ison, and direct
        -- actions do not check CanInteract. Guard before entering that method.
        if inst._nw_removing or self:IsOn() or storage.Count(container) == 0 then return false end
        -- A withdrawal can cross a minute boundary before the next tick. Pay
        -- that already-used time before lighting newly inserted dust.
        BurnElapsed(inst, 0, true)
        if storage.Count(container) == 0 then return false end
        machineturnon(self, ...)
        return true
    end
    machine.TurnOff = function(self, ...)
        SettleClock(inst)
        if not inst._nw_lit and not self:IsOn() then return false end
        machineturnoff(self, ...)
        return true
    end
    machine.OnLoad = function(self, data)
        -- Container restoration order is unspecified; prefab OnLoad runs last.
        inst._nw_restore_on = data and data.ison == true
    end

    inst:AddComponent("lootdropper")
    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnFinishCallback(OnHammered)
    inst:ListenForEvent("animover", function()
        if inst._nw_transition then ShowIdle(inst) end
    end)
    inst:ListenForEvent("onremove", StopBurnTask)
    inst.OnSave = OnSave
    inst.OnLoad = OnLoad
    inst.OnLongUpdate = OnLongUpdate
    inst.OnEntitySleep = SettleClock
    inst.OnEntityWake = OnWake
    storage.Watch(inst, RefreshFuel)
    return inst
end

return Prefab("nw_emberlamp", fn, assets, prefabs),
    MakePlacer("nw_emberlamp_placer", "nw_emberlamp", "nw_emberlamp", "off_empty",
        nil, nil, nil, nil, nil, nil, ScaleLamp)
