"""Run size adapters against installed DST callbacks, without a game process."""
import os
from pathlib import Path
import unittest
from zipfile import ZipFile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class ShrinkNativeTest(unittest.TestCase):
    def setUp(self):
        archive = GAME / "data/databundles/scripts.zip"
        if not archive.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        self.archive = ZipFile(archive)
        self.addCleanup(self.archive.close)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + self.lua.globals().package.path
        self.lua.execute('''
local noop=function() end
FRAMES=1/30;DEGREES=math.pi/180
TUNING={TORNADO_DAMAGE=7,PVP_DAMAGE_MOD=.5,SKILLS={},TRIDENT={SPELL={RADIUS=4,USE_COUNT=10},USES=100},TRIDENT_FARM_PLANT_INTERACT_RANGE=8}
TheNet={GetPVPEnabled=function() return false end}
targets={};queries={}
TheSim={FindEntities=function(_,x,y,z,r,tags)
    queries[#queries+1]={x=x,z=z,r=r,tags=tags}
    local result={};for _,e in ipairs(targets) do if e:GetDistanceSqToPoint(x,y,z)<=r*r then result[#result+1]=e end end
    return result
end}
function target(distance)
    local e={hits=0,cold=0,components={},x=distance}
    e.IsValid=function() return true end;e.IsInLimbo=function() return false end;e.HasTag=function() return false end;e.HasAnyTag=e.HasTag
    e.GetDistanceSqToPoint=function(self,x,y,z) return (self.x-x)^2+z*z end
    e.components.combat={CanBeAttacked=function() return true end,GetAttacked=function(_,_,damage) e.hits=e.hits+1;e.damage=damage end,SuggestTarget=noop}
    e.components.health={IsDead=function() return false end}
    e.components.freezable={AddColdness=function(_,n) e.cold=e.cold+n end}
    return e
end
owner={IsValid=function() return true end,components={combat={IsAlly=function() return false end,
    DoAttack=function(_,e) e.hits=e.hits+1 end}},Transform={GetWorldPosition=function() return 0,0,0 end}}
spawned={}
SpawnPrefab=function(name)
    local e={prefab=name,scale=1,Transform={}}
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.z=x,z end
    e.Transform.GetScale=function() return e.scale,e.scale,e.scale end
    e.Transform.SetScale=function(_,s) e.scale=s end
    spawned[#spawned+1]=e;return e
end
''')

    def source(self, name):
        return self.archive.read("scripts/" + name).decode().replace("\r", "")

    def test_native_dumbbell_hit_and_environment_restoration(self):
        src = self.source("prefabs/dumbbells.lua")
        can_damage = src[src.index("local function CanDamage"):src.index("local function ResetPhysics")]
        hit = src[src.index("local AOE_ATTACK_MUST_TAGS"):src.index("local LAUNCH_OFFSET")]
        self.lua.execute(can_damage + hit + "\nnative_hit=OnThrownHit")
        self.lua.execute('''
local noop=function() end
local Size=require("nw/native_size")
local inside,outside=target(.5),target(1.5);targets={inside,outside}
local bell={components={weapon={damage=34},complexprojectile={attacker=owner},finiteuses={Use=noop,GetUses=function() return 0 end}},
    isiceattack=true,Transform=owner.Transform,AnimState={PlayAnimation=noop,PushAnimation=noop},RemoveTag=noop,SoundEmitter={KillSound=noop,PlaySound=noop}}
local env=getfenv(native_hit);local sim=TheSim
Size.call(native_hit,.4,2,0,0,bell,owner,nil)
assert(inside.hits==1 and inside.cold==2 and outside.hits==0 and outside.cold==0)
assert(getfenv(native_hit)==env and TheSim==sim and bell.components.weapon.damage==34)
native_hit(bell,owner,nil)
assert(inside.hits==2 and outside.hits==1 and outside.cold==2,"ordinary native throws must retain their radius")
local throwing=function() TheSim:FindEntities(0,0,0,2);error("expected native error") end
local original=getfenv(throwing)
assert(not pcall(Size.call,throwing,.4,2,0,0))
assert(getfenv(throwing)==original and TheSim==sim,"failed callbacks must restore their local environment")
''')

    def test_native_tornado_state_timing_small_and_regular(self):
        self.lua.execute('''
package.loaded["stategraphs/commonstates"]={}
EventHandler=function(...) return {...} end
TimeEvent=function(t,fn) return {time=t,fn=fn} end
State=function(s) return s end
StateGraph=function(_,states) local out={states={}};for _,s in ipairs(states) do out.states[s.name]=s end;return out end
''')
        self.lua.globals().sg = self.lua.execute(self.source("stategraphs/SGtornado.lua"))
        self.lua.execute('''
local G=require("nw/giant_native");G.install_tornado(sg)
local inside,outside=target(.6),target(2);targets={inside,outside}
local moved,animated=0,0
local inst={_nw_giant=.4,Transform=owner.Transform,WINDSTAFF_CASTER=owner,IsValid=function() return true end,
    Physics={Stop=function() moved=moved+1 end},components={locomotor={WalkForward=function() moved=moved+1 end}},
    AnimState={PushAnimation=function(_,name) assert(name=="tornado_loop");animated=animated+1 end}}
sg.states.idle.onenter(inst);sg.states.walk.onenter(inst)
for _,name in ipairs({"walk","run_start","run","run_stop"}) do
    assert(#sg.states[name].timeline==1 and sg.states[name].timeline[1].time==5*FRAMES)
    sg.states[name].timeline[1].fn(inst)
end
assert(inside.hits==6 and inside.damage==7 and outside.hits==0 and moved==2 and animated==2)
inst._nw_giant=nil;sg.states.idle.onenter(inst)
assert(inside.hits==7 and outside.hits==1 and moved==3 and animated==3)
local outer=target(5);targets={inside,outside,outer}
inst._nw_giant=2.5;sg.states.idle.onenter(inst)
assert(inside.hits==8 and outside.hits==2 and outer.hits==1,"old giant annulus remains single-hit")
''')

    def test_trident_small_ocean_effects_boats_and_plants(self):
        self.lua.execute('''
local Size=require("nw/native_size")
Vector3=function(x,y,z) return {x=x,y=y,z=z,Get=function(self) return self.x,self.y,self.z end} end
VecUtil_Normalize=function(x,z) local d=math.sqrt(x*x+z*z);return x/d,z/d end
GetRandomWithVariance=function() return -45 end
local inside,outside=target(.5),target(2)
inside.IsOnOcean=function() return true end;outside.IsOnOcean=inside.IsOnOcean
targets={inside,outside}
local leaks={};local boat={Transform=owner.Transform,components={boatphysics={ApplyForce=function(_,x,z) assert(x*x+z*z<2) end}},
    PushEvent=function(_,name,data) assert(name=="spawnnewboatleak");leaks[#leaks+1]=data.pt end}
local onboat=true
TheWorld={Map={IsOceanTileAtPoint=function() return true end,IsVisualGroundAtPoint=function() return false end,
    GetPlatformAtPoint=function() return onboat and boat or nil end}}
local cost=0;local staff={components={finiteuses={Use=function(_,n) cost=cost+n end}},
    DoWaterExplosionEffect=function(_,e) e.hits=e.hits+1 end}
Size.trident(staff,owner,Vector3(0,0,0),.4)
assert(inside.hits==1 and outside.hits==0 and #leaks==4 and cost==10)
for _,pt in ipairs(leaks) do assert(pt.x*pt.x+pt.z*pt.z<1,"boat leaks must use the shrunk ring") end
assert(queries[#queries].r==3.2 and queries[#queries].tags[1]=="tendable_farmplant")
onboat=false;Size.trident(staff,owner,Vector3(0,0,0),.4)
assert(#spawned==4)
for _,fx in ipairs(spawned) do assert(math.abs(fx.scale-.4)<1e-9 and fx.x*fx.x+fx.z*fx.z<1.1) end
''')


if __name__ == "__main__":
    unittest.main()
