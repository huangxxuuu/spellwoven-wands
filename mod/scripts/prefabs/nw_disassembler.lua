local recycle=require("nw/recycle")
local assets={Asset("ANIM","anim/nw_stations.zip")}
local function clientfx(inst)
    local ring,update,hover,start
    local function refresh()
        if update then update:Cancel();update=nil end
        if inst._active:value() or hover then
            if not ring then
                ring=SpawnPrefab("reticuleaoe")
                ring.entity:SetParent(inst.entity)
            end
            local active=inst._active:value()
            ring.AnimState:SetMultColour(.34,.91,1,active and .8 or .3)
            local function scale()
                local n=start and math.clamp((GetTime()-start)/2,.01,1) or 1
                ring.Transform:SetScale(n,n,n)
                if n==1 and update then update:Cancel();update=nil end
            end
            scale()
            if active and start and GetTime()-start<2 then update=inst:DoPeriodicTask(FRAMES,scale) end
        elseif ring then ring:Remove();ring=nil end
    end
    inst:ListenForEvent("mouseover",function() hover=true;refresh() end)
    inst:ListenForEvent("mouseout",function() hover=false;refresh() end)
    local function state()
        start=inst._active:value() and (start or GetTime()) or nil
        refresh()
    end
    inst:ListenForEvent("nw_furnacedirty",state)
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
return Prefab("nw_disassembler",fn,assets,{"reticuleaoe","carnival_sparkle_fx","nw_dust","nw_spellcard"}),
    MakePlacer("nw_disassembler_placer","nw_stations","nw_stations","furnace")
