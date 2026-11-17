local C=require("nw/constants/casting").aim
local POSE=require("nw/constants/casting").pose
local U=require("nw/util")
local Direction=require("nw/cast_direction")
local Mode=require("nw/cast_mode")
local Binding=require("nw/cast_binding")
local M={}
local INSTANT_BLOCKED_TAGS={"busy","attack","moving","sleeping","frozen","dead","nointerrupt","playerghost"}
function M.pose_state(player)
    local sg=player.sg
    local rider=(player.components and player.components.rider) or (player.replica and player.replica.rider)
    local mounted_idle=sg and sg.currentstate and POSE.mounted_idle_states[sg.currentstate.name]
        and rider and rider:IsRiding()
    -- An idle tag also occurs on special states (hiding, mounts, emotes).
    -- Only these native, stationary idle variations may yield to casting.
    if sg and sg.currentstate and not POSE.idle_states[sg.currentstate.name] and not mounted_idle then return false end
    if TheWorld.ismastersim and not (sg and sg.currentstate) then return false end
    for _,tag in ipairs(INSTANT_BLOCKED_TAGS) do
        if player:HasTag(tag) or (sg and sg:HasStateTag(tag)) then return false end
    end
    local pc=player.components and player.components.playercontroller
    return not pc or (pc:IsEnabled() and not pc:IsBusy())
end
local function instant_state(player)
    if not M.pose_state(player) then return false end
    local combat=(player.components and player.components.combat) or (player.replica and player.replica.combat)
    if combat and combat:InCooldown() then return false end
    return true
end
local function instant_blocked(player)
    return not instant_state(player) or (TheWorld.ismastersim
        and (player._nw_instant_casting or player._nw_instant_cast_tick==GetTick()))
end
local function face(player,pos)
    local loco=player.components and player.components.locomotor
    if loco then loco:FaceMovePoint(pos.x,0,pos.z)
    elseif player.FacePoint then player:FacePoint(pos.x,0,pos.z) end
end
function M.hand(player)
    local inv=player and player.replica and player.replica.inventory
    inv=inv or (player and player.components.inventory)
    local item=inv and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    return item and ((item.components and item.components.nw_wand)
        or (item.HasTag and item:HasTag("nw_wand"))) and item or nil
end
function M.stop(player)
    local act=player.GetBufferedAction and player:GetBufferedAction()
    if act and act.action==ACTIONS.NW_CAST then player:ClearBufferedAction() end
end
local function inrange(player,pos)
    if not pos or not U.finite(pos.x) or not U.finite(pos.z) then return false end
    local x,_,z=player.Transform:GetWorldPosition()
    local dsq=(pos.x-x)^2+(pos.z-z)^2
    return dsq>=C.min_distance_squared and dsq<=C.max_distance_squared
end
function M.available(wand,player,pos)
    if not Mode.ready() or not player or M.hand(player)~=wand or player._nw_editing or player:HasTag("playerghost")
        or not inrange(player,pos) then return false end
    if Mode.enabled() and instant_blocked(player) then return false end
    local combat=player.replica and player.replica.combat
    if combat and combat:InCooldown() then return false end
    if TheWorld.ismastersim then
        if (player._nw_edit_until or 0)>GetTime() then return false end
        return wand.components.nw_wand:CanCast(player)
    end
    return wand._nw_ready:value() and (Mode.enabled() or wand._nw_cancast:value())
end
function M.input_allowed(player)
    if player._nw_cast_pick then return player._nw_cast_pick=="cast" end
    -- Native RPC validation explicitly requests the same action selected locally.
    if TheWorld.ismastersim and CLIENT_REQUESTED_ACTION~=nil then return CLIENT_REQUESTED_ACTION==ACTIONS.NW_CAST end
    local pc=player.components and player.components.playercontroller
    if player._nw_cast_mouse_input==false
        or (player==ThePlayer and pc and pc.UsingMouse and not pc:UsingMouse()) then return true end
    return Binding.get(player)=="mouse:1001"
