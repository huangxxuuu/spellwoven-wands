local Rules = require("nw/acquisition")
local assets = {Asset("ANIM","anim/nw_supplies.zip"), Asset("ATLAS",Rules.atlas),
    Asset("IMAGE","images/inventoryimages/nw_supplies.tex")}
local function material(id, spec)
    return Prefab(id,function()
        local inst = CreateEntity()
        inst.entity:AddTransform()
        inst.entity:AddAnimState()
        inst.entity:AddNetwork()
        MakeInventoryPhysics(inst)
        inst.AnimState:SetBank("nw_supplies")
        inst.AnimState:SetBuild("nw_supplies")
        inst.AnimState:PlayAnimation(id)
        if id=="nw_dust" then inst.AnimState:SetRayTestOnBB(true) end
        MakeInventoryFloatable(inst,"small",.1,.8)
        inst.entity:SetPristine()
        if not TheWorld.ismastersim then return inst end
        inst:AddComponent("inventoryitem")
        inst.components.inventoryitem.atlasname = Rules.atlas
        inst:AddComponent("stackable")
        inst.components.stackable.maxsize = spec[3]
        inst:AddComponent("inspectable")
        return inst
    end,assets)
end
local prefabs = {}
for name, spec in pairs(Rules.materials) do table.insert(prefabs, material(name,spec)) end
return unpack(prefabs)
