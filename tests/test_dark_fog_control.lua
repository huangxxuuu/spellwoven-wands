local Control = require("nw/dark_fog_control")
local Profiles = require("nw/dark_fog_profiles")
TheWorld = { ismastersim = true }
local clock = 10
GetTime = function() return clock end
local function tick(e, time, covered)
    clock = time
    Control.update(e, time, covered ~= false)
end
local navigable = true
FindWalkableOffset = function(_, angle, _, attempts, _, ignorewalls, _, water)
    assert(attempts == 1 and not ignorewalls)
    if navigable then return { x = 1, z = 0 }, angle end
end
FindSwimmableOffset = FindWalkableOffset
distsq = function(a, b) return (a.x-b.x)^2 + (a.z-b.z)^2 end

local function entity(kind, x, z)
    local e = { prefab = kind or "hound", x = x or 0, z = z or 0,
        tags = {}, components = {}, brain = {}, events = {}, reasons = {},
        moves = 0, attacks = 0, reads = 0, stops = 0, clears = 0, sg_tags = {} }
    function e:IsValid() return not self.removed end
    function e:HasTag(tag) return self.tags[tag] or false end
    function e:HasAnyTag(...)
        for _, tag in ipairs({...}) do if self:HasTag(tag) then return true end end
        return false
    end
    function e:IsAsleep() return self.asleep end
    function e:IsInLimbo() return self:HasTag("INLIMBO") end
    function e:IsInLight() return true end
    function e:IsNear(other, radius) return (self.x-other.x)^2+(self.z-other.z)^2 <= radius^2 end
    function e:GetPosition() return { x = self.x, y = 0, z = self.z } end
    function e:GetPhysicsRadius() return 0 end
    function e:StopBrain(reason) self.reasons[reason] = true end
    function e:RestartBrain(reason) self.reasons[reason] = nil end
    function e:ClearBufferedAction() self.clears = self.clears + 1; self.action = nil end
    function e:ListenForEvent(name, fn, source)
        if source then return end
        self.events[name] = self.events[name] or {}; self.events[name][fn] = true
    end
    function e:RemoveEventCallback(name, fn, source)
        if source then return end
        if self.events[name] then self.events[name][fn] = nil end
    end
    function e:PushEvent(name, data)
        if name == "doattack" then self.attacks = self.attacks + 1 end
        local copy = {}; for fn in pairs(self.events[name] or {}) do copy[#copy+1] = fn end
        for _, fn in ipairs(copy) do fn(self, data) end
    end
    function e:StartUpdatingComponent() end
    function e:StopUpdatingComponent() end
    e.Transform = { GetWorldPosition = function()
        e.reads = e.reads + 1; return e.x, 0, e.z
    end }
    e.sg = { HasStateTag = function(_, tag) return e.sg_tags[tag] or false end }
    e.components.health = { IsDead = function() return e.dead end }
    e.components.locomotor = {
        Stop = function() e.stops = e.stops + 1 end,
        SetBufferedAction = function(_, action) e.loco_action = action end,
        WalkInDirection = function(_, heading) e.moves = e.moves + 1; e.heading = heading end,
        GetWalkSpeed = function() return 4 end,
        SetExternalSpeedMultiplier = function(_, source, key, speed)
            e.speed_calls = (e.speed_calls or 0) + 1; e.speed = speed
        end,
        RemoveExternalSpeedMultiplier = function() e.speed = nil end,
    }
    e.replica = { combat = {
        CanTarget = function(_, target) return target and target ~= e and not target.dead end,
        IsValidTarget = function(_, target) return target and target:IsValid() and not target.dead end,
        SetLastTarget = function() end,
    } }
    local combat = { inst = e, attackrange = 1, min_attack_period = 2,
        laststartattacktime = -100, canattack = true }
    if NativeCombat then
        setmetatable(combat, { __index = NativeCombat })
    else
        function combat:SetTarget(target) self.target = target end
        function combat:CanTarget(target) return e.replica.combat:CanTarget(target) end
        function combat:CanAttack(target)
            return target ~= nil and e:IsNear(target, self.attackrange)
                and clock - self.laststartattacktime >= self.min_attack_period
        end
        function combat:TryAttack(target)
            if not self:CanAttack(target) then return false end
            e:PushEvent("doattack", { target = target }); return true
        end
    end
    e.components.combat = combat
    e.tags._combat = true
    return e
end

-- Players always excluded, even with shadow/epic tags. Buildings are not fauna.
local player = entity(); player.tags.player = true; player.tags.shadow = true
assert(Control.classify(player) == nil)
tick(player, 10); assert(not player._nw_dark_control)
local building = entity(); building.tags.structure = true
assert(Control.classify(building) == nil)
local brainless = entity(); brainless.brain = nil
assert(Control.classify(brainless) == nil)
local aligned = entity(); aligned.tags.shadow_aligned = true
assert(Control.classify(aligned) == "normal")
for _, name in ipairs({ "rocky_boss_shadow", "bat_boss_shadow", "worm_boss_shadow", "shadowthrall_centipede_head" }) do
    local e = entity(name); e.tags.shadowthrall = true; e.tags.epic = true
    assert(Control.classify(e) == "shadow", "shadow family precedes boss classification")
end
local shrouden = entity("shrouden"); shrouden.tags.shadowboss = true
assert(Control.classify(shrouden) == "shadow")
assert(Control.classify(entity("bat_boss")) == "large")
local spat = entity("spat"); spat.tags.largecreature = true
assert(Control.classify(spat) == "large", "spat follows the requested boss response")
spat.tags.shadow = true
assert(Control.classify(spat) == "shadow", "shadow immunity retains priority")
for _, name in ipairs({ "beequeen", "twinofterror1", "twinofterror2" }) do
    local e = entity(name); e.tags.epic = true; e.tags.largecreature = true
    e.tags.flying = true; e.tags.shadow_aligned = true
    assert(Control.classify(e) == "large", "flying and shadow alignment do not exempt these bosses")
end
local fixedboss = entity("crabking"); fixedboss.tags.epic = true
fixedboss.components.locomotor = nil; fixedboss.brain = nil
assert(Control.classify(fixedboss) == "large")
fixedboss.tags.shadow = true
assert(Control.classify(fixedboss) == "shadow")
tick(fixedboss, 9); assert(fixedboss._nw_dark_control.speed_unavailable)
Control.leave(fixedboss)

-- Continuous union coverage cannot renew fear; exit grants a fixed immunity.
local rabbit = entity("rabbit"); rabbit.action = {}; rabbit.loco_action = {}
tick(rabbit, 10); assert(rabbit._nw_dark_control.phase == "fear_hold")
assert(rabbit.moves == 0 and rabbit.action == nil and rabbit.loco_action == nil)
tick(rabbit, 10.9); assert(rabbit.moves == 0)
tick(rabbit, 11); assert(rabbit.moves == 1)
tick(rabbit, 11.2); assert(rabbit._nw_dark_control.entered == 10)
tick(rabbit, 11.3, false); assert(not rabbit._nw_dark_control and not next(rabbit.reasons))
tick(rabbit, 11.4); assert(not rabbit._nw_dark_control)
Control.leave(rabbit); tick(rabbit, 21.29); assert(not rabbit._nw_dark_control)
tick(rabbit, 21.3); assert(rabbit._nw_dark_control.phase == "fear_hold")
Control.leave(rabbit); Control.leave(rabbit)

local shadow = entity("crawlinghorror"); shadow.tags.epic = true
local original_set = shadow.components.combat.SetTarget
shadow.components.combat.target = player
tick(shadow, 20); tick(shadow, 21)
assert(shadow.speed == 1.25 and shadow.speed_calls == 1 and not next(shadow.reasons))
assert(shadow.components.combat.target == player and shadow.components.combat.SetTarget == original_set)
tick(shadow, 21.1, false); assert(not shadow.speed)
tick(shadow, 30); assert(not shadow.speed and shadow.speed_calls == 1)
tick(shadow, 31.1); assert(shadow.speed == 1.25 and shadow.speed_calls == 2)
Control.leave(shadow)

-- Near hostile candidate comes from the original targetfn, not CanTarget alone.
local hound, far, close = entity(), entity("player", 9), entity("player", 2)
far.tags.player = true; close.tags.player = true
local combat = hound.components.combat
combat.target = far
combat.targetfn = function(inst)
    for _, target in ipairs({far, close}) do
        if inst.components.combat:CanTarget(target) then return target end
    end
end
tick(hound, 30); assert(combat.target == nil and hound._nw_dark_control.phase == "panic")
tick(hound, 30.1); assert(combat.target == close and hound.attacks == 0 and hound.moves == 1)
close.x = .5; tick(hound, 30.2); assert(hound.attacks == 1)
combat.laststartattacktime = 30.2
tick(hound, 30.3); assert(hound.attacks == 1, "native cooldown must be retained")
close.x = 3; tick(hound, 30.4); local angle = hound._nw_dark_control.last_direction
-- Crossing perception and then turning sharply cannot alter the recorded heading.
close.x = 5; close.z = 20
local reads = close.reads
tick(hound, 30.5); assert(combat.target == nil and hound._nw_dark_control.sensed_target == nil)
assert(hound._nw_dark_control.phase == "blind_continue")
assert(hound.heading == angle * 180 / math.pi and close.reads == reads)
close.z = -20; tick(hound, 30.7)
assert(hound.heading == angle * 180 / math.pi and close.reads == reads)
tick(hound, 31.31); assert(hound._nw_dark_control.phase == "panic")
combat:SetTarget(far); assert(combat.target == nil, "ranged retaliation/shared aggro cannot relock")
assert(not combat:CanAttack(far))
close.x = 1; close.z = 0
combat:SetTarget(close); assert(combat.target == close, "native near retaliation is accepted")
Control.leave(hound)
combat:SetTarget(far); assert(combat.target == far)

-- No targetfn/aggro source means no spontaneous attack, even when CanTarget is true.
local neutral = entity("neutral")
tick(neutral, 40); tick(neutral, 40.1)
assert(neutral.components.combat.target == nil and neutral.attacks == 0)
local follower = entity("pigman")
follower.components.follower = { GetLeader = function() return close end }
follower.components.combat.targetfn = function(inst)
    if close ~= inst.components.follower:GetLeader() and inst.components.combat:CanTarget(close) then return close end
end
tick(follower, 40); tick(follower, 40.1); assert(follower.attacks == 0)
Control.leave(neutral); Control.leave(follower)

-- Other brain stops survive exit; own wrappers do not clobber later mod hooks.
local frozen = entity("rabbit"); frozen.reasons.frozen = true
tick(frozen, 50)
frozen.components.freezable = { IsFrozen = function() return true end }
tick(frozen, 50.1)
assert(not frozen.reasons.nw_fog_control and frozen.reasons.frozen)
assert(not frozen._nw_dark_control.active and frozen.moves == 0)
frozen.components.freezable = nil
tick(frozen, 51.1); assert(frozen._nw_dark_control.phase == "blind_wander")
local hook = frozen.components.combat.SetTarget
local other = function(self, target) return hook(self, target) end
frozen.components.combat.SetTarget = other
Control.leave(frozen)
assert(frozen.reasons.frozen and frozen.components.combat.SetTarget == other)
frozen.components.combat:SetTarget(far); assert(frozen.components.combat.target == far)

local sleeping = entity(); tick(sleeping, 60)
sleeping.asleep = true; sleeping:PushEvent("entitysleep")
assert(not sleeping._nw_dark_control and not next(sleeping.reasons))
sleeping.asleep = false; tick(sleeping, 69.9); assert(not sleeping._nw_dark_control)
tick(sleeping, 70); assert(sleeping._nw_dark_control)
Control.leave(sleeping)
local removed = entity(); tick(removed, 60)
removed.RestartBrain = function() error("retiring entity must not rejoin BrainManager") end
removed.removed = true; removed:PushEvent("onremove")
assert(not removed._nw_dark_control and not next(removed.events.onremove))
local removed_shadow = entity("crawlinghorror"); tick(removed_shadow, 60)
removed_shadow.components.locomotor.RemoveExternalSpeedMultiplier = function()
    error("retiring entity must not update locomotor replication")
end
removed_shadow:PushEvent("onremove")
assert(not removed_shadow._nw_dark_control)
assert(not require("nw/dark_fog_immunity").is_immune(removed_shadow), "onremove clears immunity even before IsValid flips")
local dead = entity(); tick(dead, 60); dead.dead = true; dead:PushEvent("death")
assert(not dead._nw_dark_control)

-- Busy SG transactions/committed attacks are not forcibly idled or failed.
local attacking = entity("rabbit"); attacking.sg_tags.busy = true
attacking.action = {}; attacking.loco_action = {}
tick(attacking, 70)
assert(attacking.clears == 0 and attacking.stops == 0 and attacking.action)
tick(attacking, 71.1); assert(attacking.moves == 0)
attacking.sg_tags.busy = nil; tick(attacking, 71.2)
assert(attacking.clears == 1 and attacking.action == nil and attacking.moves == 1)
Control.leave(attacking)
navigable = false
local stranded = entity("rabbit"); tick(stranded, 80); tick(stranded, 81.1)
assert(stranded.moves == 0, "no passable offset must not walk into ocean/wall")
Control.leave(stranded); navigable = true

-- Large dispatch must not acquire ordinary hooks/brain stop/three-unit limit.
local previous_boss = package.loaded["nw/dark_fog_boss"]
local calls = 0
package.loaded["nw/dark_fog_boss"] = {
    update = function(inst) calls = calls + 1; inst._nw_dark_control = { kind = "large" } end,
    leave = function(inst) inst._nw_dark_control = nil end,
}
local boss = entity("deerclops"); boss.tags.epic = true
local boss_set = boss.components.combat.SetTarget
tick(boss, 90); assert(calls == 1 and not next(boss.reasons))
assert(boss.components.combat.SetTarget == boss_set)
boss.components.combat:SetTarget(far); assert(boss.components.combat.target == far)
Control.leave(boss); assert(not boss._nw_dark_control)
package.loaded["nw/dark_fog_boss"] = previous_boss

-- Real region/control integration: union exits, immediate expiry, rebuilt
-- pools and periodic scanning all share the same per-creature deadline.
local Fog = require("nw/dark_fog")
local Immunity = require("nw/dark_fog_immunity")
local world = entity("world"); world.ismastersim = true; TheWorld = world
function world:DoPeriodicTask(_, fn)
    return { fn = fn, Cancel = function(self) self.cancelled = true end }
end
local creatures = {}
TheSim = { FindEntities = function() return creatures end }
local function cloud(x, lifetime)
    local source = entity("cloud", x)
    function source:DoTaskInTime(delay, fn)
        local task = { fn = function() fn(self) end, delay = delay,
            Cancel = function(self) self.cancelled = true end }
        return task
    end
    return Fog.register(source, { userid = "immunity-test" }, lifetime or 4)
end
local function scan(t) clock = t; Fog.refresh(world) end
local union = entity("rabbit"); creatures = { union }
clock = 100
local left, right = cloud(-1), cloud(1)
scan(100); assert(union._nw_dark_control)
Fog.dissipate(left)
assert(union._nw_dark_control and not Immunity.is_immune(union), "remaining overlap keeps one affected session")
local old_task = world._nw_dark_fog.task
clock = 101; Fog.dissipate(right)
assert(not union._nw_dark_control and Immunity.is_immune(union) and not world._nw_dark_fog)
assert(old_task.cancelled, "zero clouds release the shared scan while immunity survives")
local replacement = cloud(0)
scan(102); assert(Fog.contains(world, union) and not union._nw_dark_control)
for _, t in ipairs({ 103, 105, 110.99 }) do
    union.x = 20; scan(t); union.x = 0; scan(t)
    assert(not union._nw_dark_control and Immunity.is_immune(union), "immune edge crossings never extend or remove the deadline")
end
clock = 111; world._nw_dark_fog.task.fn()
assert(union._nw_dark_control and not Immunity.is_immune(union), "periodic scan reapplies at exactly ten seconds in existing fog")
-- Trigger the actual source expiry callback, including zero-pool cleanup.
clock = 112; replacement._nw_dark_expiry.fn()
assert(Immunity.is_immune(union) and not union._nw_dark_control and not world._nw_dark_fog)
clock = 122; assert(not Immunity.is_immune(union))
replacement = cloud(0); union.x = 20; scan(122)
assert(not union._nw_dark_control)
union.x = 0; scan(123); assert(union._nw_dark_control, "entry after expiry applies immediately")
clock = 124; Fog.dissipate(replacement)

-- Never-affected entities do not get an exit cooldown. Deferred disabled
-- control and unsupported bosses must remain eligible when they can act.
local deferred = entity("rabbit")
deferred.components.freezable = { IsFrozen = function() return true end }
creatures = { deferred }; replacement = cloud(0); scan(130)
assert(deferred._nw_dark_control and not deferred._nw_dark_control.active)
Fog.dissipate(replacement); assert(not Immunity.is_immune(deferred))
deferred.components.freezable = nil; replacement = cloud(0); scan(130.1)
assert(deferred._nw_dark_control.active)
deferred.components.freezable = { IsFrozen = function() return true end }; scan(130.2)
assert(not deferred._nw_dark_control.active and not Immunity.is_immune(deferred))
deferred.components.freezable = nil; scan(130.3)
assert(deferred._nw_dark_control.active and not Immunity.is_immune(deferred), "temporary suspension retains the covered session")
deferred.tags.shadow = true; scan(130.4)
assert(not deferred._nw_dark_control and not deferred.speed and Immunity.is_immune(deferred), "classification change cannot bypass new immunity in the same tick")
Fog.dissipate(replacement)
local fresh, unsupported = entity(), entity("unadapted_boss"); unsupported.tags.epic = true
creatures = { fresh, unsupported }; replacement = cloud(0); scan(140)
assert(fresh._nw_dark_control and not unsupported._nw_fog_boss_wait)
Fog.dissipate(replacement)
assert(not Immunity.is_immune(unsupported))
fresh.dead = true; fresh:PushEvent("death")
assert(not Immunity.is_immune(fresh), "dead creatures cannot retain effective immunity")
local removed_immune = entity(); tick(removed_immune, 150); tick(removed_immune, 151, false)
removed_immune.removed = true; removed_immune:PushEvent("onremove")
assert(not Immunity.is_immune(removed_immune))

-- Expose fixtures only to the optional authoritative combat/retarget runner.
if NativeCombat then
    DarkFogNativeFixtures = { entity = entity, tick = tick }
end
print("dark_fog_control: classification, overlap, hostility, blind heading, cooldowns, lifecycle, safe movement and boss boundary")
