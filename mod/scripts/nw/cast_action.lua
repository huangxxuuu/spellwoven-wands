local C=require("nw/constants/casting").aim
local U=require("nw/util")
local Direction=require("nw/cast_direction")
local M={}
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
    if not player or M.hand(player)~=wand or player._nw_editing or player:HasTag("playerghost")
        or not inrange(player,pos) then return false end
    local combat=player.replica and player.replica.combat
    if combat and combat:InCooldown() then return false end
    if TheWorld.ismastersim then
        if (player._nw_edit_until or 0)>GetTime() then return false end
        return wand.components.nw_wand:CanCast(player)
    end
    return wand._nw_ready:value() and wand._nw_cancast:value()
end
function M.point(wand,player,pos,actions,right)
    if right and M.available(wand,player,pos) and TheWorld.Map:IsPassableAtPoint(pos.x,0,pos.z,true) then actions[#actions+1]=ACTIONS.NW_CAST end
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
        if not Direction.uses_mouse(player) or not target then return nil,true end
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
    if act._nw_done or not act.invobject or M.hand(act.doer)~=act.invobject
        or (act.doer._nw_edit_until or 0)>GetTime() then return false end
    if not act._nw_checked then M.prepare(act) end
    if not inrange(act.doer,act:GetActionPoint()) then return false end
    return act._nw_plan~=nil and act.invobject.components.nw_wand:CanCast(act.doer,act._nw_plan) or false
end
function M.server_state(player,act)
    if M.valid(act) and not player.components.combat:InCooldown() then return "attack" end
end
function M.client_state(player,act)
    local pos=M.aim_point(act)
    if M.available(act.invobject,player,pos) then return "attack" end
end
function M.perform(act)
    if not M.valid(act) then return false end
    act._nw_done=true
    local target=act._nw_aim_target
    local pos=target and target:IsValid() and target:GetPosition() or act:GetActionPoint()
    return act.invobject.components.nw_wand:Cast(act.doer,pos,act._nw_plan)
end
return M