end
function M.point(wand,player,pos,actions,right)
    if right and M.input_allowed(player) and M.available(wand,player,pos)
        and TheWorld.Map:IsPassableAtPoint(pos.x,0,pos.z,true) then actions[#actions+1]=ACTIONS.NW_CAST end
end
function M.input_action(player,native)
    local picker=player.components.playeractionpicker
    local previous=player._nw_cast_pick
    player._nw_cast_pick=native and "native" or "cast"
    -- Omitted coordinates select the native local-input path, including its
    -- visibility checks. Explicit coordinates are reserved for remote RPCs.
    local ok,_,action=pcall(picker.DoGetMouseActions,picker)
    player._nw_cast_pick=previous
    if not ok then error(_,0) end
    return action
end
function M.equipped(wand,player,target,actions,right)
    if Direction.uses_mouse(player) then return end
    if target and target.Transform then
        M.point(wand,player,target:GetPosition(),actions,right)
    end
end
function M.install_picker(picker)
    if picker.rightclickoverride==picker._nw_direction_callback and picker._nw_direction_callback then return end
    local previous=picker.rightclickoverride
    picker._nw_direction_callback=function(player,target,position)
        if previous then
            local actions,usedefault=previous(player,target,position)
            if not usedefault or (actions and #actions>0) then return actions,usedefault end
        end
        if not M.input_allowed(player) or not Direction.uses_mouse(player) or not target then return nil,true end
        local wand=M.hand(player)
        local inv=player.replica and player.replica.inventory
        if not wand or not inv or inv:GetActiveItem() or picker.containers[target]
            or target:HasTag("walkableplatform") then return nil,true end
        local special=picker:GetSteeringActions(player,position,true)
            or picker:GetCannonAimActions(player,position,true)
            or picker:GetGolfAimActions(position,true)
        if special then return special,false end
        local actions={}
        M.point(wand,player,position,actions,true)
        if #actions==0 then return nil,true end
        return picker:SortActionList(actions,position,wand),false
    end
    picker.rightclickoverride=picker._nw_direction_callback
end
function M.aim_point(act)
    if act._nw_direction_set or Direction.uses_mouse(act.doer) then return act:GetActionPoint() end
    return act.target and act.target:IsValid() and act.target:GetPosition() or act:GetActionPoint()
end
function M.prepare(act)
    if not act._nw_direction_set then
        if not Direction.uses_mouse(act.doer) and act.target and act.target:IsValid() then
            act:SetActionPoint(act.target:GetPosition())
            act._nw_aim_target=act.target
        end
        act._nw_direction_set=true
    end
    act.target=nil;act.initialtargetowner=nil
    if TheWorld.ismastersim and not act._nw_checked then
        act._nw_checked=true
        local wand=act.invobject
        if wand and M.available(wand,act.doer,act:GetActionPoint()) then
            local ok,_,plan=wand.components.nw_wand:CanCast(act.doer)
            if ok then act._nw_plan=plan end
        end
    end
end
function M.valid(act)
    if not Mode.ready() or act._nw_done or not act.doer or not act.invobject or M.hand(act.doer)~=act.invobject
        or (act.doer._nw_edit_until or 0)>GetTime() then return false end
    if Mode.enabled() and (instant_blocked(act.doer) or act.doer._nw_editing
        or act.doer:HasTag("playerghost")) then return false end
    if not act._nw_checked then M.prepare(act) end
    if not inrange(act.doer,act:GetActionPoint()) then return false end
    return act._nw_plan~=nil and act.invobject.components.nw_wand:CanCast(act.doer,act._nw_plan) or false
end
function M.server_state(player,act)
    if M.valid(act) and not player.components.combat:InCooldown() then return "attack" end
end
function M.client_state(player,act)
    local pos=M.aim_point(act)
    if M.available(act.invobject,player,pos) then
        if Mode.enabled() then
            face(player,pos)
            -- Returning nil also clears this preview in EntityScript, without a failure callback.
            player:PerformPreviewBufferedAction()
        else return "attack" end
    end
end
function M.perform(act)
    if not TheWorld.ismastersim then return false end
    if Mode.enabled() then
        local player,wand=act.doer,act.invobject
        -- This action may beat its hold RPC. Enter the server pose before
        -- readiness checks and before Wand:Cast samples the current wand tip.
        -- Pose entry must preserve the current NW_CAST buffered action.
        if not Mode.ready() or act._nw_done or not player or not wand or M.hand(player)~=wand
            or not inrange(player,M.aim_point(act)) or not M.pose_state(player)
            or player._nw_instant_casting or player._nw_instant_cast_tick==GetTick()
            or not player._nw_pose_ensure or not player._nw_pose_ensure(player,wand) then return false end
    end
    if not M.valid(act) then return false end
    act._nw_done=true
    local target=act._nw_aim_target
    local pos=target and target:IsValid() and target:GetPosition() or act:GetActionPoint()
    if not Mode.enabled() then return act.invobject.components.nw_wand:Cast(act.doer,pos,act._nw_plan) end
    if not inrange(act.doer,pos) then return false end
    face(act.doer,pos)
    act.doer._nw_instant_casting=true
    local ok,reason=act.invobject.components.nw_wand:Cast(act.doer,pos,act._nw_plan)
    act.doer._nw_instant_casting=nil
    if ok then
        act.doer._nw_instant_cast_tick=GetTick()
        -- One successful cast, not one projectile: this presentation callback
        -- cannot gate readiness, spend mana or change the casting state.
        if act.doer._nw_pose_on_cast then act.doer._nw_pose_on_cast(act.doer,act.invobject) end
    end
    return ok,reason
end
return M
