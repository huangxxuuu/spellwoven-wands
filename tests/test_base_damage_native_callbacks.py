"""Run installed native damage callbacks with spell-only multiplier markers."""
import os
from pathlib import Path
import unittest
from zipfile import ZipFile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class BaseDamageNativeCallbacks(unittest.TestCase):
    def setUp(self):
        path = GAME / "data/databundles/scripts.zip"
        if not path.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        self.archive = ZipFile(path)
        self.addCleanup(self.archive.close)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + self.lua.globals().package.path
        self.lua.execute('''
local noop=function() end
N=require("nw/base_damage_native")
TheWorld={ismastersim=true}
TUNING={TRIDENT={USES=100,SPELL={DAMAGE=200,RADIUS=4,USE_COUNT=10}},SKILLS={}}
TheNet={GetPVPEnabled=function() return true end}
target={components={},IsValid=function() return true end,HasTag=function() return false end,IsInLimbo=function() return false end}
target.components.health={IsDead=function() return false end}
target.components.combat={inst=target,CanBeAttacked=function() return true end,
    GetAttacked=function(_,a,n,w) received=n end}
N.wrap_combat(target.components.combat)
owner={IsValid=function() return true end,components={combat={IsAlly=function() return false end}}}
owner.components.combat.DoAttack=function(_,e,w)
    local n=w.components.weapon.damage
    if type(n)=="function" then n=n(w,owner,e) end
    e.components.combat:GetAttacked(owner,n,w)
end
TheSim={FindEntities=function() return {target} end}
SpawnPrefab=function() return {Transform={SetPosition=noop}} end
function bell()
    return {prefab="dumbbell",components={weapon={damage=34},complexprojectile={attacker=owner},
        finiteuses={Use=noop,GetUses=function() return 0 end}},
        Transform={GetWorldPosition=function() return 0,0,0 end},
        AnimState={PlayAnimation=noop,PushAnimation=noop},RemoveTag=noop,
        SoundEmitter={KillSound=noop,PlaySound=noop}}
end
''')

    def source(self, name):
        return self.archive.read("scripts/" + name).decode().replace("\r", "")

    def test_native_trident_ordinary_and_spell(self):
        source = self.source("prefabs/trident.lua")
        callback = source[source.index("local function do_water_explosion_effect"):source.index("local function create_water_explosion")]
        self.lua.execute(callback + "\nnative_water=do_water_explosion_effect")
        self.lua.execute('''
local ordinary={prefab="trident"}
local spell={prefab="trident"}
N.tag(spell,{engraving="trident",base_damage_multiplier=.5})
native_water(ordinary,target,owner,{});assert(received==200)
native_water(spell,target,owner,{});assert(received==100)
native_water(ordinary,target,owner,{});assert(received==200)
assert(TUNING.TRIDENT.SPELL.DAMAGE==200)
''')

    def test_native_dumbbell_landing_ordinary_and_spell(self):
        source = self.source("prefabs/dumbbells.lua")
        can_damage = source[source.index("local function CanDamage"):source.index("local function ResetPhysics")]
        callback = source[source.index("local AOE_ATTACK_MUST_TAGS"):source.index("local LAUNCH_OFFSET")]
        self.lua.execute(can_damage + callback + "\nnative_land=OnThrownHit")
        self.lua.execute('''
local ordinary,spell=bell(),bell()
N.tag(spell,{engraving="dumbbell",base_damage_multiplier=1.5})
native_land(ordinary,owner,nil);assert(received==34)
native_land(spell,owner,nil);assert(received==51)
native_land(ordinary,owner,nil);assert(received==34)
assert(spell.components.weapon.damage==34 and ordinary.components.weapon.damage==34)
''')


if __name__ == "__main__":
    unittest.main()
