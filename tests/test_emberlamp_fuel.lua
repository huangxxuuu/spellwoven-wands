-- Exercise the production prefab against a deterministic clock. Component
-- doubles preserve native machine callback order and infinite-stack removal.
local now, tasks, spilled = 0, {}, 0
local noop = function() end
GetTime = function() return now end
Asset = noop
Prefab = function(name, fn) return { name = name, fn = fn } end
MakePlacer = noop
MakeObstaclePhysics = noop
package.preload.prefabutil = function() return {} end
TheWorld = { ismastersim = true }
ACTIONS = { HAMMER = {} }

local function surface()
    return setmetatable({}, { __index = function() return noop end })
end
local function entity()
    local e = { components = {}, events = {}, tags = {}, valid = true }
    function e:IsValid() return self.valid end
    function e:IsAsleep() return false end
    function e:AddTag(tag) self.tags[tag] = true end
    function e:RemoveTag(tag) self.tags[tag] = nil end
    function e:HasTag(tag) return self.tags[tag] == true end
    function e:ListenForEvent(name, fn, source)
        source = source or self
        source.events[name] = source.events[name] or {}
        table.insert(source.events[name], { target = self, fn = fn })
    end
    function e:RemoveEventCallback(name, fn, source)
        for _, event in ipairs((source or self).events[name] or {}) do
            if event.fn == fn and event.target == self then event.removed = true end
        end
    end
    function e:PushEvent(name)
        for _, event in ipairs(self.events[name] or {}) do
            if not event.removed then event.fn(event.target) end
        end
    end
    function e:Remove() self:PushEvent("onremove"); self.valid = false end
    function e:DoTaskInTime(delay, fn)
        local task = { owner = self, at = now + delay, fn = fn }
        task.Cancel = function(self) self.cancelled = true end
        table.insert(tasks, task)
        return task
    end
    function e:DoPeriodicTask(period, fn)
        local task = self:DoTaskInTime(period, fn)
        task.period = period
        return task
    end
    function e:AddComponent(name)
        local c = { inst = self }
        if name == "container" then
            c.WidgetSetup = noop
            c.EnableInfiniteStackSize = noop
            c.GetItemInSlot = function(self) return self.item end
            c.GiveItem = function(self, item) self.item = item; self.inst:PushEvent("itemget") end
            c.Withdraw = function(self)
                local item = self.item
                self.item = nil
                self.inst:PushEvent("itemlose")
                return item
            end
            c.ConsumeByName = function(self, name, amount)
                assert(self.item.prefab == name)
                local size = self.item.components.stackable:StackSize()
                if size > amount then
                    self.item.components.stackable:SetStackSize(size - amount)
                else
                    -- Stock removal spills excess if a whole infinite stack
                    -- reaches RemoveItem without first being reduced to one.
                    spilled = spilled + math.max(0, size - 40)
                    self:Withdraw():Remove()
                end
            end
            c.OnSave = function(self)
                return { count = self.item and self.item.components.stackable:StackSize() or 0 }
            end
        elseif name == "machine" then
            c.ison = false
            c.SetGroundOnlyMachine = noop
            c.IsOn = function(self) return self.ison end
            c.TurnOn = function(self)
                self.turnonfn(self.inst)
                self.ison = true
            end
            c.TurnOff = function(self)
                self.turnofffn(self.inst)
                self.ison = false
            end
            c.OnSave = function(self) return { ison = self.ison } end
        elseif name == "workable" then
            c.SetWorkAction, c.SetWorkLeft, c.SetOnFinishCallback = noop, noop, noop
        else
            assert(name == "inspectable" or name == "lootdropper", name)
        end
        self.components[name] = c
    end
    e.entity, e.Transform, e.AnimState = surface(), surface(), surface()
    e.SoundEmitter, e.MiniMapEntity = surface(), surface()
    e.Light = surface()
    e.Light.Enable = function(_, value) e.lightenabled = value end
    return e
end
CreateEntity = entity

local function advance(dt)
    local target = now + dt
    while true do
        local nexttask
        for _, task in ipairs(tasks) do
            if not task.cancelled and task.owner.valid and task.at <= target
                and (not nexttask or task.at < nexttask.at) then nexttask = task end
        end
        if not nexttask then break end
        now = math.max(now, nexttask.at)
        if nexttask.period then nexttask.at = now + nexttask.period
        else nexttask.cancelled = true end
        nexttask.fn(nexttask.owner)
    end
    now = target
end
local function dust(size)
    local item = entity()
    item.prefab = "nw_dust"
    item.components.stackable = {
        StackSize = function() return size end,
        SetStackSize = function(_, value) size = value; item:PushEvent("stacksizechange") end,
    }
    return item
