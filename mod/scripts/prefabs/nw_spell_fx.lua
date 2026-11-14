local C=require("nw/constants/prefabs").spell_fx
local Light=require("nw/constants/modifiers").cards.light
local assets={Asset("ANIM","anim/shock_fx.zip"),Asset("ANIM","anim/nw_electric_arc.zip"),Asset("ANIM","anim/nw_objects.zip"),Asset("ANIM","anim/explode.zip"),Asset("ANIM","anim/swap_spear.zip"),
    Asset("ANIM","anim/swap_glasscutter.zip"),Asset("ANIM","anim/swap_axe.zip")}
local layout=require("nw/fx_layout")
local function setup_arc(inst)
    inst._dx=net_float(inst.GUID,"nw_arc.dx","nw_arcdirty")
    inst._dy=net_float(inst.GUID,"nw_arc.dy","nw_arcdirty")
    inst._dz=net_float(inst.GUID,"nw_arc.dz","nw_arcdirty")
    inst._lift=net_float(inst.GUID,"nw_arc.lift","nw_arcdirty")
    inst._contact=net_entity(inst.GUID,"nw_arc.contact","nw_arcdirty")
    inst._shockanim=net_string(inst.GUID,"nw_arc.shockanim","nw_arcdirty")
    local refresh=require("nw/electric_visual").attach(inst)
    if TheWorld.ismastersim then
        inst.SetSpan=function(_,dx,dz,target,dy,source_visual_lift)
            inst._dx:set(dx);inst._dy:set(dy or 0);inst._dz:set(dz)
            inst._lift:set(source_visual_lift or 0)
            if target then
                local _,size,height=GetCombatFxSize(target)
                inst._shockanim:set(GetElectrocuteFxAnim(size,height))
                inst._contact:set(target)
            else
                inst._shockanim:set("");inst._contact:set(nil)
            end
            if refresh then refresh() end
        end
    end
end
local function ground_shock()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
    inst:AddTag("FX");inst:AddTag("NOCLICK")
    inst.AnimState:SetBank("shock_fx");inst.AnimState:SetBuild("shock_fx")
    inst.entity:SetCanSleep(false)
    inst.AnimState:PlayAnimation(GetElectrocuteFxAnim("small"))
    inst.AnimState:PushAnimation(GetElectrocuteFxAnim("small").."_pst",false)
    inst.AnimState:SetFinalOffset(C.ground_shock_offset)
    require("nw/projectile_glow").attach(inst)
    inst.entity:SetPristine()
    if TheWorld.ismastersim then
        inst.persists=false
        inst:ListenForEvent("animqueueover",inst.Remove)
    end
    return inst
end
local function silent_explosion()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddNetwork()
    inst.Transform:SetFourFaced();inst:AddTag("FX");inst:AddTag("NOCLICK")
    if not TheNet:IsDedicated() then
        inst:DoTaskInTime(0,function(proxy)
            local fx=CreateEntity()
            fx.entity:AddTransform();fx.entity:AddAnimState();fx.entity:SetCanSleep(false)
            fx:AddTag("FX");fx:AddTag("NOCLICK");fx.persists=false
            fx.Transform:SetFromProxy(proxy.GUID)
            fx.AnimState:SetBank("explode");fx.AnimState:SetBuild("explode")
            fx.AnimState:PlayAnimation("small")
            fx.AnimState:SetLightOverride(1)
            fx:ListenForEvent("animover",fx.Remove)
        end)
    end
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst.persists=false;inst:DoTaskInTime(C.silent_lifetime,inst.Remove)
    return inst
