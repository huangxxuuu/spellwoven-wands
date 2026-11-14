local M={}
local Policy=require("nw/target_policy")
M.flags=Policy.flags
M.infinite_pierce=Policy.infinite_pierce
M.object_tags={"structure","wall","boat","walkableplatform","plant","tree","boulder","CHOP_workable","MINE_workable","DIG_workable","HAMMER_workable","pickable","fishable","oceanfishable","nw_breakable","nw_spell_placement"}
M.scan_exclude={"INLIMBO","FX","DECOR"}
local combat_tags={"_combat","wall"}
local object_tags={"_combat","wall"}
for _,tag in ipairs(M.object_tags) do object_tags[#object_tags+1]=tag end
local selected_tags={}
for _,tag in ipairs(object_tags) do selected_tags[#selected_tags+1]=tag end
for _,tag in ipairs({"_health","locomotor","_locomotor","player","hostile","alwayshostile","animal","smallcreature","monster","character","insect","companion"}) do
    selected_tags[#selected_tags+1]=tag
end
function M.scan_tags(flags,force_objects)
    local scope=flags and flags.targets
    if scope or flags and flags._nw_target_bypass then return selected_tags end
    return force_objects and object_tags or combat_tags
end
function M.allows_category(flags,category)
    local scope=flags and flags.targets
    return not scope or scope[category]==true
end
function M.scope_key(flags)
    local scope=flags and flags.targets
    if not scope then return "default" end
    local keys={}
    for category,enabled in pairs(scope) do if enabled then keys[#keys+1]=category end end
    table.sort(keys)
    return "selected:"..table.concat(keys,",")
end
function M.valid(e)
    return e and e:IsValid() and not (e.IsInLimbo and e:IsInLimbo())
        and not e:HasTag("playerghost") and not e:HasTag("FX")
        and not (e.components.health and e.components.health:IsDead())
end
local function live_owner(owner)
    return owner and owner:IsValid() and not (owner.components.health and owner.components.health:IsDead())
end
function M.object(e)
    local stored=e._nw_stored and e._nw_stored.p
    if stored and (stored.id=="crystal_mine" or stored.id=="sleep_crystal" or stored.id=="payload_egg") then return "building" end
    if e:HasTag("wall") or e:HasTag("structure") or e:HasTag("boat") or e:HasTag("walkableplatform")
        or e.components.hullhealth or e.components.boatphysics or e.components.walkableplatform then return "building" end
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
    if not scope or not M.valid(e) or e:HasTag("nw_decoy") then return false end
    if e==owner then return scope.self end
    if e:HasTag("player") then return scope.players_other end
    if e:HasTag("nw_test_target") then return scope.hostile end
    local kind=M.object(e)
    if kind then return scope[kind] end
    if e:HasTag("nw_breakable") then return false end
    local c=e.components.combat
    local f=e.components.follower
    local combat=owner and owner.components.combat
    if (f and f.leader and f.leader:HasTag("player")) or combat and combat.IsAlly and combat:IsAlly(e) then return scope.friendly end
    if e:HasTag("hostile") or e:HasTag("alwayshostile") or e:HasTag("nw_test_target")
        or c and c.target and c.target:HasTag("player") then return scope.hostile end
    if c or e.components.health or e.components.locomotor or e.brain
        or e:HasTag("animal") or e:HasTag("smallcreature") or e:HasTag("monster")
        or e:HasTag("character") or e:HasTag("insect") then return scope.neutral end
    return false
end
function M.selected_object(owner,e,flags)
    local scope=flags and flags.targets
    return live_owner(owner) and scope and (scope.nature or scope.building)
        and M.valid(e) and M.object(e) and M.matches(owner,e,scope)
end
function M.allowed(owner,e,flags)
    if not M.valid(e) then return false end
    if flags and flags._nw_target_bypass then return true end
    if not live_owner(owner) then return false end
    local scope=flags and flags.targets
    if scope then return M.matches(owner,e,scope) end
    if e:HasTag("nw_breakable") or e:HasTag("nw_decoy") then return false end
    local h,c=e.components.health,e.components.combat
    if not h or h:IsDead() or not c or not owner.components.combat then return false end
    if owner.components.health and owner.components.health:IsDead() then return false end
    if e==owner or e:HasTag("player") or e:HasTag("wall") then return false end
    local follower=e.components.follower
    if follower and follower.leader and follower.leader:HasTag("player") then return false end
    local combat=owner.components.combat
    if combat.IsAlly and combat:IsAlly(e) then return false end
    return owner.components.combat:CanTarget(e)
end
function M.selected(owner,e,flags)
    return M.allowed(owner,e,flags)
end
function M.selectable_prop(owner,e,flags)
    if not M.valid(e) or not e._nw_break then return false end
    if flags and flags._nw_target_bypass then return true end
    if flags and flags.targets and not M.matches(owner,e,flags.targets) then return false end
    return M.breakable(e) or require("nw/expanded_fields").can_break(e,owner)
end
function M.accepts(owner,e,flags,options)
    options=options or {}
    if e==options.exclude then return false end
    if options.breakables and M.selectable_prop(owner,e,flags) then return true end
    local scope=flags and flags.targets
    local selected
    if flags and flags._nw_target_bypass then
        selected=M.valid(e)
    elseif options.default_predicate and not scope then
        selected=live_owner(owner) and M.valid(e) and not e:HasTag("nw_breakable") and not e:HasTag("nw_decoy")
            and options.default_predicate(owner,e,flags)
    elseif options.default then
        selected=live_owner(owner) and M.valid(e) and (scope and M.matches(owner,e,scope)
            or not scope and not e:HasTag("nw_breakable") and not e:HasTag("nw_decoy"))
    else selected=M.selected(owner,e,flags) end
    if not selected then return false end
    for _,name in ipairs(options.components or {}) do
        if not e.components[name] then return false end
    end
    return not options.predicate or options.predicate(owner,e)
end
function M.query(owner,x,z,r,flags,options)
    local found={}
    for _,e in ipairs(require("nw/spell_effects").scan(x,z,r,flags,options and options.force_objects)) do
        if M.accepts(owner,e,flags,options) and e:GetDistanceSqToPoint(x,0,z)<=r*r then
            found[#found+1]=e
        end
    end
    return found
end
function M.damage(owner,e,amount,flags,p)
    if M.selectable_prop(owner,e,flags) then e._nw_break(owner);return true end
    if not M.accepts(owner,e,flags,{components={"health"}}) then return false end
    local health=e.components.health
    local before=health and health.currenthealth
    local damage=amount*require("nw/spell_effects").wet_mult(e,flags)
    if e.components.combat then require("nw/balance_damage").attack(p,owner,e,damage)
    else require("nw/balance_damage").delta(p,e,-damage,nil,"nw_spell",nil,owner) end
    require("nw/journal_damage").loss(owner,p,health,before)
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
    return M.selectable_prop(owner,e,flags) or M.allowed(owner,e,flags)
end
return M
