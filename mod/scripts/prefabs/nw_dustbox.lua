local storage=require("nw/arcane_storage")
local atlas=storage.atlas
local assets={Asset("ANIM","anim/nw_dustbox.zip"),Asset("ANIM","anim/ui_chest_1x1.zip"),
    Asset("ATLAS",atlas),Asset("IMAGE","images/inventoryimages/nw_arcane_storage.tex")}

local function play(inst,animation,loop)
    if inst._dustbox_animation~=animation then
        inst._dustbox_animation=animation
        inst.AnimState:PlayAnimation(animation,loop or false)
    end
end

local function refresh(inst,state)
    local box=inst.components.container
    state=state or storage.StateForCount(storage.Count(box))
    inst._dustbox_fill=state
    local opened=box:IsOpen()
    inst.components.inventoryitem:ChangeImageName(opened and "nw_dustbox_open_"..state or "nw_dustbox")

    if inst.components.inventoryitem.owner~=nil then
        -- Inventory entities may sleep in limbo. Their UI changes immediately;
        -- do not wait for an invisible animation before resolving the pose.
        inst._dustbox_phase=opened and "opened" or "closed"
        play(inst,inst._dustbox_phase.."_"..state,opened)
    elseif inst._dustbox_phase=="opening" or inst._dustbox_phase=="closing" then
        -- Item/stack events only change the destination while the lid moves.
        -- Likewise, a rapid reopen/close finishes this motion before reversing.
        return
    elseif opened and inst._dustbox_phase~="opened" then
        inst._dustbox_phase="opening"
        play(inst,"open_"..state)
    elseif not opened and inst._dustbox_phase~="closed" then
        inst._dustbox_phase="closing"
        play(inst,"close_"..state)
    else
        play(inst,(opened and "opened_" or "closed_")..state,opened)
    end
end

local function onanimover(inst)
    if inst._dustbox_phase=="opening" then
        inst._dustbox_phase="opened"
    elseif inst._dustbox_phase=="closing" then
        inst._dustbox_phase="closed"
    else
        return
    end
    -- Read the latest count and openers instead of queuing a stale idle pose.
    refresh(inst)
end

local function onwake(inst)
    if (inst._dustbox_phase=="opening" or inst._dustbox_phase=="closing")
        and inst.AnimState:AnimDone() then
        -- A finished motion may have slept through its completion event.
        onanimover(inst)
    else
        refresh(inst)
    end
end

local function onopen(inst)
    refresh(inst)
    inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/tacklebox/small_open")
end
local function onclose(inst)
    refresh(inst)
    inst.SoundEmitter:PlaySound("hookline_2/characters/hermit/tacklebox/small_close")
end
local function onpocket(inst)
    inst.components.container:Close()
    inst._dustbox_phase="closed"
    refresh(inst)
end
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddNetwork()
    MakeInventoryPhysics(inst)
    inst.AnimState:SetBank("nw_dustbox")
    inst.AnimState:SetBuild("nw_dustbox")
    inst.AnimState:PlayAnimation("closed_empty")
    inst.AnimState:SetScale(storage.DUSTBOX_SCALE,storage.DUSTBOX_SCALE)
    inst.AnimState:SetRayTestOnBB(true)
    inst:AddTag("portablestorage")
    inst:AddTag("fireimmune")
    MakeInventoryFloatable(inst,"small",.15,.8*storage.DUSTBOX_SCALE)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end

    inst:AddComponent("inspectable")
    inst:AddComponent("inventoryitem")
    inst.components.inventoryitem.atlasname=atlas
    inst.components.inventoryitem:SetOnPutInInventoryFn(onpocket)
    inst:AddComponent("container")
    local box=inst.components.container
    box:WidgetSetup("nw_dustbox")
    box:EnableInfiniteStackSize(true)
    box.onopenfn=onopen
    box.onclosefn=onclose
    box.skipopensnd=true
    box.skipclosesnd=true
    -- Native RUMMAGE + portablestorage handles inventory/backpack grand owners.
    -- Retain its range/state auto-close and first-open/last-close semantics.
    box.droponopen=false
    inst._dustbox_phase="closed"
    inst._dustbox_animation="closed_empty"
    inst._dustbox_fill="empty"
    inst:ListenForEvent("animover",onanimover)
    inst.OnEntityWake=onwake
    -- Native container save/load restores its stack before this deferred read.
    storage.Watch(inst,refresh)
    MakeHauntableLaunch(inst)
    return inst
end
return Prefab("nw_dustbox",fn,assets,{"nw_dust"})
