local C=require("nw/constants/visuals/furnace_visual")
local M={grow_time=C.grow_time,loop_time=C.loop_time,release_time=C.release_time,rotation_speed=C.rotation_speed}
local SYNC_TIME=C.sync_time

function M.rotation_angle(age)
    return (math.max(0,age)*M.rotation_speed)%360
end

M.release_visual_extents=C.release_visual_extents
function M.release_visual_extent(progress)
    if progress<=0 then return 0 end
    if progress>=1 then return 1 end
    local tick=math.floor(progress*60+1e-6)
    local source=math.floor(tick*24/60)
    return M.release_visual_extents[math.min(24,source+1)]
end

function M.netvars(inst)
    inst._active=net_bool(inst.GUID,"nw_furnace.active","nw_furnacedirty")
    inst._retract=net_bool(inst.GUID,"nw_furnace.retract","nw_furnacedirty")
    inst._nw_furnace_age=net_float(inst.GUID,"nw_furnace.age","nw_furnacedirty")
    inst._nw_furnace_extent=net_float(inst.GUID,"nw_furnace.extent","nw_furnacedirty")
    inst._nw_furnace_seq=net_uint(inst.GUID,"nw_furnace.seq","nw_furnacedirty")
end

function M.attach(inst)
    local ring,task,rotation_task,mode,sequence,started,seen_age,clip,last_sync
    local rotation=0
    local removed=false
    local master=TheWorld.ismastersim
    local function cancel()
        if task then task:Cancel();task=nil end
    end
    local function cancel_rotation()
        if rotation_task then rotation_task:Cancel();rotation_task=nil end
    end
    local function clear()
        cancel();cancel_rotation()
        if ring then ring:Remove();ring=nil end
        clip=nil;rotation=0
        inst.Light:SetRadius(0)
        inst.Light:SetIntensity(C.light_intensity)
    end
    local function make_ring()
        if ring or TheNet:IsDedicated() then return end
        ring=CreateEntity();ring.entity:AddTransform();ring.entity:AddAnimState()
        ring.entity:SetCanSleep(false)
        ring:AddTag("FX");ring:AddTag("NOCLICK");ring.persists=false
        ring.entity:SetParent(inst.entity)
        ring.AnimState:SetBank("nw_furnace_wave");ring.AnimState:SetBuild("nw_furnace_wave")
        ring.AnimState:SetOrientation(ANIM_ORIENTATION.OnGround)
        ring.AnimState:SetLayer(LAYER_BACKGROUND);ring.AnimState:SetSortOrder(1)
        ring.Transform:SetRotation(rotation)
    end
    local function spin()
        rotation=M.rotation_angle(GetTime()-started)
        ring.Transform:SetRotation(rotation)
    end
    local function play(name,age,extent)
        if not ring then return end
        if clip~=name then
            clip=name
            ring.AnimState:PlayAnimation(name,name=="loop")
            local scale=name=="release" and M.release_visual_extent(extent) or extent
            ring.Transform:SetScale(scale,scale,scale)
        end
        ring.AnimState:SetTime(age)
    end
    local state
    local function tick(publish)
        local age=math.max(0,GetTime()-started)
        local duration=mode=="release" and M.release_time or M.grow_time
        if age>=duration-1e-6 then age=math.max(age,duration) end
        if master and publish~=false then
            inst._nw_furnace_age:set_local(math.min(age,duration))
            if age>=duration or GetTime()-last_sync>=SYNC_TIME then
                inst._nw_furnace_age:set(math.min(age,duration))
                last_sync=GetTime()
            end
        end
        if mode=="release" then
            if age>=duration-1e-6 then
                clear()
                if master then
                    inst._retract:set(false)
                    inst._nw_furnace_age:set(0)
                    state()
                end
                return
            end
            local extent=inst._nw_furnace_extent:value()
            play("release",age,extent)
            inst.Light:SetRadius(C.light_radius*extent)
            inst.Light:SetIntensity(C.light_intensity*(1-age/duration))
        else
            local progress=math.min(1,age/duration)
            inst.Light:SetRadius(C.light_radius*progress);inst.Light:SetIntensity(C.light_intensity)
            if age<duration-1e-6 then
                play("grow",age,1)
            else
                play("loop",math.max(0,age-duration)%M.loop_time,1)
                cancel()
            end
        end
    end
    state=function()
        if removed then return end
        local nextmode=inst._active:value() and "active" or inst._retract:value() and "release" or "off"
        local nextseq=inst._nw_furnace_seq:value()
        local age=inst._nw_furnace_age:value()
        if nextmode~=mode or nextseq~=sequence then
            if mode=="active" and nextmode=="release" then
                rotation=M.rotation_angle(GetTime()-started)
            elseif nextmode=="active" then
                rotation=M.rotation_angle(age)
            end
            cancel();cancel_rotation();clip=nil
            mode,sequence=nextmode,nextseq
            started=GetTime()-age
            last_sync=GetTime()
        elseif age~=seen_age and not master then
            started=math.min(started,GetTime()-age)
        end
        seen_age=age
        if mode=="off" then clear();return end
        local duration=mode=="release" and M.release_time or M.grow_time
        if mode=="release" and GetTime()-started>=duration-1e-6 then clear();return end
        make_ring()
        if ring and mode=="release" then ring.Transform:SetRotation(rotation) end
        tick(false)
        if not task and mode~="off" and GetTime()-started<duration-1e-6 then
            task=inst:DoPeriodicTask(FRAMES,tick)
        end
        if ring and mode=="active" then
            spin()
            if not rotation_task then rotation_task=inst:DoPeriodicTask(FRAMES,spin) end
        end
    end
    inst:ListenForEvent("nw_furnacedirty",state)
    inst:ListenForEvent("onremove",function() removed=true;clear() end)
    inst:DoTaskInTime(0,state)
    if master then
        inst.SetNWActive=function(_,active,release)
            if removed then return end
            release=not active and release==true
            if inst._active:value()==active and inst._retract:value()==release then return end
            local extent=mode=="active" and math.min(1,math.max(0,GetTime()-started)/M.grow_time) or 0
            inst._nw_furnace_extent:set(extent)
            inst._nw_furnace_age:set(0)
            inst._nw_furnace_seq:set((inst._nw_furnace_seq:value()+1)%4294967296)
            inst._retract:set(release);inst._active:set(active)
            inst.AnimState:PlayAnimation(active and "active" or "furnace",true)
            state()
        end
    end
end
return M
