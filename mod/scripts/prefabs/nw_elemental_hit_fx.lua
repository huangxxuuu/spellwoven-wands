local C=require("nw/constants/prefabs").elemental_hit
local Elemental=require("nw/constants/native").elemental
local Flight=require("nw/elemental_flight")
local assets={Asset("ANIM","anim/nw_elemental_flight.zip")}
local LIFETIME=Elemental.clip_frames/Elemental.frame_rate
local names={"fire","frost","arrow","heavy","scatter",
    "gust","spore_ball","flint_lance","slime","grow_orb","heal_bolt","star_vortex",
    "glass_disc","land_hook","tri_electric","end_beam","soundwave","bee_swarm","fireflies"}
local codes={}
for code,id in ipairs(names) do codes[id]=code end
local scale=C.scale

local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform()
    inst.entity:AddNetwork()
    inst.entity:SetCanSleep(false)
    inst:AddTag("FX");inst:AddTag("NOCLICK")
    inst.persists=false
    inst._kind=net_byte(inst.GUID,"nw_elemental_hit.kind","nw_elemental_hitdirty")
    inst._height=net_float(inst.GUID,"nw_elemental_hit.height","nw_elemental_hitdirty")
    inst._size=net_float(inst.GUID,"nw_elemental_hit.size","nw_elemental_hitdirty")
    inst._heading=net_float(inst.GUID,"nw_elemental_hit.heading","nw_elemental_hitdirty")
    inst.entity:SetPristine()

    local visual,started,direction,animation,task
    local function refresh()
        if TheNet:IsDedicated() then return end
        local id=names[inst._kind:value()]
        if not id then return end
        local now=GetTime()
        started=started or now
        local age=math.max(0,now-started)
        if age>=LIFETIME-Elemental.expiry_epsilon then
            if visual then visual:Hide() end
            if task then task:Cancel();task=nil end
            return
        end
        if not visual then
            visual=CreateEntity()
            visual.entity:AddTransform();visual.entity:AddAnimState()
            visual.entity:SetCanSleep(false)
            visual.entity:SetParent(inst.entity)
            visual:AddTag("FX");visual:AddTag("NOCLICK");visual.persists=false
            visual.AnimState:SetBank("nw_elemental_flight")
            visual.AnimState:SetBuild("nw_elemental_flight")
            visual.AnimState:SetOrientation(ANIM_ORIENTATION.BillBoard)
            visual.AnimState:SetLightOverride(1)
            task=inst:DoPeriodicTask(1/Elemental.frame_rate,refresh)
        end
        visual.Transform:SetPosition(0,inst._height:value(),0)
        local size=math.max(1,inst._size:value())*scale[id]
        visual.Transform:SetScale(size,size,size)
        local face=Flight.direction(inst._heading:value(),id)
        if face~=direction or id~=animation then
            direction,animation=face,id
            visual.AnimState:PlayAnimation(id.."_hit_dir_"..face)
            visual.AnimState:SetTime(age)
        end
    end
    inst:ListenForEvent("onremove",function()
        if task then task:Cancel();task=nil end
        if visual and visual:IsValid() then visual:Remove() end
    end)
    if not TheWorld.ismastersim then
        inst:ListenForEvent("nw_elemental_hitdirty",refresh)
        inst:DoTaskInTime(0,refresh)
        return inst
    end
    function inst:SetImpact(id,height,size,heading)
        self._height:set(height)
        self._size:set(size)
        self._heading:set(heading)
        self._kind:set(codes[Flight.resolve(id)] or 0)
        refresh()
    end
    inst:DoTaskInTime(LIFETIME,inst.Remove)
    return inst
end

return Prefab("nw_elemental_hit_fx",fn,assets)
