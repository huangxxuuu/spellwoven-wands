"""Executable Lua lifecycle tests with independently clocked network peers."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def runtime(master=True, dedicated=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + lua.globals().package.path
    lua.globals().master = master
    lua.globals().dedicated = dedicated
    lua.execute(r'''
package.loaded["nw/recycle"]={start=function() end,stop=function() end}
FRAMES=1/30; LAYER_BACKGROUND=7; ANIM_ORIENTATION={OnGround=1}
ACTIONS={HAMMER={}}; now=0; entities={}; nets={}; dirty=false
TheWorld={ismastersim=master};TheNet={IsDedicated=function() return dedicated end}
GetTime=function() return now end
local function net(initial,name)
    local n={v=initial,sent=initial,writes=0}
    function n:value() return self.v end
    function n:set(v) self.v=v;self.sent=v;self.writes=self.writes+1;dirty=true end
    function n:set_local(v) self.v=v end
    nets[name]=n;return n
end
net_bool=function(_,name) return net(false,name) end
net_float=function(_,name) return net(0,name) end
net_uint=function(_,name) return net(0,name) end
local function recorder()
    return setmetatable({}, {__index=function(self,key)
        return function(_,...)
            self[key.."_args"]={...}
            self[key.."_count"]=(rawget(self,key.."_count") or 0)+1
        end
    end})
end
CreateEntity=function()
    local e={entity=recorder(),AnimState=recorder(),Light=recorder(),Transform=recorder(),
        MiniMapEntity=recorder(),components={},events={},tasks={},initial={}}
    function e:AddTag() end
    function e:RemoveTag() end
    function e:AddComponent(name) self.components[name]=recorder() end
    function e:ListenForEvent(name,fn)
        local previous=self.events[name]
        self.events[name]=function(...)
            if previous then previous(...) end
            fn(...)
        end
    end
    function e:DoTaskInTime(_,fn) table.insert(self.initial,fn) end
    function e:DoPeriodicTask(_,fn)
        local t={fn=fn,Cancel=function(self) self.cancelled=true end}
        table.insert(self.tasks,t);return t
    end
    function e:Remove() self.removed=true end
    table.insert(entities,e);return e
end
MakeObstaclePhysics=function(e,r) e.collision=r end
Asset=function() return {} end
Prefab=function(name,fn) return {name=name,fn=fn} end
MakePlacer=function() return {} end
local prefab=require("prefabs/nw_disassembler")
furnace=prefab.fn()
for _,fn in ipairs(furnace.initial) do fn() end
function flush()
    local limit=0
    while dirty do
        dirty=false;furnace.events.nw_furnacedirty();limit=limit+1
        assert(limit<5,"dirty callback must not publish another dirty value forever")
    end
end
function advance(t)
    while now<t-1e-8 do
        now=t-now<=FRAMES+1e-8 and t or now+FRAMES
        for _,task in ipairs(furnace.tasks) do if not task.cancelled then task.fn() end end
        flush()
    end
end
function near(a,b) assert(math.abs(a-b)<.0001,tostring(a).." ~= "..tostring(b)) end
function verify(radius,animation,scale)
    near(furnace.Light.SetRadius_args[1],radius)
    if dedicated then assert(#entities==1,"dedicated must not spawn FX");return end
    local ring=entities[#entities]
    assert(not ring.removed,"missing ring")
    assert(ring.AnimState.PlayAnimation_args[1]==animation,"wrong animation")
    near(ring.Transform.SetScale_args[1],scale)
    assert(ring.AnimState.SetBank_args[1]=="nw_furnace_wave")
    assert(ring.AnimState.SetBuild_args[1]=="nw_furnace_wave")
    assert(ring.AnimState.SetOrientation_args[1]==ANIM_ORIENTATION.OnGround)
    assert(ring.AnimState.SetLayer_args[1]==LAYER_BACKGROUND)
    assert(ring.AnimState.SetSortOrder_args[1]==1)
end
function no_tasks()
    for _,task in ipairs(furnace.tasks) do assert(task.cancelled,"task leaked") end
end
function off()
    near(furnace.Light.SetRadius_args[1],0);no_tasks()
    if not dedicated and #entities>1 then assert(entities[#entities].removed) end
end
assert(furnace.collision==.8)
assert(furnace.AnimState.SetScale_args[1]==1.1)
assert(furnace.Light.EnableClientModulation_args[1])
''')
    return lua


def replicate(source, target, current=True):
    # A joining entity reads current values; connected peers receive published
    # values. No synthetic grow frame is injected into the client fixture.
    for name, net in source.globals().nets.items():
        target.globals().nets[name]["v"] = net["v" if current else "sent"]
    target.execute("furnace.events.nw_furnacedirty()")


class FurnaceVisualTest(unittest.TestCase):
    def lifecycle(self, dedicated):
        lua = runtime(dedicated=dedicated)
        lua.execute(r'''
furnace:SetNWActive(true);flush();verify(0,"grow",1)
advance(.5);verify(1,"grow",1)
advance(1);verify(2,"grow",1)
local plays=not dedicated and entities[#entities].AnimState.PlayAnimation_count
furnace:SetNWActive(true);flush();furnace.events.nw_furnacedirty()
if not dedicated then assert(entities[#entities].AnimState.PlayAnimation_count==plays) end
advance(2);verify(4,"loop",1);no_tasks()
assert(nets["nw_furnace.age"].writes<12,"age must not broadcast every frame")
advance(5);furnace:SetNWActive(false,true);flush();verify(4,"release",1)
advance(5.3);verify(4,"release",1);near(furnace.Light.SetIntensity_args[1],.325)
advance(5.6);off()
local count=#entities
furnace.events.nw_furnacedirty();assert(#entities==count,"release respawned")
-- Mid-growth cancellation keeps the current footprint throughout release.
furnace:SetNWActive(true);advance(6.6);verify(2,"grow",1)
furnace:SetNWActive(false,true);flush();verify(2,"release",.5)
advance(6.9);verify(2,"release",.5)
-- Restart while releasing must restore normal light and unscaled grow art.
furnace:SetNWActive(true);flush();verify(0,"grow",1)
near(furnace.Light.SetIntensity_args[1],.65)
advance(7.4);verify(1,"grow",1)
furnace.events.onremove();off()
furnace:SetNWActive(false,true);flush();off()
''')

    def test_host_lifecycle(self):
        self.lifecycle(False)

    def test_dedicated_lifecycle_without_fx(self):
        self.lifecycle(True)

    def test_late_join_and_duplicate_dirty(self):
        server, client = runtime(), runtime(False)
        server.execute("furnace:SetNWActive(true);advance(1.2)")
        client.execute("now=100")
        replicate(server, client)
        client.execute(r'''
verify(2.4,"grow",1)
local plays=entities[#entities].AnimState.PlayAnimation_count
advance(100.2);furnace.events.nw_furnacedirty();verify(2.8,"grow",1)
assert(entities[#entities].AnimState.PlayAnimation_count==plays)
advance(100.8);verify(4,"loop",1);no_tasks()
''')
        # A complete grow snapshot starts directly in the flowing loop.
        server.execute("advance(3)")
        late = runtime(False)
        late.execute("now=700")
        replicate(server, late)
        late.execute('verify(4,"loop",1);no_tasks();assert(entities[2].AnimState.PlayAnimation_count==1)')

    def test_connected_correction_and_coalesced_restart(self):
        server, client = runtime(), runtime(False)
        server.execute("furnace:SetNWActive(true)")
        replicate(server, client, False)
        server.execute("advance(1)")
        client.execute("advance(.4)")
        replicate(server, client, False)
        published = server.globals().nets["nw_furnace.age"]["sent"]
        self.assertGreater(published, .7)
        self.assertAlmostEqual(client.globals().furnace.Light.SetRadius_args[1], 2 * published)
        client.execute("oldplays=entities[2].AnimState.PlayAnimation_count")
        # Client never saw inactive; sequence must still restart the new run.
        server.execute("furnace:SetNWActive(false,true);furnace:SetNWActive(true)")
        replicate(server, client, False)
        client.execute('verify(0,"grow",1);assert(entities[2].AnimState.PlayAnimation_count==oldplays+1)')

    def test_late_release_and_removal(self):
        server, client = runtime(), runtime(False)
        server.execute("furnace:SetNWActive(true);advance(1);furnace:SetNWActive(false,true);advance(1.3)")
        client.execute("now=90")
        replicate(server, client)
        client.execute(r'''
verify(2,"release",.5);near(furnace.Light.SetIntensity_args[1],.325)
advance(90.3);off()
local count=#entities
furnace.events.nw_furnacedirty();assert(#entities==count)
''')
        server.execute("advance(1.6)")
        replicate(server, client)
        client.execute("off()")
        server.execute("furnace:SetNWActive(true);advance(2.1)")
        replicate(server, client)
        client.execute("furnace.events.onremove();off();furnace.events.nw_furnacedirty();off()")

    def test_recycle_end_paths_stop_gameplay_immediately(self):
        for outcome in ("empty", "complete", "cancel"):
            with self.subTest(outcome=outcome):
                lua = runtime()
                lua.globals().outcome = outcome
                lua.execute(r'''
package.loaded["nw/recycle"]=nil
local recycle=require("nw/recycle")
local station=furnace
station.Transform.GetWorldPosition=function() return 0,0,0 end
station.RemoveEventCallback=function() end
local player={components={health={IsDead=function() return false end},
    talker={Say=function() end}},sg={statemem={target=station}}}
function player:IsValid() return true end
function player:IsNear() return true end
station.components.channelable={channeler=player,IsChanneling=function() return true end,
    StopChanneling=function() recycle.stop(station) end}
local item={prefab="nw_spellcard",components={stackable={StackSize=function() return 1 end}},
    entity={GetParent=function() end},Transform={GetWorldPosition=function() return .5,0,0 end}}
function item:IsValid() return not self.removed end
function item:HasTag() return false end
function item:IsNear() return true end
function item:SetNWMarked(v) self.marked=v end
function item:Remove() self.removed=true end
TheSim={FindEntities=function() return outcome=="empty" and {} or {item} end}
local outputs=0
SpawnPrefab=function(name)
    if name=="nw_dust" then outputs=outputs+1 end
    return {Transform={SetPosition=function() end},
        components={stackable={SetStackSize=function() end}}}
end
recycle.start(station,player)
if outcome=="cancel" then
    advance(1);recycle.stop(station)
    verify(2,"release",.5);assert(not item.removed and outputs==0)
    assert(not item.marked and item._nw_claim==nil)
else
    advance(outcome=="empty" and 2 or 5)
    assert(item.removed==(outcome=="complete" and true or nil))
    assert(outputs==(outcome=="complete" and 1 or 0))
    verify(4,"release",1)
end
assert(station._nw_run==nil,"gameplay must stop before release finishes")
local active=0
for _,task in ipairs(station.tasks) do if not task.cancelled then active=active+1 end end
assert(active==1,"only the local release task may survive gameplay stop")
advance(now+.6);off()
''')


if __name__ == "__main__":
    unittest.main()
