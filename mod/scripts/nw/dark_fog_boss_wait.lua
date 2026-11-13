-- Server-only reaction while covered and no native defense is currently usable.
local M = { reason = "nw_fog_boss_wait", interval = .1, body_delay = 2, body_duration = 2.5 }
-- Only ordinary locomotion can be interrupted. In particular minotaur's
-- run chain is an attack, even run_stop's apparent idle tag before impact.
local runners={bearger=true,mutatedbearger=true,warg=true,mutatedwarg=true,daywalker2=true,spat=true}
local function other_action(inst)
    local loco=inst.components.locomotor
    local queued=inst.bufferedaction
    local travel=loco and loco.bufferedaction
    return queued and not (ACTIONS and queued.action==ACTIONS.ATTACK)
        or travel and not (ACTIONS and travel.action==ACTIONS.ATTACK)
end
function M.can_move(inst)
    if other_action(inst) then return false end
    local sg=inst.sg
    local name=sg and sg.currentstate and sg.currentstate.name
    local ordinary=name=="idle" or name=="idle_nofaced"
        or name=="walk_start" or name=="walk" or name=="walk_stop"
        or runners[inst.prefab] and (name=="run_start" or name=="run" or name=="run_stop")
        or inst.prefab=="moose" and name=="hop"
    return ordinary and not sg:HasStateTag("busy") and not sg:HasStateTag("attack") and not sg:HasStateTag("atk_pre")
end
local function position(inst) local x,_,z=inst.Transform:GetWorldPosition();return x,z end
local function incapacitated(inst)
    if other_action(inst) then return true end
    local c=inst.components
    if inst.buried or inst.defeated or (inst.prefab=="daywalker2" and not inst.hostile) then return true end
    for reason in pairs(inst._brainstopped or {}) do
        if reason~=M.reason and not (reason=="nw_fog_boss" and inst._nw_fog_boss_cast) then return true end
    end
    local mem=inst.sg.mem
    if mem and (mem.wantstochannel or mem.wantstoroar or mem.wantstoburrow or mem.wantstoleave
        or mem.wantstotransform or mem.wantstospawn or mem.wantstofocustarget or mem.wantstotransition
        or mem.wantstoscreech or mem.wantstoflyaway or mem.wantstospawnguards or mem.focuscount ~= nil
        or mem.wantstochomp or mem.laughsremaining or mem.dostagger or mem.dohowl or mem.doicegrow or mem.sleeping) then return true end
    if not inst:IsValid() or inst:IsInLimbo() or inst:IsAsleep() or c.health:IsDead()
        or c.sleeper and c.sleeper:IsAsleep() or c.freezable and c.freezable:IsFrozen() then return true end
    for _,tag in ipairs({"dead","sleeping","frozen","flight","grounded","jumping","transform","knockback","knockout","fossilized"}) do
        if inst.sg:HasStateTag(tag) then return true end
    end
    return false
end
function M.stop(inst, removing)
    local state=inst._nw_fog_boss_wait
    if not state then return end
    inst._nw_fog_boss_wait=nil
    if state.task then state.task:Cancel() end
    for event,fn in pairs(state.events) do inst:RemoveEventCallback(event,fn) end
    local live=not removing and inst:IsValid() and not inst.components.health:IsDead()
    if live then
        -- An already committed SG owns its own movement.
        if state.moving and M.can_move(inst) then inst.components.locomotor:Stop() end
        inst:RestartBrain(M.reason)
    else
        -- Entity removal/death must not reinsert a brain into BrainManager.
        local reasons=inst._brainstopped
        if reasons then reasons[M.reason]=nil;if next(reasons)==nil then inst._brainstopped=nil end end
    end
end
local function stop_body(inst)
    local state=inst._nw_fog_boss_body
    if not state then return end
    inst._nw_fog_boss_body=nil
    if state.task then state.task:Cancel() end
    for event,fn in pairs(state.events) do inst:RemoveEventCallback(event,fn) end
