local T=require("nw/locale").t
local assets={Asset("ANIM","anim/nw_objects.zip")}
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddNetwork()
    MakeObstaclePhysics(inst,.5)
    inst.AnimState:SetBank("nw_objects");inst.AnimState:SetBuild("nw_objects");inst.AnimState:PlayAnimation("target_dummy")
    inst:AddTag("nw_test_target")
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(1000)
    inst:AddComponent("combat")
    inst.components.combat:SetDefaultDamage(0)
    inst:AddComponent("inspectable")
    inst.components.inspectable.getspecialdescription=function()
        return string.format(T("测试靶生命 %.2f / 1000"),inst.components.health.currenthealth)
    end
    MakeSmallFreezableCharacter(inst)
    MakeSmallBurnableCharacter(inst).fastextinguish=true
    return inst
end
return Prefab("nw_target_dummy",fn,assets,{"character_fire"})
