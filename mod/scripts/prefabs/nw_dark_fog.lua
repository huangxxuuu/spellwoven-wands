local assets={Asset("IMAGE","fx/miasma.tex"),Asset("SHADER","shaders/vfx_particle.ksh")}
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddNetwork()
    inst._nw_dark_dissipating=net_bool(inst.GUID,"nw_dark_fog.dissipating","nw_dark_fog_dirty")
    inst._nw_dark_radius=net_float(inst.GUID,"nw_dark_fog.radius","nw_dark_fog_size_dirty")
    inst:AddTag("FX");inst:AddTag("NOCLICK")
    inst.entity:SetPristine();inst.persists=false
    if not TheNet:IsDedicated() then
        inst:DoTaskInTime(0,function() require("nw/dark_fog_visual").attach(inst) end)
    end
    return inst
end
local function vfxfn()
    return require("nw/dark_fog_visual").create_emitter()
end
return Prefab("nw_dark_fog",fn,assets,{"nw_dark_fog_vfx"}),
    Prefab("nw_dark_fog_vfx",vfxfn,assets)
