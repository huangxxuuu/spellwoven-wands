"""Replay installed DST callbacks through the spell-only targeting adapters."""
import os
from pathlib import Path
import unittest
from zipfile import ZipFile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class TargetingNativeCallbacks(unittest.TestCase):
    def setUp(self):
        archive = GAME / "data/databundles/scripts.zip"
        if not archive.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        self.archive = ZipFile(archive)
        self.addCleanup(self.archive.close)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + self.lua.globals().package.path
        self.lua.execute((ROOT / "tests/test_targeting_native.lua").read_text(encoding="utf8"))

    def source(self, path):
        return self.archive.read("scripts/" + path).decode().replace("\r", "")

    def test_lunar_native_hit_schedules_selected_bounce(self):
        source = self.source("prefabs/brilliance_projectile_fx.lua")
        body = source[source.index("local function PlayAnimAndRemove"):source.index("local function OnMiss")]
        self.lua.execute("local BOUNCE_RANGE=12;local BOUNCE_SPEED=10\n" + body + "\nnative_hit=OnHit")
        self.lua.execute('''
local Native=require("nw/native_targeting")
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
GetRandomMinMax=function(a,b) return (a+b)/2 end
local previous=native_test_targets[4]
local shot={prefab="brilliance_projectile_fx",bounces=3,components={},Transform={GetRotation=function() return 0 end},
    Physics={Stop=function() end,Teleport=function() end},Show=function() end,Hide=function() end,
    Remove=function(self) self.removed=true end,IsValid=function(self) return not self.removed end}
local cp={onhit=native_hit,SetSpeed=function() end,SetBounced=function() end,
    Throw=function(_,owner,e,attacker) chosen=e end}
shot.components.projectile=cp
shot.DoTaskInTime=function(self,time,fn,...) task={fn=fn,args={...}} end
local schedule=shot.DoTaskInTime
Native.tag(shot,native_test_owner,{engraving="staff_lunarplant",flags={targets={players_other=true}}})
Native.bounce(shot)
cp.onhit(shot,native_test_owner,previous)
assert(shot.DoTaskInTime==schedule and shot.bounces==2 and task)
task.fn(shot,unpack(task.args))
assert(chosen==native_test_targets[2],"native player-excluding search must be replaced")
assert(not shot.removed and shot.recenttargets[1]==previous)
-- Another scope must not reuse this continuation's copied selection.
local p={engraving="staff_lunarplant",flags={targets={friendly=true}}}
Native.tag(shot,native_test_owner,p);p.flags.targets={hostile=true}
cp.onhit(shot,native_test_owner,previous);task.fn(shot,unpack(task.args))
assert(chosen==native_test_targets[3] and shot.bounces==1)
-- Explicit nature selection chooses a tree even without damage components.
shot.bounces=3
Native.tag(shot,native_test_owner,{engraving="staff_lunarplant",flags={targets={nature=true}}})
cp.onhit(shot,native_test_owner,previous);task.fn(shot,unpack(task.args))
assert(chosen==native_test_targets[6],"bounce selection must not pre-require health/combat")
-- A failed native callback must not leave a temporary scheduling override.
local failing={prefab="brilliance_projectile_fx",components={projectile={}},DoTaskInTime=schedule}
local TryBounce=function() end
failing.components.projectile.onhit=function(self) self:DoTaskInTime(.1,TryBounce);error("expected native failure") end
Native.tag(failing,native_test_owner,{engraving="staff_lunarplant",flags={targets={friendly=true}}})
Native.bounce(failing)
assert(not pcall(failing.components.projectile.onhit,failing))
assert(failing.DoTaskInTime==schedule)
''')

    def test_real_bell_native_disk_is_suppressed_only_for_selected_landing(self):
        source = self.source("prefabs/dumbbells.lua")
        can_damage = source[source.index("local function CanDamage"):source.index("local function ResetPhysics")]
        callback = source[source.index("local AOE_ATTACK_MUST_TAGS"):source.index("local LAUNCH_OFFSET")]
        self.lua.execute(can_damage + callback + "\nnative_land=OnThrownHit")
        self.lua.execute('''
local noop=function() end
local Native=require("nw/native_targeting")
local bell={prefab="dumbbell",components={weapon={damage=34,OnAttack=noop},complexprojectile={attacker=native_test_owner},
    finiteuses={Use=noop,GetUses=function() return 0 end}},Transform=native_test_owner.Transform,
    AnimState={PlayAnimation=noop,PushAnimation=noop},RemoveTag=noop,
    SoundEmitter={KillSound=noop,PlaySound=noop}}
for _,e in ipairs(native_test_targets) do e.hits=0 end
Native.tag(bell,native_test_owner,{engraving="dumbbell",flags={targets={neutral=true}}})
require("nw/giant_native").bell(bell,native_test_owner,1)
require("nw/native_size").filtered(native_land,1,2,.5,0,function() return false end,bell,native_test_owner,nil)
for _,e in ipairs(native_test_targets) do assert(e.hits==(e.prefab=="neutral" and 1 or 0)) end
assert(bell.components.weapon.damage==34)
-- Unmarked original attacks remain the game's own callback.
bell._nw_native_targets=nil
native_land(bell,native_test_owner,nil)
assert(native_test_targets[4].hits==1 and native_test_targets[5].hits==2)
''')

    def test_native_projectile_hit_is_filtered_before_attack_and_callback(self):
        source = self.source("components/projectile.lua")
        body = source[source.index("function Projectile:Hit(target)"):source.index("local function DozeOff")]
        self.lua.execute("local Projectile={};local StopTrackingDelayOwner=function() end\n" + body + "\nnative_projectile_hit=Projectile.Hit")
        self.lua.execute('''
local Native=require("nw/native_targeting")
local noop=function() end
local owner=native_test_owner
local enemy=native_test_targets[4]
enemy.hits=0
local shot={prefab="brilliance_projectile_fx",components={},Physics={Stop=noop},IsValid=function() return true end}
local hitcallbacks,misses=0,0
local staff={prefab="staff_lunarplant",components={weapon={damage=12,OnAttack=noop},inventoryitem={owner=owner}}}
local cp={inst=shot,owner=staff,Stop=noop,Hit=native_projectile_hit,
    onhit=function() hitcallbacks=hitcallbacks+1 end,Miss=function() misses=misses+1 end}
shot.components.projectile=cp
local p={engraving="staff_lunarplant",flags={targets={hostile=true}}}
Native.tag(staff,owner,p);Native.tag(shot,owner,p);Native.projectile(shot)
cp:Hit(enemy)
assert(enemy.hits==1 and hitcallbacks==1 and misses==0)
enemy.tags.hostile=nil
cp:Hit(enemy)
assert(enemy.hits==1 and hitcallbacks==1 and misses==1,"filter must run before native DoAttack and onhit")
enemy.tags.hostile=true
''')

    def test_real_tentacle_attack_frames_recheck_inherited_selection(self):
        source = self.source("stategraphs/SGshadowtentacle.lua")
        body = source[source.index("local function DoAttack"):source.index("local states=")]
        self.lua.execute(body + "\nnative_tentacle_attack=DoAttack")
        self.lua.execute('''
local Native=require("nw/native_targeting")
local enemy=native_test_targets[4]
local tentacle=native_test_entity("neutral");tentacle.prefab="shadowtentacle"
local c=tentacle.components.combat
-- The stategraph calls DoAttack without a weapon; this small fixture supplies
-- its native default damage while retaining the real shared combat wrapper.
c._nw_targeting_wrapped=nil
c.DoAttack=function(self,target)
    target=target or self.target
    return target.components.combat:GetAttacked(tentacle,10)
end
Native.wrap_combat(c);c.target=enemy
Native.tag(tentacle,native_test_owner,{source_weapon="ruins_bat",flags={targets={hostile=true}}})
enemy.hits=0
native_tentacle_attack(tentacle)
enemy.tags.hostile=nil
native_tentacle_attack(tentacle)
assert(enemy.hits==1,"frame 17 must reclassify after frame 7")
enemy.tags.hostile=true
''')

    def test_native_tornado_all_existing_attack_stages_filter(self):
        self.lua.execute('''
package.loaded["stategraphs/commonstates"]={}
EventHandler=function(...) return {...} end
TimeEvent=function(t,fn) return {time=t,fn=fn} end
State=function(s) return s end
StateGraph=function(_,states) local out={states={}};for _,s in ipairs(states) do out.states[s.name]=s end;return out end
''')
        self.lua.globals().sg = self.lua.execute(self.source("stategraphs/SGtornado.lua"))
        self.lua.execute('''
local Native=require("nw/native_targeting")
require("nw/giant_native").install_tornado(sg)
local noop=function() end
local wind={prefab="tornado",WINDSTAFF_CASTER=native_test_owner,WINDSTAFF_CASTER_ISPLAYER=true,
    Transform=native_test_owner.Transform,IsValid=function() return true end,
    Physics={Stop=noop},components={locomotor={WalkForward=noop}},
    AnimState={PushAnimation=noop,PlayAnimation=noop}}
Native.tag(wind,native_test_owner,{engraving="staff_tornado",flags={targets={hostile=true}}})
for _,e in ipairs(native_test_targets) do e.hits=0;e.worked=0 end
sg.states.empty.onenter(wind)
for _,e in ipairs(native_test_targets) do assert(e.hits==0 and e.worked==0,"directed empty phase gains no attack") end
sg.states.idle.onenter(wind);sg.states.walk.onenter(wind)
for _,name in ipairs({"walk","run_start","run","run_stop"}) do
    assert(#sg.states[name].timeline==1 and sg.states[name].timeline[1].time==5*FRAMES)
    sg.states[name].timeline[1].fn(wind)
end
for _,e in ipairs(native_test_targets) do assert(e.hits==(e.prefab=="hostile" and 6 or 0) and e.worked==0) end
native_test_targets[4].tags.hostile=nil
sg.states.idle.onenter(wind)
assert(native_test_targets[4].hits==6,"ongoing wind rechecks current category")
native_test_targets[4].tags.hostile=true
''')

    def test_trident_selected_entities_boats_and_tending(self):
        self.lua.execute('''
local Size=require("nw/native_size")
Vector3=function(x,y,z) return {x=x,y=y,z=z,Get=function(self) return self.x,self.y,self.z end} end
VecUtil_Normalize=function(x,z) local d=math.sqrt(x*x+z*z);return x/d,z/d end
GetRandomWithVariance=function() return -45 end
TUNING.TRIDENT={USES=100,SPELL={RADIUS=4,USE_COUNT=10}}
TUNING.TRIDENT_FARM_PLANT_INTERACT_RANGE=8
local plant=native_test_targets[6]
plant.tags.tendable_farmplant=true
plant.components.farmplanttendable={TendTo=function() plant.tended=(plant.tended or 0)+1 end}
local boat=native_test_targets[7]
boat.tags.structure=nil;boat.tags.boat=true
boat.components.workable=nil
boat.components.boatphysics={ApplyForce=function() end}
boat.PushEvent=function(_,name) assert(name=="spawnnewboatleak");boat.leaks=(boat.leaks or 0)+1 end
TheWorld={Map={IsOceanTileAtPoint=function() return true end,IsVisualGroundAtPoint=function() return false end,
    GetPlatformAtPoint=function() return boat end}}
for _,e in ipairs(native_test_targets) do e.IsOnOcean=function() return true end end
local staff={components={finiteuses={Use=function() end}},DoWaterExplosionEffect=function(_,e) e.hits=e.hits+1 end}
for _,category in ipairs({"self","players_other","friendly","hostile","neutral","nature","building"}) do
    for _,e in ipairs(native_test_targets) do e.hits=0 end
    boat.leaks=0;plant.tended=0
    Size.trident(staff,native_test_owner,Vector3(0,0,0),.5,{flags={targets={[category]=true}}})
    for _,e in ipairs(native_test_targets) do assert(e.hits==(e.prefab==category and 1 or 0),category.." water "..e.prefab) end
    assert(boat.leaks==(category=="building" and 4 or 0),category.." boat leaks")
    assert(plant.tended==(category=="nature" and 1 or 0),category.." tending")
end
''')


if __name__ == "__main__":
    unittest.main()
