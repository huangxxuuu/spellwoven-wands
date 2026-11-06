-- Optional shard-wide collection of unattended, permanent moving spells.
-- A count threshold starts a collection pass; it is not an entity cap.
local Limits=require("nw/spell_limits")
local M={timeout=16*60,max_elapsed=20*60,threshold=20}

local function advance(state,now)
    -- Keep the counter itself bounded, including when collection is below
    -- its count threshold. The simulation clock is only used for deltas.
    if state.absent<M.max_elapsed then
        state.absent=math.min(M.max_elapsed,state.absent+math.max(0,now-state.updated_at))
    end
    state.updated_at=now
end

local function activity(state,active,now)
    advance(state,now)
    if active or state.active then state.absent=0 end
    state.active=active
end

local function observe(inst,state,now)
    local probe=state.probe
    -- New entities report awake until the engine delivers their initial state.
    -- Preserve saved absence while that initial result is pending.
    if probe:IsValid() and not probe.sleepstatepending then
        activity(state,not probe:IsAsleep(),now)
    else
        advance(state,now)
    end
end

function M.sync(inst)
    local state=inst._nw_cleanup_state
    if not state then return end
    local x,_,z=inst.Transform:GetWorldPosition()
    if state.x~=x or state.z~=z then
        state.x,state.z=x,z
        state.probe.Transform:SetPosition(x,0,z)
    end
end

local function tick(world)
    local pool=world._nw_permanent_motion_cleanup
    local now=GetTime()
    local collect=Limits.permanent_motion_cleanup and pool.count>M.threshold
    local expired={}
    for inst,state in pairs(pool.items) do
        if inst:IsValid() then
            observe(inst,state,now)
            if not Limits.permanent_motion_cleanup then state.absent=0 end
            if collect and state.active==false and not state.probe.sleepstatepending
                and state.absent>=M.timeout then expired[#expired+1]=inst end
        end
    end
    -- Evaluate the threshold once for this pass. Never remove recent entities
    -- to reach twenty, and never invoke break/impact/payload callbacks.
    for _,inst in ipairs(expired) do if inst:IsValid() then inst:Remove() end end
end

function M.unwatch(inst)
    local state=inst._nw_cleanup_state
    if state and state.release then state.release() end
end

function M.watch(inst)
    if not Limits.permanent_motion_cleanup or inst._nw_cleanup_state
        or not inst._nw_stored or not inst._nw_motion then return end
    local pool=TheWorld._nw_permanent_motion_cleanup
    if not pool then pool={items={},count=0};TheWorld._nw_permanent_motion_cleanup=pool end
    local absent=tonumber(inst._nw_stored.cleanup_absent) or 0
    if absent~=absent then absent=0 end
    local now=GetTime()
    local state={absent=math.max(0,math.min(M.max_elapsed,absent)),updated_at=now}
    -- The spell itself cannot sleep: it must continue flying outside active
    -- regions. An unparented, non-networked transform asks the engine what a
    -- normal sleepable entity at the same position would do. No fixed radius.
    local probe=CreateEntity()
    probe.entity:AddTransform()
    probe.entity:SetCanSleep(true)
    probe.persists=false
    state.probe=probe
    inst._nw_cleanup_state=state
    M.sync(inst)
    probe:ListenForEvent("entitywake",function() activity(state,true,GetTime()) end)
    probe:ListenForEvent("entitysleep",function() activity(state,false,GetTime()) end)
    pool.items[inst]=state;pool.count=pool.count+1
    state.release=function()
        if inst._nw_cleanup_state~=state then return end
        pool.items[inst]=nil;pool.count=pool.count-1
        inst._nw_cleanup_state=nil
        if inst.RemoveEventCallback then inst:RemoveEventCallback("onremove",state.release) end
        if probe:IsValid() then probe:Remove() end
        if pool.count==0 and pool.task then pool.task:Cancel();pool.task=nil end
    end
    inst:ListenForEvent("onremove",state.release)
    if not pool.task then pool.task=TheWorld:DoPeriodicTask(1,tick) end
end

function M.elapsed(inst)
    local state=inst._nw_cleanup_state
    if not Limits.permanent_motion_cleanup or not state then return end
    local now=GetTime()
    observe(inst,state,now)
    -- Store duration, never an absolute clock. Time with the server closed
    -- does not count; loading does not erase the time already accumulated.
    return state.absent
end
return M
