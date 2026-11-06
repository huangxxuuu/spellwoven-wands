local assets={Asset("ANIM","anim/shock_fx.zip"),Asset("ANIM","anim/fence_electric_field_fx.zip"),Asset("ANIM","anim/nw_objects.zip"),Asset("ANIM","anim/swap_spear.zip"),
    Asset("ANIM","anim/swap_glasscutter.zip"),Asset("ANIM","anim/swap_axe.zip")}
local layout=require("nw/fx_layout")
local function setup_arc(inst)
    inst._dx=net_float(inst.GUID,"nw_arc.dx","nw_arcdirty")
    inst._dz=net_float(inst.GUID,"nw_arc.dz","nw_arcdirty")
    inst._contact=net_entity(inst.GUID,"nw_arc.contact","nw_arcdirty")
    inst._shockanim=net_string(inst.GUID,"nw_arc.shockanim","nw_arcdirty")
    local pieces={}
    local last_x,last_z,last_target,last_anim
    local function clear()
        for _,piece in ipairs(pieces) do if piece:IsValid() then piece:Remove() end end
        pieces={}
    end
    local function refresh()
        if TheNet:IsDedicated() then return end
        local dx,dz=inst._dx:value(),inst._dz:value()
        local target,anim=inst._contact:value(),inst._shockanim:value()
        if dx==last_x and dz==last_z and target==last_target and anim==last_anim then return end
        last_x,last_z,last_target,last_anim=dx,dz,target,anim
        clear()
        local count,scale,rotation=layout.arc(dx,dz)
        for i=1,count do
            local piece=CreateEntity()
            piece.entity:AddTransform();piece.entity:AddAnimState()
            piece:AddTag("FX");piece:AddTag("NOCLICK");piece.persists=false
            piece.entity:SetParent(inst.entity)
            local mid=(i-.5)/count
            piece.Transform:SetPosition(dx*mid,0,dz*mid)
            piece.Transform:SetRotation(rotation)
            piece.AnimState:SetBank("fence_electric_field_fx");piece.AnimState:SetBuild("fence_electric_field_fx")
            -- This is a span between two world points, not a camera-facing
            -- projectile. Ground-plane orientation lets world yaw turn the beam.
            piece.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
            piece.AnimState:SetLightOverride(1);piece.AnimState:SetFinalOffset(3)
            piece.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
            piece.AnimState:SetScale(scale,i%2==0 and -layout.arc_thickness or layout.arc_thickness)
            piece.AnimState:SetMultColour(.64,.82,1,1)
            piece.AnimState:PlayAnimation("beam",true)
            pieces[i]=piece
        end
        if target and target:IsValid() and anim~="" then
            local contact=CreateEntity()
            contact.entity:AddTransform();contact.entity:AddAnimState()
            contact:AddTag("FX");contact:AddTag("NOCLICK");contact.persists=false
            contact.entity:SetParent(target.entity)
            contact.AnimState:SetBank("shock_fx");contact.AnimState:SetBuild("shock_fx")
            contact.AnimState:SetMultColour(.64,.82,1,1)
            contact.AnimState:SetAddColour(.06,.15,.36,0)
            contact.AnimState:SetFinalOffset(1)
            contact.AnimState:SetBloomEffectHandle("shaders/anim.ksh")
            contact.AnimState:PlayAnimation(anim)
            pieces[#pieces+1]=contact
        end
    end
    if TheWorld.ismastersim then
        inst.SetSpan=function(_,dx,dz,target)
            inst._dx:set(dx);inst._dz:set(dz)
            if target then
                local _,size,height=GetCombatFxSize(target)
                inst._shockanim:set(GetElectrocuteFxAnim(size,height))
                inst._contact:set(target)
            end
            refresh()
        end
    else
        inst:ListenForEvent("nw_arcdirty",refresh);inst:DoTaskInTime(0,refresh)
    end
    inst:ListenForEvent("onremove",clear)
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
local function effect(name,animation,seconds,light)
    return Prefab(name,function()
        local inst=CreateEntity()
        inst.entity:AddTransform()
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
        elseif animation=="blast" then
            -- Explosion art never draws a gameplay radius guide. This runs on
            -- both peers, including late-spawned replicated effects.
            inst.AnimState:Hide("blast_extent")
            inst._radius=net_float(inst.GUID,"nw_blast.radius","nw_blastradiusdirty")
            local function resize()
                local scale=layout.blast_scale(inst._radius:value())
                inst.AnimState:SetScale(scale,scale)
            end
            if TheWorld.ismastersim then
                inst.SetRadius=function(_,radius) inst._radius:set(radius);resize() end
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
    effect("nw_arc_fx",nil,.22),effect("nw_heal_fx","heal",.3),
    effect("nw_blast_fx","blast",.32),effect("nw_lighter_burst_fx","blast",.32),effect("nw_afterlight",nil,3,true),
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
