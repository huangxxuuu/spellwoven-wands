local C=require("nw/constants/casting").pose
local Cast=require("nw/cast_action")
local Mode=require("nw/cast_mode")
local U=require("nw/util")
local M={}
local STATE="nw_hold_pose"
local ANIM={pre="nw_hold_cast_pre",loop="nw_hold_cast_loop",post="nw_hold_cast_pst"}
local globals

local function cancel_lease(player)
    local hold=player._nw_pose_hold
    player._nw_pose_hold=nil
    if hold and hold.task then hold.task:Cancel();hold.task=nil end
end

local function in_pose(player)
    return player.sg and player.sg.currentstate.name==STATE
end

local function reverse_frame(player,animation)
    local anim=player.AnimState
    if anim:IsCurrentAnimation(animation) then
        return math.max(0,anim:GetCurrentAnimationNumFrames()-1-anim:GetCurrentAnimationFrame())
    end
end

local function begin_post(player)
    local mem=player.sg.statemem
    mem.post=true
    mem.recoil=0
    local frame=reverse_frame(player,ANIM.pre)
    player.AnimState:PlayAnimation(ANIM.post)
    if frame then player.AnimState:SetFrame(frame) end
end

local function stop(player,interrupt)
    local hold=player._nw_pose_hold
    cancel_lease(player)
    if in_pose(player) then
        local mem=player.sg.statemem
        -- Stay interruptible during the post animation. Native idle's onenter
        -- clears buffered actions, so do not enter it from an RPC callback.
        if not mem.releasing then mem.recoil_time=GetTime() end
        mem.releasing=true
        -- A click arriving before its first hold RPC still gets one recoil
        -- after extension. It is never promoted to a persistent input hold.
        if hold and hold.transient and mem.recoil>0 then mem.transient_shot=true end
        if not mem.post and (interrupt or mem.recoil==0
            or (player.AnimState:IsCurrentAnimation(ANIM.pre) and not mem.transient_shot)) then
            begin_post(player)
        end
    end
end

local function pending(player,casting)
    local loco=player.components.locomotor
    local function blocks(act)
        return act and not (casting and act.action==ACTIONS.NW_CAST and act.invobject==casting)
    end
    return blocks(player:GetBufferedAction()) or (loco and (blocks(loco.bufferedaction)
        or loco:WantsToMoveForward() or loco:HasDestination()))
end

local function eligible(player,wand,casting,allow_riding)
    if not Mode.enabled() or type(wand)~="table" or not wand.IsValid or not wand:IsValid() or Cast.hand(player)~=wand
        or not player.sg or player._nw_editing or (player._nw_edit_until or 0)>GetTime()
        or pending(player,casting) then return false end
    if not Cast.pose_state(player) then return false end
    local inv=player.components.inventory
    if inv and inv:GetActiveItem() then return false end
    -- The hold animations have not been verified for mounted builds.
    local rider=player.components.rider
    return allow_riding or not (rider and rider:IsRiding())
end

local function render_recoil(player)
    local mem=player.sg.statemem
    if player.AnimState:IsCurrentAnimation(ANIM.pre) then return end
    local level=math.min(C.recoil_levels,math.ceil(mem.recoil*C.recoil_levels-1e-6))
    if level~=mem.level then
        local frame=player.AnimState:GetCurrentAnimationFrame()
        mem.level=level
        player.AnimState:PlayAnimation(level==0 and ANIM.loop
            or string.format("nw_hold_cast_recoil_%02d",level),true)
        -- All intensity tracks share one cycle: breathing and supporting legs
        -- continue through shots/decay rather than restarting on each impulse.
        player.AnimState:SetFrame(frame)
    end
end

local function decay_recoil(player)
    local mem=player.sg.statemem
    local now=GetTime()
    local elapsed=math.max(0,now-mem.recoil_time)
    mem.recoil_time=now
    -- Finish extending once, then show any shots accumulated during the pre.
    if not player.AnimState:IsCurrentAnimation(ANIM.pre) then
        if mem.extending then mem.extending=nil;elapsed=0 end
        local rate=mem.releasing and C.recoil_release_decay or C.recoil_decay
        mem.recoil=math.max(0,mem.recoil-elapsed*rate)
        if mem.recoil<1e-6 then mem.recoil=0 end
    end
end

local function cast_success(player,wand)
    local hold=player._nw_pose_hold
    if not globals.TheWorld.ismastersim or not in_pose(player) or player.sg.statemem.releasing
        or not hold or hold.wand~=wand or not eligible(player,wand,wand) then return end
    decay_recoil(player)
    local mem=player.sg.statemem
    mem.recoil=math.min(1,mem.recoil+C.recoil_kick)
    render_recoil(player)
end

local function face(player,x,z)
    if x==nil then return end
    local px,_,pz=player.Transform:GetWorldPosition()
    local dsq=(x-px)^2+(z-pz)^2
    if U.finite(dsq) and dsq>C.direction_epsilon_squared then
        player.components.locomotor:FaceMovePoint(x,0,z)
    end
end