end
local function start_body(inst, now, x, z)
    if inst._nw_fog_boss_body then return end
    local state={world=TheWorld,until_time=now+M.body_duration,x=x,z=z,events={}}
    inst._nw_fog_boss_body=state
    for _,event in ipairs({"death","entitysleep","onremove"}) do
        local fn=function() stop_body(inst) end
        state.events[event]=fn;inst:ListenForEvent(event,fn)
    end
    local function tick()
        if inst._nw_fog_boss_body~=state then return end
        if GetTime()>=state.until_time or not inst:IsValid() or inst:IsInLimbo()
            or inst:IsAsleep() or inst.components.health:IsDead()
            or TheWorld~=state.world or not state.world.ismastersim then stop_body(inst);return end
        local nx,nz=position(inst)
        local ax,az=state.x,state.z
        state.x,state.z=nx,nz
        if (nx-ax)^2+(nz-az)^2>16*16 then ax,az=nx,nz end
        -- This finite sweep survives leaving the cloud which started it.
        -- It reads only actual motion and never commands the boss's SG.
        require("nw/dark_fog").disperse_path(state.world,ax,az,nx,nz,math.max(0,inst:GetPhysicsRadius(0)))
    end
    state.task=inst:DoPeriodicTask(M.interval,tick)
    tick()
end
function M.leave(inst)
    M.stop(inst)
end
local function walk(inst,state,now)
    if now<(state.next_turn or 0) then return end
    local loco=inst.components.locomotor
    local duration=.25+math.random()*.25
    state.next_turn=now+duration
    local aquatic=loco.IsAquatic and loco:IsAquatic()
    local finder=aquatic and FindSwimmableOffset or FindWalkableOffset
    if not finder then return end
    local point=inst:GetPosition()
    local angle=math.random()*2*math.pi
    local distance=math.max(.5,(loco.GetWalkSpeed and loco:GetWalkSpeed() or 4)*duration+.25)
    local water=loco.CanPathfindOnWater and loco:CanPathfindOnWater() or false
    local offset,heading=finder(point,angle,distance,1,true,false,nil,water)
    if offset then loco:WalkInDirection((heading or angle)*180/math.pi);state.moving=true
    elseif state.moving then loco:Stop();state.moving=false end
end
-- StopBrain does not clear the locomotor's destination/path. Do this only
-- after a safe idle/movement gate and after taking ownership of the brain.
function M.stop_chase(inst)
    if inst.bufferedaction and inst.ClearBufferedAction then inst:ClearBufferedAction() end
    local loco=inst.components.locomotor
    if loco then
        if loco.bufferedaction and loco.SetBufferedAction then loco:SetBufferedAction(nil) end
        loco:Stop()
    end
end
function M.target_in_range(inst, target)
    local combat=inst.components.combat
    if not (target and target:IsValid() and combat and combat.CanTarget and combat:CanTarget(target)) then return false end
    local planned=M.target_range and M.target_range(inst,target)
    if planned~=nil then return planned end
    return combat.CalcAttackRangeSq
        and target:GetDistanceSqToPoint(inst.Transform:GetWorldPosition())<=combat:CalcAttackRangeSq(target)
end
function M.prune_target(inst)
    local combat=inst.components.combat
    if combat and combat.target and not M.target_in_range(inst,combat.target) and combat.DropTarget then
        combat:DropTarget()
    end
end
function M.start(inst, now, poll)
    if inst._nw_fog_boss_wait or not inst.components.locomotor then return false end
    local x,z=position(inst)
    local state={started=now,x=x,z=z,events={}}
    inst._nw_fog_boss_wait=state
    inst:StopBrain(M.reason)
    M.stop_chase(inst)
    M.prune_target(inst)
    for _,event in ipairs({"death","entitysleep","onremove"}) do
        local removing=event=="onremove"
        local fn=function() M.stop(inst,removing) end
        state.events[event]=fn;inst:ListenForEvent(event,fn)
    end
    local function tick()
        if inst._nw_fog_boss_wait~=state then return end
        local time=GetTime()
        if incapacitated(inst) then M.stop(inst);return end
        local Fog=require("nw/dark_fog")
        if not Fog.contains(TheWorld,inst) then M.stop(inst);return end
        if M.can_move(inst) then M.prune_target(inst) end
        if poll(inst,time) or inst._nw_fog_boss_wait~=state then
            state.suspended=true
            return
        end
        -- A native/external attack may start while we own the brain. Observe
        -- it without resuming pursuit or touching its movement/locked target.
        if inst._nw_fog_boss_cast or not M.can_move(inst) then
            state.suspended=true
            state.x,state.z=position(inst)
            return
        end
        if state.suspended then
            state.suspended=nil
            state.started=time
            state.x,state.z=position(inst)
        end
        if not state.body_started and time-state.started>=M.body_delay then
            state.body_started=true
            start_body(inst,time,state.x,state.z)
            if inst._nw_fog_boss_wait~=state then return end
        end
        state.x,state.z=position(inst)
        if M.can_move(inst) then walk(inst,state,time) end
    end
    state.task=inst:DoPeriodicTask(M.interval,tick)
    tick()
    return true
end
return M
