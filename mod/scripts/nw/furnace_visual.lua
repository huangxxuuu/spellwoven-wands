-- Local ground animation; only phase changes and occasional age corrections
-- cross the network. Gameplay owns the scan and stops independently of FX.
local M={grow_time=60/30,loop_time=60/30,release_time=18/30,rotation_speed=30}
local SYNC_TIME=.25

function M.rotation_angle(age)
    return (math.max(0,age)*M.rotation_speed)%360
end

-- Selected grow frames' maximum alpha>=64 radius / release_000's radius.
-- Keep these measurements synchronized with the painted source selection.
M.release_visual_extents={
    0.000000,0.089182,0.216339,0.310958,0.391029,0.475795,0.517006,0.553151,
    0.600100,0.651569,0.724727,0.776966,0.798662,0.845112,0.874892,0.895693,
    0.922453,0.939596,0.972811,0.986549,0.991128,0.991004,0.987719,0.988369,
}
function M.release_visual_extent(progress)
    if progress<=0 then return 0 end
    if progress>=1 then return 1 end
    -- Match native 30 FPS first, then the authored 24-source/60-tick holds.
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
        inst.Light:SetIntensity(.65)
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
            -- Painted grow frames have a nonlinear outer edge. Register the
            -- release drawing to that edge once when changing clips; scan
            -- progress still independently owns the light and gameplay range.
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
            -- Maintain a current snapshot for entities first seen mid-cycle.
            -- Also explicitly correct connected clients, never every frame.
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
            inst.Light:SetRadius(4*extent)
            inst.Light:SetIntensity(.65*(1-age/duration))
        else
            local progress=math.min(1,age/duration)
            inst.Light:SetRadius(4*progress);inst.Light:SetIntensity(.65)
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
            -- Keep the last visible direction when dissolving. The local
            -- angle never depends on the looping painted clip's frame index.
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
            -- GetTime has a different origin on each peer. Replicate age,
            -- not an absolute GetTime timestamp, and seek without replaying.
            started=math.min(started,GetTime()-age)
        end
        seen_age=age
        if mode=="off" then clear();return end
        local duration=mode=="release" and M.release_time or M.grow_time
        -- A repeated dirty event after release completion must not respawn it.
        if mode=="release" and GetTime()-started>=duration-1e-6 then clear();return end
        make_ring()
        if ring and mode=="release" then ring.Transform:SetRotation(rotation) end
        tick(false)
        if not task and mode~="off" and GetTime()-started<duration-1e-6 then
            task=inst:DoPeriodicTask(FRAMES,tick)
        end
        -- Only a peer rendering this ring needs a rotation update. Dedicated
        -- servers keep the existing phase/snapshot task budget unchanged.
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
