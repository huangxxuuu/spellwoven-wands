local M = {}
local registered = {}
local shadow_prefabs = {
    crawlinghorror = true, terrorbeak = true, crawlingnightmare = true,
    nightmarebeak = true, shadow_rook = true, shadow_knight = true,
    shadow_bishop = true, stalker = true, stalker_forest = true,
    stalker_atrium = true, shadowthrall_hands = true,
    shadowthrall_horns = true, shadowthrall_wings = true,
}
local large_prefabs = { bat_boss = true }

function M.register(prefab, profile)
    assert(type(prefab) == "string" and type(profile) == "table")
    assert(profile.kind == "small" or profile.kind == "normal"
        or profile.kind == "large" or profile.kind == "shadow")
    registered[prefab] = profile
end

function M.get(inst)
    return registered[inst.prefab]
end

function M.classify(inst)
    if not inst or not inst:IsValid() or inst.isplayer
        or inst:HasTag("player") or inst:HasTag("playerghost")
        or inst:HasTag("INLIMBO") then
        return nil
    end
    local c = inst.components
    if not c or not c.health or c.health:IsDead() then
        return nil
    end
    local profile = registered[inst.prefab]
    if shadow_prefabs[inst.prefab] or inst:HasTag("shadowcreature")
        or inst:HasTag("shadow") or inst:HasTag("shadowthrall")
        or inst:HasTag("shadowboss") or (profile and profile.kind == "shadow") then
        return "shadow"
    elseif large_prefabs[inst.prefab] or inst:HasTag("epic") or inst:HasTag("largecreature")
        or (profile and profile.kind == "large") then
        return "large"
    end
    if inst:HasTag("structure") or not c.locomotor or not (inst.brain or inst.brainfn) then
        return nil
    end
    if inst:HasTag("smallcreature") or inst.prefab == "rabbit"
        or (profile and profile.kind == "small") then
        return "small"
    end
    return "normal"
end

return M
