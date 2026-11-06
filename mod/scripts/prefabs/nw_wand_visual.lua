local Visual = require("nw/visual")
local assets = {Asset("ANIM", "anim/nw_parts.zip")}
local function refresh(inst)
    if inst._local_visual then Visual.apply(inst._local_visual, inst._look:value(), "held") end
end
local function attach(inst)
    local parent = inst.entity:GetParent()
    if not parent then return false end
    local child = CreateEntity()
    child.entity:AddTransform()
    child.entity:AddAnimState()
    child.entity:AddFollower()
    child:AddTag("FX")
    child.persists = false
    child.entity:SetParent(parent.entity)
    child.Follower:FollowSymbol(parent.GUID, "swap_object", 0, 0, 0, true)
    child.AnimState:SetFinalOffset(1)
    inst._local_visual = child
    refresh(inst)
    return true
end
local function fn()
    local inst = CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddNetwork()
    inst:AddTag("FX")
    inst._look = net_ushortint(inst.GUID, "nw_visual.look", "nw_visualdirty")
    inst.entity:SetPristine()
    inst.persists = false
    if not TheNet:IsDedicated() then
        inst:ListenForEvent("nw_visualdirty", refresh)
        inst._attach_task = inst:DoPeriodicTask(.1, function()
            if attach(inst) then inst._attach_task:Cancel(); inst._attach_task = nil end
        end, 0)
        inst:ListenForEvent("onremove", function()
            if inst._local_visual then inst._local_visual:Remove(); inst._local_visual = nil end
        end)
    end
    return inst
end
return Prefab("nw_wand_visual", fn, assets)
