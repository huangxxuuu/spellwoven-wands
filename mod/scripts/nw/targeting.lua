local M={}
M.object_tags={"structure","wall","plant","tree","boulder","CHOP_workable","MINE_workable","DIG_workable","HAMMER_workable","pickable","fishable","oceanfishable"}
function M.object(e)
    if e:HasTag("wall") or e:HasTag("structure") then return "building" end
    if e:HasTag("fishable") or e:HasTag("oceanfishable") and not e.components.combat or e:HasTag("plant") or e:HasTag("tree") or e:HasTag("boulder") or e:HasTag("pickable") then return "nature" end
    local w=e.components.workable
    if w and w:GetWorkAction() then
        local id=w:GetWorkAction().id
        if id=="CHOP" or id=="DIG" or id=="MINE" then return "nature" end
        if id=="HAMMER" then return "building" end
    end
end
function M.only_self(flags)
    local scope=flags and flags.targets
    return scope and next(scope)=="self" and next(scope,"self")==nil
end
function M.matches(owner,e,scope)
    if not e:IsValid() or e:IsInLimbo() or e:HasTag("playerghost") or e:HasTag("FX")
        or e:HasTag("nw_breakable") or e:HasTag("nw_decoy") then return false end
    if e==owner then return scope.self end
    if e:HasTag("player") then return scope.players_other and TheNet:GetPVPEnabled() end
    if e:HasTag("nw_test_target") and scope.hostile then
        return e.components.health and not e.components.health:IsDead() and e.components.combat~=nil
    end
    local kind=M.object(e)
    if kind then return scope[kind] end
    local h,c=e.components.health,e.components.combat
    if not h or h:IsDead() or not c then return false end
    local f=e.components.follower
    if (f and f.leader and f.leader:HasTag("player")) or owner.components.combat:IsAlly(e) then return scope.friendly end
    if e:HasTag("hostile") or e:HasTag("alwayshostile") or e:HasTag("nw_test_target")
        or c.target and c.target:HasTag("player") then return scope.hostile end
    return scope.neutral
end
function M.selected_object(owner,e,flags)
    local scope=flags and flags.targets
    return scope and (scope.nature or scope.building) and M.object(e) and M.matches(owner,e,scope)
        and (not e.components.health or not e.components.health:IsDead())
end
function M.allowed(owner,e,flags)
    if not owner or not owner:IsValid() or not e:IsValid() or e:IsInLimbo()
        or e:HasTag("nw_breakable") or e:HasTag("nw_decoy") then return false end
    local h,c=e.components.health,e.components.combat
    if not h or h:IsDead() or not c or not owner.components.combat then return false end
    if owner.components.health and owner.components.health:IsDead() then return false end
    local scope=flags and flags.targets
    if scope then
        if not M.matches(owner,e,scope) then return false end
        if e==owner or M.object(e) then return true end
    else
        if e==owner or e:HasTag("player") or e:HasTag("wall") then return false end
        local follower=e.components.follower
        if follower and follower.leader and follower.leader:HasTag("player") then return false end
        local combat=owner.components.combat
        if combat.IsAlly and combat:IsAlly(e) then return false end
    end
    return owner.components.combat:CanTarget(e)
end
function M.damage(owner,e,amount,flags)
    if M.breakable(e) then e._nw_break(owner);return true end
    if not M.allowed(owner,e,flags) then return false end
    e.components.combat:GetAttacked(owner,amount*require("nw/spell_effects").wet_mult(e,flags))
    return true
end
function M.egg(e)
    return e:IsValid() and e._nw_break and e._nw_stored and e._nw_stored.p.id=="payload_egg"
end
function M.breakable(e)
    return e:IsValid() and e._nw_break and e._nw_stored
        and (e._nw_stored.p.id=="payload_egg" or e._nw_stored.p.id=="sleep_crystal")
end
function M.hittable(owner,e,flags)
    return M.breakable(e) or M.allowed(owner,e,flags)
end
return M
