local recycle=require("nw/recycle")
local visual=require("nw/furnace_visual")
local assets={Asset("ANIM","anim/nw_stations.zip"),Asset("ANIM","anim/nw_furnace_wave.zip")}
local function furnace_scale(inst) inst.AnimState:SetScale(1.1,1.1) end
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddMiniMapEntity()
    inst.entity:AddLight();inst.entity:AddNetwork()
    MakeObstaclePhysics(inst,.8)
    inst:AddTag("structure");inst:AddTag("nw_disassembler")
    inst.MiniMapEntity:SetIcon("nw_disassembler.tex")
    inst.AnimState:SetBank("nw_stations");inst.AnimState:SetBuild("nw_stations")
    inst.AnimState:PlayAnimation("furnace",true)
    furnace_scale(inst)
    inst.Light:SetRadius(0);inst.Light:SetIntensity(.65);inst.Light:SetFalloff(.7)
    -- Radius zero turns the light off locally; replicated Enable(false) must
    -- not cut a remote client's closing animation short.
    inst.Light:SetColour(.28,.82,1);inst.Light:Enable(true)
    inst.Light:EnableClientModulation(true)
    visual.netvars(inst)
    visual.attach(inst)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst:AddComponent("inspectable")
    inst:AddComponent("channelable")
    -- Use the native player channel states with our own contextual action label.
    inst:RemoveTag("channelable")
    inst.components.channelable:SetChannelingFn(recycle.start,recycle.stop)
    inst:AddComponent("lootdropper")
    inst:AddComponent("workable")
    inst.components.workable:SetWorkAction(ACTIONS.HAMMER)
    inst.components.workable:SetWorkLeft(4)
    inst.components.workable:SetOnFinishCallback(function()
        inst.components.lootdropper:DropLoot();inst:Remove()
    end)
    inst:ListenForEvent("onremove",recycle.stop)
    return inst
end
return Prefab("nw_disassembler",fn,assets,{"carnival_sparkle_fx","nw_dust","nw_spellcard"}),
    MakePlacer("nw_disassembler_placer","nw_stations","nw_stations","furnace",nil,nil,nil,nil,nil,nil,furnace_scale)