end
local prefab = dofile("mod/scripts/prefabs/nw_emberlamp.lua")
local storage = require("nw/arcane_storage")
local function spawn(count)
    local inst = prefab.fn()
    if count and count > 0 then inst.components.container:GiveItem(dust(count)) end
    advance(0)
    return inst
end
local function near(a, b)
    assert(math.abs(a - b) < .000001, tostring(a).." ~= "..tostring(b))
end
local function save(inst)
    -- Deliberately serialize machine before the container, like one possible
    -- pairs() order in EntityScript:GetPersistData.
    local data = { machine = inst.components.machine:OnSave() }
    data.container = inst.components.container:OnSave()
    inst:OnSave(data)
    return data
end

-- Every withdrawal happens before the periodic task's first one-second tick.
-- Already-lit fractions must survive and pay for one full minute on refill.
local lamp = spawn(2)
assert(lamp.components.machine:TurnOn())
for cycle = 1, 80 do
    advance(.75)
    local item = lamp.components.container:Withdraw()
    advance(0)
    assert(not lamp.components.machine:IsOn() and not lamp.lightenabled)
    lamp.components.container:GiveItem(item)
    advance(0)
    assert(lamp.components.machine:TurnOn())
    assert(storage.Count(lamp.components.container) == (cycle == 80 and 1 or 2),
        "rapid withdrawal reset the lit-time bill")
end
near(lamp._nw_burnprogress, 0)
lamp:Remove()

-- A minute boundary crossed just before withdrawal is a debt, not fuel.
-- Saving an empty lamp must preserve it; refilling one dust pays it without
-- entering native TurnOn (which would overwrite the callback's off state).
lamp = spawn(1)
assert(lamp.components.machine:TurnOn())
advance(59.75)
now = now + .5 -- withdraw before the due scheduler callback is serviced
local item = lamp.components.container:Withdraw()
advance(0)
near(lamp._nw_burnprogress, 60.25)
local saved = save(lamp)
lamp:Remove()
lamp = spawn()
lamp.components.machine:OnLoad(saved.machine)
lamp:OnLoad(saved)
near(lamp._nw_burnprogress, 60.25)
lamp.components.container:GiveItem(item)
advance(0)
assert(lamp.components.machine:TurnOn() == false)
assert(storage.Count(lamp.components.container) == 0)
assert(not lamp.components.machine:IsOn() and not lamp.lightenabled)
near(lamp._nw_burnprogress, .25)
lamp.components.container:GiveItem(dust(1))
advance(0)
assert(lamp.components.machine:TurnOn())
near(lamp._nw_burnprogress, .25)
lamp:Remove()

-- Save settles before the inventory snapshot and fixes an earlier machine
-- snapshot if a dust unit expired while the scheduler was paused.
lamp = spawn(1)
assert(lamp.components.machine:TurnOn())
now = now + 60.25
saved = save(lamp)
assert(saved.container.count == 0 and saved.machine.ison == false and saved.nw_lit == false)
lamp:Remove()

-- Native whole-stack removal must never eject already-burned overstacked dust.
lamp = spawn(12000)
assert(lamp.components.machine:TurnOn())
lamp:OnLongUpdate(12000 * storage.DUST_SECONDS + 1)
assert(storage.Count(lamp.components.container) == 0 and spilled == 0)
assert(not lamp.components.machine:IsOn() and not lamp.lightenabled)
lamp:Remove()

-- Closing pauses only future time; game-time skips count once, offline load
-- uses the saved fraction and never charges elapsed wall-clock time.
lamp = spawn(5)
assert(lamp.components.machine:TurnOn())
advance(.25)
lamp.components.machine:TurnOff()
advance(120)
lamp:OnLongUpdate(120)
near(lamp._nw_burnprogress, .25)
saved = save(lamp)
lamp:Remove()
now = now + 100000
lamp = spawn(saved.container.count)
lamp.components.machine:OnLoad(saved.machine)
lamp:OnLoad(saved)
near(lamp._nw_burnprogress, .25)
assert(not lamp.components.machine:IsOn())
assert(lamp.components.machine:TurnOn())
lamp:OnEntitySleep()
lamp:OnLongUpdate(120)
lamp:OnEntityWake()
assert(storage.Count(lamp.components.container) == 3)
near(lamp._nw_burnprogress, .25)
lamp:Remove()
print("emberlamp: rapid withdrawal accounting, saved debt, atomic save, 12000-unit depletion, pause and sleep")