end
local function effect(name,animation,seconds,light)
    return Prefab(name,function()
        local inst=CreateEntity()
        inst.entity:AddTransform()
        if name=="nw_moon_impact_fx" or animation=="blast" then inst.entity:AddSoundEmitter() end
        if animation then
            inst.entity:AddAnimState()
            inst.AnimState:SetBank("nw_objects");inst.AnimState:SetBuild("nw_objects")
            inst.AnimState:PlayAnimation(animation)
            inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
            inst.AnimState:SetLightOverride(C.light_override);inst.AnimState:SetFinalOffset(C.final_offset)
        end
        if light then
            inst.entity:AddLight()
            inst.Light:SetRadius(Light.radius);inst.Light:SetIntensity(C.light_intensity);inst.Light:SetFalloff(C.light_falloff)
            inst.Light:SetColour(unpack(C.light_colour));inst.Light:Enable(true)
        end
        inst.entity:AddNetwork();inst:AddTag("FX");inst:AddTag("NOCLICK")
        if name=="nw_arc_fx" then
            setup_arc(inst)
        elseif name=="nw_moon_impact_fx" then
            if TheWorld.ismastersim then
                inst.SetRadius=function()
                    if inst._nw_burst_started then return end
                    inst._nw_burst_started=true
                    inst.SoundEmitter:PlaySound("dontstarve/common/meteor_impact")
                end
            end
        elseif animation=="blast" then
            inst.AnimState:Hide("blast_extent")
            inst.AnimState:Hide("blast_burst")
            inst._radius=net_float(inst.GUID,"nw_blast.radius","nw_blastradiusdirty")
            local function resize()
                local scale=layout.blast_scale(inst._radius:value())
                inst.AnimState:SetScale(scale,scale)
            end
            local burst=require("nw/burst_visual").attach(inst)
            if TheWorld.ismastersim then
                inst.SetRadius=function(_,radius)
                    inst._radius:set(radius);resize()
                    if inst._nw_burst_started then return end
                    inst._nw_burst_started=true
                    if burst then burst() end
                    inst.SoundEmitter:PlaySound("dontstarve/common/blackpowder_explo",nil,
                        name=="nw_soft_blast_fx" and C.soft_blast_volume or 1)
                end
            else
                inst:ListenForEvent("nw_blastradiusdirty",resize)
                inst:DoTaskInTime(0,resize)
            end
        end
        inst.entity:SetPristine()
        if not TheWorld.ismastersim then return inst end
        inst.persists=false
        if name=="nw_arc_fx" then
            inst:AddComponent("weapon")
            inst.components.weapon:SetElectric()
        end
        if seconds then inst:DoTaskInTime(seconds,inst.Remove) end
        return inst
    end,assets)
end
local weapon_fx=require("nw/weapon_visual")
local effects={Prefab("nw_ground_shock_fx",ground_shock,assets),
    Prefab("nw_silent_explode_small",silent_explosion,assets),
    effect("nw_arc_fx",nil,C.arc_lifetime),effect("nw_heal_fx","heal",C.heal_lifetime),
    effect("nw_blast_fx","blast",C.blast_lifetime),effect("nw_lighter_burst_fx","blast",C.blast_lifetime),effect("nw_afterlight",nil,Light.duration,true),
    effect("nw_moon_impact_fx",nil,C.moon_impact_lifetime),
    effect("nw_soft_blast_fx","blast",C.blast_lifetime),
    effect("nw_crystal_burst_fx","blast",C.blast_lifetime),
    effect("nw_flyinglight",nil,nil,true)}
local function reel_fx(name,build,symbol,anim)
    return Prefab(name,function()
        local inst=CreateEntity()
        inst.entity:AddTransform();inst.Transform:SetFourFaced()
        inst.entity:AddAnimState();inst.entity:AddNetwork()
        inst.AnimState:SetBank("wilson");inst.AnimState:SetBuild("nw_objects")
        inst.AnimState:OverrideSymbol("swap_object",build,symbol)
        inst.AnimState:OverrideSymbol("fishingline",build,"fishingline")
        inst.AnimState:OverrideSymbol("FX_fishing",build,"FX_fishing")
        inst.AnimState:PlayAnimation(anim)
        inst:AddTag("FX");inst:AddTag("NOCLICK");inst.entity:SetPristine()
        if TheWorld.ismastersim then inst.persists=false;inst:ListenForEvent("animover",inst.Remove) end
        return inst
    end,assets)
end
effects[#effects+1]=reel_fx("nw_reel_pond_fx","swap_fishingrod","swap_fishingrod","fish_catch")
effects[#effects+1]=reel_fx("nw_reel_ocean_fx","swap_fishingrod_ocean","swap_fishingrod_ocean","fishing_ocean_catch")
local definitions=require("nw/definitions")
for _,id in ipairs(definitions.order) do
    local card=definitions.spells[id]
    if card.kind=="melee" then
        effects[#effects+1]=weapon_fx(id,card.source_weapon,card.pose or id,card.duration)
    end
end
return unpack(effects)
