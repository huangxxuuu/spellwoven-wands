"""Exercise wand recharge projection through installed DST component/UI code."""
import os
from pathlib import Path
import re
import unittest
import zipfile

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))
SCRIPTS = GAME / "data/databundles/scripts.zip"


def method(source, owner, name):
    """Extract an unchanged top-level native method, including its nested closures."""
    start = source.index(f"function {owner}:{name}(")
    following = re.search(r"\n(?:function |local function |return )", source[start + 1:])
    chunk = source[start:] if following is None else source[start:start + 1 + following.start()]
    return chunk[:chunk.rindex("\nend") + len("\nend")]


@unittest.skipUnless(SCRIPTS.is_file(), "requires local DST scripts (or DST_GAME)")
class NativeWandRechargeTests(unittest.TestCase):
    def setUp(self):
        self.vm = LuaRuntime(unpack_returned_tuples=True)
        vm = self.vm
        vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
        with zipfile.ZipFile(SCRIPTS) as archive:
            source = lambda name: archive.read("scripts/" + name + ".lua").decode().replace("\r", "")
            vm.execute(source("class"))
            vm.execute("math.clamp=function(v,a,b) return math.max(a,math.min(b,v)) end")
            vm.globals().package.loaded["util/sourcemodifierlist"] = vm.execute(source("util/sourcemodifierlist"))
            vm.globals().NativeRechargeable = vm.execute(source("components/rechargeable"))
            classified = source("prefabs/inventoryitem_classified")
            start = classified.index("local function SerializeRecharge(")
            end = classified.index("local function OnStackSizeDirty(", start)
            vm.execute(classified[start:end] + """
NativeClassified={SerializeRecharge=SerializeRecharge,SerializeRechargeTime=SerializeRechargeTime,
    DeserializeRecharge=DeserializeRecharge,DeserializeRechargeTime=DeserializeRechargeTime}
""")
            vm.execute("InventoryItem={};ItemTile={}")
            replica = source("components/inventoryitem_replica")
            for name in ("SerializeUsage", "DeserializeUsage", "SetChargeTime"):
                vm.execute(method(replica, "InventoryItem", name))
            tile = source("widgets/itemtile")
            for name in ("Refresh", "SetChargePercent", "SetChargeTime"):
                vm.execute(method(tile, "ItemTile", name))
        vm.execute(r'''
FRAMES=1/30
clock=10
GetTime=function() return clock end
GetGameModeProperty=function() return false end
TheWorld={ismastersim=true}
TheNet={IsDedicated=function() return true end}
EntityScript={is_instance=function() return false end}
function near(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..tostring(b)) end
-- DST set_local changes the local value but leaves the comparison value different,
-- so set_local(x);set(x) can force replication even for an unchanged percentage.
local function netvar(v)
    return {v=v,network=v,dirty=0,sets=0,locals=0,
        value=function(self) return self.v end,
        set_local=function(self,x) self.v=x;self.network=nil;self.locals=self.locals+1 end,
        set=function(self,x)
            self.sets=self.sets+1
            if self.network~=x then self.dirty=self.dirty+1;self.network=x end
            self.v=x
        end}
end
function make_classified(parent)
    local c={_parent=parent,recharge=netvar(255),rechargetime=netvar(-2)}
    setmetatable(c,{__index=NativeClassified})
    function c:DoPeriodicTask(_,fn)
        local task={cancelled=false,Cancel=function(t) t.cancelled=true end}
        self.tick=function() if not task.cancelled then fn(self) end end
        return task
    end
    for _,name in ipairs({'PercentUsed','Perish','Temperature'}) do
        c['Serialize'..name]=function() end;c['Deserialize'..name]=function() end
    end
    return c
end
function make_tile(item,master)
    local anim={pct=1,finish=0}
    function anim:SetPercent(_,pct) self.pct=pct end
    function anim:IsCurrentAnimation() return false end
    function anim:PlayAnimation(name) if name=='frame_pst' then self.finish=self.finish+1 end end
    function anim:SetMultColour() end
    local widget={shown=true,inst={RemoveEventCallback=function() end,ListenForEvent=function() end}}
    function widget:GetAnimState() return anim end
    local frame={shown=false,Show=function(s) s.shown=true end,Hide=function(s) s.shown=false end}
    local t=setmetatable({item=item,ismastersim=master,isactivetile=true,recharge=widget,
        rechargeframe=frame,rechargepct=1,rechargetime=math.huge,anim=anim}, {__index=ItemTile})
    function t:StartUpdatingCharge() self.updating=true end
    function t:StopUpdatingCharge() self.updating=false end
    return t
end
function make_wand()
    local inst={components={},replica={},events={},updaters={},tags={},charged=0,discharged=0}
    function inst:AddTag(t) self.tags[t]=true end
    function inst:RemoveTag(t) self.tags[t]=nil end
    function inst:HasTag(t) return self.tags[t]==true end
    function inst:StartUpdatingComponent(c) self.updaters[c]=true end
    function inst:StopUpdatingComponent(c) self.updaters[c]=nil end
    function inst:ListenForEvent(event,fn)
        self.events[event]=self.events[event] or {};table.insert(self.events[event],fn)
    end
    function inst:PushEvent(event,data)
        for _,fn in ipairs(self.events[event] or {}) do fn(self,data) end
    end
    function inst:AddComponent(name)
        assert(name=='rechargeable');self.components[name]=NativeRechargeable(self)
    end
    local inv=setmetatable({inst=inst,classified=make_classified(inst)},{__index=InventoryItem})
    inst.replica.inventoryitem=inv
    inst:ListenForEvent('rechargechange',function(_,d) inv.classified:SerializeRecharge(d.percent,d.overtime) end)
    local w=require('components/nw_wand')(inst)
    inst.components.nw_wand=w
    w.data={runtime={remaining_cast=0,remaining_recharge=0,mana=42},stats={mana_max=100,mana_regen=1}}
    local M=require('nw/wand_recharge')
    M.setup(inst)
    local r=inst.components.rechargeable
    r:SetOnChargedFn(function() inst.charged=inst.charged+1 end)
    r:SetOnDischargedFn(function() inst.discharged=inst.discharged+1 end)
    -- Discharge(0) must never be used as a display reset.
    local discharge=r.Discharge
    r.Discharge=function(self,t) assert(t>0,'Discharge(0)');return discharge(self,t) end
    return w,r,inv.classified,inst,M
end
function state(w,cast,recharge,total,time)
    clock=time or clock;w.last_time=clock;w.cool_total=total
    w.data.runtime.remaining_cast=cast;w.data.runtime.remaining_recharge=recharge
end
''')

    def test_zero_and_epsilon_never_discharge_or_finish(self):
        self.vm.execute('''
local w,r,c,inst,M=make_wand()
local tile=make_tile(inst,true)
inst:ListenForEvent('rechargechange',function(_,d) tile:SetChargePercent(d.percent) end)
inst:ListenForEvent('rechargetimechange',function(_,d) tile:SetChargeTime(d.t) end)
for _,v in ipairs({0,0,0.0005,0.001,0}) do
    state(w,v,0,1);M.sync(w);tile:Refresh()
    assert(r:IsCharged() and c.recharge:value()==180)
    assert(not tile.rechargeframe.shown and not tile.updating)
end
for i=1,3 do
    w.data.runtime={remaining_cast=0,remaining_recharge=0,mana=42}
    M.sync(w);tile:Refresh()
end
assert(inst.discharged==0 and inst.charged==0 and tile.anim.finish==0)
assert(not inst.updaters[r] and not r.updating)
''')

    def test_progress_completion_and_no_periodic_broadcast(self):
        self.vm.execute('''
local w,r,c,inst,M=make_wand()
state(w,2,4,4,10);M.sync(w)
near(r:GetPercent(),0);near(r:GetRechargeTime(),4)
assert(c.recharge:value()==0)
local dirty=c.recharge.dirty
for i=1,20 do state(w,math.max(0,2-i*.1),4-i*.1,4,10+i*.1);M.sync(w) end
near(r:GetPercent(),.5)
assert(c.recharge.dirty==dirty,'ordinary 0.1s sync must use overtime/set_local')
state(w,0,0,4,14);M.sync(w)
assert(r:IsCharged() and c.recharge:value()==180 and c.recharge.dirty>dirty)
assert(inst.charged==1 and not inst.updaters[r] and not r.updating)
''')

    def test_short_cooldown_is_projection_only_and_not_reset(self):
        self.vm.execute('''
local w,r,c,inst,M=make_wand()
state(w,.08,.03,.08,20)
local runtime=w.data.runtime
M.sync(w)
assert(w.data.runtime==runtime and runtime.remaining_cast==.08 and runtime.remaining_recharge==.03)
near(r:GetRechargeTime(),.08);near(r:GetPercent(),0)
state(w,.04,0,.08,20.04);M.sync(w)
near(r:GetRechargeTime(),.08);near(r:GetPercent(),.5)
local value=c.recharge:value();local dirty=c.recharge.dirty
M.sync(w);near(r:GetPercent(),.5)
assert(c.recharge:value()==value and c.recharge.dirty==dirty)
assert(runtime.mana==42 and runtime.remaining_cast==.04 and runtime.remaining_recharge==0)
-- Editing/name Sync can run after time advances without authoritative UpdateTime.
clock=20.06;M.sync(w)
near(r:GetPercent(),.75)
assert(runtime.remaining_cast==.04 and w.last_time==20.04)
M.sync(w);near(r:GetPercent(),.75)
''')

    def test_restart_same_percentage_and_duration_forces_network_update(self):
        self.vm.execute('''
local w,r,c,inst,M=make_wand()
state(w,0,2,4,30);M.sync(w)
near(r:GetPercent(),.5)
local dirty=c.recharge.dirty
local notices=0
inst:ListenForEvent('rechargechange',function() notices=notices+1 end)
-- A replaced runtime is a new cycle even at the same timestamp and progress.
w.data.runtime={remaining_cast=0,remaining_recharge=2,mana=42}
M.sync(w)
assert(c.recharge.dirty>dirty,'replacement runtime must dirty unchanged network percent')
assert(notices==1,'replacement runtime must notify host tile exactly once')
dirty=c.recharge.dirty
-- A replacement cycle at a later timestamp with unchanged remaining is a restart.
state(w,0,2,4,31);M.sync(w)
assert(c.recharge.dirty>dirty,'same percent/time restart must dirty classified recharge')
dirty=c.recharge.dirty
state(w,0,4,8,31);M.sync(w)
near(r:GetPercent(),.5);near(c.rechargetime:value(),8)
assert(c.recharge.dirty>dirty,'changed duration must republish unchanged percent')
''')

    def test_native_late_host_tile_and_remote_deserialization(self):
        self.vm.execute('''
local w,r,c,inst,M=make_wand()
state(w,1,3,4,40);M.sync(w)
local tile=make_tile(inst,true);tile:Refresh()
near(tile.rechargepct,.25);near(tile.rechargetime,4)
assert(tile.rechargeframe.shown and tile.updating)
-- Native SerializeUsage is also the late inventory attachment path.
inst.replica.inventoryitem:SerializeUsage()
local remote={components={},replica={},events={}}
function remote:HasTag() return false end
local rt=make_tile(remote,false)
function remote:PushEvent(name,d)
    if name=='rechargechange' then rt:SetChargePercent(d.percent)
    elseif name=='rechargetimechange' then rt:SetChargeTime(d.t) end
end
local rc=make_classified(remote)
rc.recharge:set(c.recharge:value());rc.rechargetime:set(c.rechargetime:value())
remote.replica.inventoryitem=setmetatable({inst=remote,classified=rc},{__index=InventoryItem})
rt:Refresh()
near(rt.rechargepct,.25);near(rt.rechargetime,4)
assert(rt.rechargeframe.shown and rt.updating)
rc.tick();assert(rt.rechargepct>.25)
rc.recharge:set(180);rc:DeserializeRecharge()
assert(not rt.rechargeframe.shown and not rt.updating and rt.anim.finish==1)
''')

    def test_native_persistence_longupdate_and_external_modifiers_are_inert(self):
        self.vm.execute('''
local w,r,c,inst,M=make_wand()
state(w,0,2,4,50);M.sync(w)
local pct=r:GetPercent()
assert(r.OnSave==nil or r:OnSave()==nil,'projection must not save a second cooldown')
if r.OnLoad then r:OnLoad({chargetime=123,charge=0}) end
near(r:GetPercent(),pct);near(r:GetRechargeTime(),4)
if r.OnUpdate then r:OnUpdate(100) end
if r.LongUpdate then r:LongUpdate(100) end
near(r:GetPercent(),pct);near(w.data.runtime.remaining_recharge,2)
r:SetChargeTimeMod(inst,'native_test',2)
near(r:GetRechargeTime(),4);near(c.rechargetime:value(),4)
assert(inst.updaters[r] and r.updating,'native modifier must exercise update wakeup')
if r.OnUpdate then r:OnUpdate(100) end
assert(not inst.updaters[r] and not r.updating)
near(r:GetPercent(),pct);near(w.data.runtime.remaining_recharge,2)
r:SetChargeTimeMod(inst,'native_test',3)
assert(inst.updaters[r] and r.updating)
if r.LongUpdate then r:LongUpdate(100) end
assert(not inst.updaters[r] and not r.updating)
near(r:GetPercent(),pct);near(w.data.runtime.remaining_recharge,2)
M.sync(w)
assert(not inst.updaters[r] and not r.updating)
near(r:GetPercent(),pct)
''')


if __name__ == "__main__":
    unittest.main()
