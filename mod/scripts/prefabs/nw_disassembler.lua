local recycle=require("nw/recycle")
local assets={Asset("ANIM","anim/nw_stations.zip"),Asset("ANIM","anim/nw_spell_world.zip")}
local function clientfx(inst)
    local ring,update,start
    local function clear()
        if update then update:Cancel();update=nil end
        if ring then ring:Remove();ring=nil end
    end
    local function state()
        if not inst._active:value() then start=nil;clear();return end
        start=start or GetTime()
        if not ring then
            ring=CreateEntity();ring.entity:AddTransform();ring.entity:AddAnimState()
            ring:AddTag("FX");ring:AddTag("NOCLICK");ring.persists=false
            ring.entity:SetParent(inst.entity)
            ring.AnimState:SetBank("nw_spell_world");ring.AnimState:SetBuild("nw_spell_world")
            ring.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
            ring.AnimState:PlayAnimation("recycle_wave",true)
            ring.AnimState:SetFinalOffset(1)
        end
        local function scale()
            local n=math.clamp((GetTime()-start)/2,.01,1)
            ring.Transform:SetScale(n,n,n)
            -- The gold edge appears as the expanding dust finishes searching.
            ring.AnimState:SetMultColour(.55+.45*n,.62+.38*n,1,.22+.35*n)
        end
        scale()
        if not update then update=inst:DoPeriodicTask(FRAMES,scale) end
    end
    inst:ListenForEvent("nw_furnacedirty",state)
    inst:ListenForEvent("onremove",clear)
    inst:DoTaskInTime(0,state)
    return state
end
local function fn()
    local inst=CreateEntity()
    inst.entity:AddTransform();inst.entity:AddAnimState();inst.entity:AddMiniMapEntity()
    inst.entity:AddLight();inst.entity:AddNetwork()
    MakeObstaclePhysics(inst,.8)
    inst:AddTag("structure");inst:AddTag("nw_disassembler")
    inst.MiniMapEntity:SetIcon("nw_disassembler.tex")
    inst.AnimState:SetBank("nw_stations");inst.AnimState:SetBuild("nw_stations")
    inst.AnimState:PlayAnimation("furnace",true)
    inst.Light:SetRadius(2);inst.Light:SetIntensity(.65);inst.Light:SetFalloff(.7)
    inst.Light:SetColour(.28,.82,1);inst.Light:Enable(false)
    inst._active=net_bool(inst.GUID,"nw_furnace.active","nw_furnacedirty")
    local update=not TheNet:IsDedicated() and clientfx(inst)
    inst.entity:SetPristine()
    if not TheWorld.ismastersim then return inst end
    inst.SetNWActive=function(_,active)
        inst._active:set(active);inst.Light:Enable(active)
        if inst._lightgrow then inst._lightgrow:Cancel();inst._lightgrow=nil end
        if active then
            local start=GetTime();inst.Light:SetRadius(.1)
            inst._lightgrow=inst:DoPeriodicTask(FRAMES,function()
                local n=math.min(1,(GetTime()-start)/2)
                inst.Light:SetRadius(.1+3.9*n)
                if n>=1 then inst._lightgrow:Cancel();inst._lightgrow=nil end
            end)
        end
        inst.AnimState:PlayAnimation(active and "active" or "furnace",true)
        if update then update() end
    end
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
    MakePlacer("nw_disassembler_placer","nw_stations","nw_stations","furnace")
