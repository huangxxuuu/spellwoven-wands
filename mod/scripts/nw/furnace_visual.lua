-- Local ground animation; only phase changes and occasional age corrections
-- cross the network. Gameplay owns the scan and stops independently of FX.
local M={grow_time=60/30,loop_time=60/30,release_time=18/30}
local SYNC_TIME=.25

function M.netvars(inst)
    inst._active=net_bool(inst.GUID,"nw_furnace.active","nw_furnacedirty")
    inst._retract=net_bool(inst.GUID,"nw_furnace.retract","nw_furnacedirty")
    inst._nw_furnace_age=net_float(inst.GUID,"nw_furnace.age","nw_furnacedirty")
    inst._nw_furnace_extent=net_float(inst.GUID,"nw_furnace.extent","nw_furnacedirty")
    inst._nw_furnace_seq=net_uint(inst.GUID,"nw_furnace.seq","nw_furnacedirty")
end

function M.attach(inst)
    local ring,task,mode,sequence,started,seen_age,clip,last_sync
    local removed=false
    local master=TheWorld.ismastersim
    local function cancel()
        if task then task:Cancel();task=nil end
    end
    local function clear()
        cancel()
        if ring then ring:Remove();ring=nil end
        clip=nil
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
    end
    local function play(name,age,extent)
        if not ring then return end
        if clip~=name then
            clip=name
            ring.AnimState:PlayAnimation(name,name=="loop")
            -- Grow is authored at full scale. Only an interrupted release
            -- needs a fixed scale, captured once from the scan's progress.
            ring.Transform:SetScale(extent,extent,extent)
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
            cancel();clip=nil
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
        make_ring();tick(false)
        if not task and mode~="off" and GetTime()-started<duration-1e-6 then
            task=inst:DoPeriodicTask(FRAMES,tick)
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
