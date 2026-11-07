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
-- Purely visual ground contact. Never starts electrocution or forks native damage.
local function ground_shock()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddNetwork()
    inst:AddTag("FX");inst:AddTag("NOCLICK")
    inst.AnimState:SetBank("shock_fx");inst.AnimState:SetBuild("shock_fx")
    inst.entity:SetCanSleep(false)
    inst.AnimState:PlayAnimation(GetElectrocuteFxAnim("small"))
    inst.AnimState:PushAnimation(GetElectrocuteFxAnim("small").."_pst",false)
    inst.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
    inst.AnimState:SetFinalOffset(1)
    inst.entity:SetPristine()
    if TheWorld.ismastersim then
        inst.persists=false
        inst:ListenForEvent("animqueueover",inst.Remove)
    end
    return inst
end
-- Same proxy/local-animation layout as native explode_small, but without its
-- independent SoundEmitter. The owning soft burst supplies one quieter sound.
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
    inst.persists=false;inst:DoTaskInTime(1,inst.Remove)
    return inst
end
local function effect(name,animation,seconds,light)
    return Prefab(name,function()
        local inst=CreateEntity()
        inst.entity:AddTransform()
        if name=="nw_moon_impact_fx" or name=="nw_soft_blast_fx" then inst.entity:AddSoundEmitter() end
        if animation then
            inst.entity:AddAnimState()
            inst.AnimState:SetBank("nw_objects");inst.AnimState:SetBuild("nw_objects")
            inst.AnimState:PlayAnimation(animation)
            inst.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
            inst.AnimState:SetLightOverride(.85);inst.AnimState:SetFinalOffset(3)
        end
        if light then
            inst.entity:AddLight()
            inst.Light:SetRadius(2);inst.Light:SetIntensity(.75);inst.Light:SetFalloff(.65)
            inst.Light:SetColour(1,.85,.53);inst.Light:Enable(true)
        end
        inst.entity:AddNetwork();inst:AddTag("FX");inst:AddTag("NOCLICK")
        if name=="nw_arc_fx" then
            setup_arc(inst)
        elseif name=="nw_moon_impact_fx" then
            if TheWorld.ismastersim then
                inst.SetRadius=function()
                    if inst._nw_burst_started then return end
                    inst._nw_burst_started=true
                    -- The field's end animation supplies stone fragments.
                    -- Native explode_small proxies each play their own sound;
                    -- use one positioned meteor impact instead of five blasts.
                    inst.SoundEmitter:PlaySound("dontstarve/common/meteor_impact")
                end
            end
        elseif animation=="blast" then
            -- Explosion art never draws a gameplay radius guide. This runs on
            -- both peers, including late-spawned replicated effects.
            inst.AnimState:Hide("blast_extent")
            inst.AnimState:Hide("blast_burst")
            inst._radius=net_float(inst.GUID,"nw_blast.radius","nw_blastradiusdirty")
            local function resize()
                local scale=layout.blast_scale(inst._radius:value())
                inst.AnimState:SetScale(scale,scale)
            end
            if TheWorld.ismastersim then
                inst.SetRadius=function(_,radius)
                    inst._radius:set(radius);resize()
                    if inst._nw_burst_started then return end
                    inst._nw_burst_started=true
                    local x,_,z=inst.Transform:GetWorldPosition()
                    -- Native billboards: rising translucent fire/smoke at several depths.
                    for i=0,4 do
                        local a=i*2.399
                        local fx=SpawnPrefab(name=="nw_soft_blast_fx" and "nw_silent_explode_small" or "explode_small")
                        if fx then
                            local r=i==0 and 0 or radius*.38
                            fx.Transform:SetPosition(x+math.cos(a)*r,.15,z+math.sin(a)*r)
                            local scale=math.max(.25,radius/3)*(i==0 and 1.1 or .65)
                            fx.Transform:SetScale(scale,scale,scale)
                        end
                    end
                    if name=="nw_soft_blast_fx" then
                        inst.SoundEmitter:PlaySound("dontstarve/common/blackpowder_explo",nil,.35)
                    end
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
    end,assets,name=="nw_soft_blast_fx" and {"nw_silent_explode_small"} or {"explode_small"})
end
local weapon_fx=require("nw/weapon_visual")
local effects={Prefab("nw_ground_shock_fx",ground_shock,assets),
    Prefab("nw_silent_explode_small",silent_explosion,assets),
    effect("nw_arc_fx",nil,.22),effect("nw_heal_fx","heal",.3),
    effect("nw_blast_fx","blast",.32),effect("nw_lighter_burst_fx","blast",.32),effect("nw_afterlight",nil,3,true),
    effect("nw_moon_impact_fx",nil,.8),
    effect("nw_soft_blast_fx","blast",1),
    effect("nw_crystal_burst_fx","blast",.32),
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