local function enter(player,wand)
    if in_pose(player) and player.sg.statemem.releasing and not player.sg.statemem.post then
        decay_recoil(player)
        render_recoil(player)
        player.sg.statemem.releasing=nil
        player.sg.statemem.transient_shot=nil
    elseif not in_pose(player) or player.sg.statemem.releasing then
        local frame=in_pose(player) and reverse_frame(player,ANIM.post) or nil
        player.sg:GoToState(STATE)
        if frame then player.AnimState:SetFrame(frame) end
    end
    player.sg.statemem.wand=wand
end

local function lease(player,wand,transient)
    cancel_lease(player)
    local hold={wand=wand,transient=transient}
    player._nw_pose_hold=hold
    hold.task=player:DoTaskInTime(C.lease,function()
        if player._nw_pose_hold==hold then
            hold.task=nil
            stop(player)
        end
    end)
end

local function ensure(player,wand)
    if not globals.TheWorld.ismastersim or not player:IsValid() or not eligible(player,wand,wand,true) then return false end
    -- Keep the established mounted instant route, without unverified poses.
    local rider=player.components.rider
    if rider and rider:IsRiding() then return true end
    enter(player,wand)
    local hold=player._nw_pose_hold
    if not hold or hold.wand~=wand then lease(player,wand,true) end
    return true
end

local function receive(player,value,serial,wand,x,z)
    local G=globals
    if not G.TheWorld or not G.TheWorld.ismastersim or not player or not player:IsValid()
        or (value~=0 and value~=1) or not U.finite(serial) or serial<1 or serial>C.max_serial
        or serial~=math.floor(serial) then return end
    local previous=player._nw_pose_serial
    if previous then
        local delta=(serial-previous)%C.max_serial
        if delta==0 or delta>C.max_serial/2 then return end
    end
    player._nw_pose_serial=serial
    if value==0 then stop(player);return end
    if not ((x==nil and z==nil) or (U.finite(x) and U.finite(z))) then return end
    if not eligible(player,wand,wand) then stop(player,true);return end
    enter(player,wand)
    lease(player,wand)
    face(player,x,z)
end

-- Local input adapter: nil disarms immediately; a held wand renews the lease
-- and aim at a bounded rate. This never sends or performs a cast action.
function M.update(pc,wand,point)
    local G=globals
    if not G then return end
    if not Mode.enabled() then wand=nil end
    local input=pc._nw_pose_input
    if not input then
        if not wand then return end
        input={serial=0}
        pc._nw_pose_input=input
    end
    local now=G.GetTime()
    if wand==input.wand and (not wand or now<input.next_send) then return end
    input.wand=wand
    input.next_send=now+C.heartbeat
    input.serial=input.serial%C.max_serial+1
    local x,z
    if point and U.finite(point.x) and U.finite(point.z) then x,z=point.x,point.z end
    if G.TheWorld.ismastersim then
        receive(pc.inst,wand and 1 or 0,input.serial,wand,x,z)
    else
        G.SendModRPCToServer(G.MOD_RPC.nw_weave.hold_pose,wand and 1 or 0,input.serial,wand,x,z)
    end
end

function M.install(env,G)
    globals=G
    env.AddModRPCHandler("nw_weave","hold_pose",receive)
    env.AddStategraphState("wilson",G.State{
        name=STATE,tags={"idle","canrotate"},
        onenter=function(player)
            player.sg.statemem.recoil=0
            player.sg.statemem.level=0
            player.sg.statemem.recoil_time=GetTime()
            player.sg.statemem.extending=true
            player.AnimState:PlayAnimation(ANIM.pre)
            player.AnimState:PushAnimation(ANIM.loop,true)
        end,
        onupdate=function(player)
            if player.sg.statemem.releasing then
                if not player.sg.statemem.post then
                    if not eligible(player,player.sg.statemem.wand) then begin_post(player);return end
                    decay_recoil(player)
                    render_recoil(player)
                    if player.sg.statemem.recoil==0 or pending(player) then begin_post(player) end
                elseif player.AnimState:AnimDone() and not pending(player) then
                    player.sg:GoToState("idle")
                end
                return
            end
            local hold=player._nw_pose_hold
            if not hold or not eligible(player,hold.wand) then stop(player,true);return end
            decay_recoil(player)
            render_recoil(player)
            if hold.transient and not player.AnimState:IsCurrentAnimation(ANIM.pre) then stop(player) end
        end,
        onexit=cancel_lease,
    })
    env.AddPlayerPostInit(function(player)
        local function deactivate()
            local pc=player.components.playercontroller
            if player==G.ThePlayer and pc then M.update(pc,nil) end
            if G.TheWorld.ismastersim then stop(player,true) end
        end
        player:ListenForEvent("playerdeactivated",deactivate)
        player:ListenForEvent("onremove",function() cancel_lease(player) end)
        if not G.TheWorld.ismastersim then return end
        player._nw_pose_on_cast=cast_success
        player._nw_pose_ensure=ensure
        player:ListenForEvent("attacked",function() stop(player,true) end)
        player:ListenForEvent("death",function() stop(player,true) end)
        player:ListenForEvent("unequip",function(_,data)
            local hold=player._nw_pose_hold
            if hold and ((data and data.eslot==G.EQUIPSLOTS.HANDS) or Cast.hand(player)~=hold.wand) then
                stop(player,true)
            end
        end)
    end)
end

return M
