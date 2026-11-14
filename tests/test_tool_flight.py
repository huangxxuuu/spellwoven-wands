"""Focused checks for actual tool motion, orange sampling and native landing FX."""
import sys
import unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))


class ToolFlightTests(unittest.TestCase):
    def test_motion_sampling_and_cleanup(self):
        vm = LuaRuntime()
        vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
        vm.execute('''
FRAMES=1/30;DEGREES=math.pi/180;now=0;tasks={};entities={}
ANIM_ORIENTATION={BillBoard=1};TheCamera={heading=0,pitch=35}
TheNet={IsDedicated=function() return false end}
function GetTime() return now end
local function events(e)
 e.events={}
 function e:ListenForEvent(name,fn) self.events[name]=self.events[name] or {};self.events[name][fn]=true end
 function e:RemoveEventCallback(name,fn) if self.events[name] then self.events[name][fn]=nil end end
 function e:PushEvent(name)
  local callbacks={};for fn in pairs(self.events[name] or {}) do callbacks[#callbacks+1]=fn end
  for _,fn in ipairs(callbacks) do fn(self) end
 end
 return e
end
TheWorld=events({})
function TheWorld:DoPeriodicTask(period,fn)
 local t={Cancel=function(self) self.cancelled=true end};t.fn=function() fn(self) end
 tasks[#tasks+1]=t;return t
end
function CreateEntity()
 local e=events({valid=true,shown=true,x=0,y=0,z=0,rotation=0,entity={},Transform={},AnimState={}})
 e.entity.owner=e
 local noop=function() end
 for _,name in ipairs({'AddTransform','AddAnimState','SetCanSleep'}) do e.entity[name]=noop end
 function e.entity:IsVisible() return e.shown end
 function e.entity:GetParent() return e.parent end
 function e.entity:SetParent(entity) e.parent=entity.owner end
 function e.Transform:GetWorldPosition() return e.x,e.y,e.z end
 function e.Transform:SetPosition(x,y,z) e.x,e.y,e.z=x,y,z end
 function e.Transform:GetRotation() return e.rotation end
 function e.Transform:SetScale(x,y,z) e.scale=x end
 for _,name in ipairs({'SetBank','SetBuild','SetOrientation','SetLightOverride','SetDeltaTimeMultiplier'}) do e.AnimState[name]=noop end
 function e.AnimState:PlayAnimation(name,loop) e.anim=name;e.loop=loop end
 function e.AnimState:SetTime(time) e.anim_time=time end
 e.AddTag=noop
 function e:IsValid() return self.valid end
 function e:Remove() if self.valid then self.valid=false;self:PushEvent('onremove') end end
 entities[#entities+1]=e;return e
end
function shot(size)
 local e=CreateEntity();e._visual=CreateEntity();e._visual.parent=e
 e._height={value=function() return 1.4 end};e._size={value=function() return size or 1 end}
 return e
end
function step(e,x,y,z)
 if e then e.Transform:SetPosition(x,y,z) end
 now=now+FRAMES
 local batch={};for _,t in ipairs(tasks) do batch[#batch+1]=t end
 for _,t in ipairs(batch) do if not t.cancelled then t.fn() end end
end
''')
        vm.globals().Flight = vm.execute((ROOT / 'mod/scripts/nw/tool_flight.lua').read_text('utf8'))
        vm.execute('''
local hoe=shot();Flight.attach(hoe,'farm_hoe')
step(hoe,.2,.5,.2)
local up=Flight.direction_bin(Flight.project(.2,.5,.2,0,35*DEGREES))
assert(hoe._visual.anim=='farm_hoe_dir_'..up,'tool ignored actual ascending motion')
step(hoe,.4,0,.4)
local down=Flight.direction_bin(Flight.project(.2,-.5,.2,0,35*DEGREES))
assert(up~=down and hoe._visual.anim=='farm_hoe_dir_'..down,'tool ignored descending motion')
TheCamera.heading=90;step(hoe,.4,0,.4)
assert(hoe._visual.anim=='farm_hoe_dir_'..Flight.direction_bin(Flight.project(.2,-.5,.2,90*DEGREES,35*DEGREES)))
Flight.detach(hoe,true)
assert(not TheWorld._nw_tool_flights and next(TheWorld.events.onremove)==nil)
local hook=shot();Flight.attach(hook,'oceanfishingrod')
assert(hook._nw_tool_flight,'ocean hook bypassed directional flight')
local hx,hz=0,0
for _,heading in ipairs({0,90,210}) do
 TheCamera.heading=heading
 for i=0,7 do
  local dx,dz=.2*math.cos(i*math.pi/4),.2*math.sin(i*math.pi/4)
  hx,hz=hx+dx,hz+dz;step(hook,hx,0,hz)
  local bin=Flight.direction_bin(Flight.project(dx,0,dz,heading*DEGREES,35*DEGREES))
  assert(hook._visual.anim=='oceanfishingrod_dir_'..bin,'ocean hook retained its original fixed direction')
  assert(hook._visual.anim_time>=0 and hook._visual.anim_time<8/30+.000001,'turning lost the line animation phase')
 end
end
Flight.detach(hook,true)
TheCamera.heading=0
local orb=shot();Flight.attach(orb,'orangestaff')
for i=1,5 do step(orb,i*.6,0,0) end
local s=orb._nw_tool_flight
local positions={}
for _,part in pairs(s.parts) do positions[#positions+1]=part.fx.x end
table.sort(positions)
assert(#positions>=20,'high speed motion left unsampled trail gaps')
for i=2,#positions do assert(math.abs(positions[i]-positions[i-1]-.14)<.00001) end
orb.rotation=180;step(orb,3.6,0,0)
assert(orb._visual.anim=='orange_bolt_dir_32','motor rotation overrode observed motion')
local count=TheWorld._nw_tool_flights.count
orb.shown=false;step(orb,4.2,0,0)
assert(TheWorld._nw_tool_flights.count<=count,'hidden ancestor emitted new trail')
orb:Remove()
assert(TheWorld._nw_tool_flights,'tail must survive a normal head impact')
for i=1,30 do step() end
assert(not TheWorld._nw_tool_flights and next(TheWorld.events.onremove)==nil,'expired trail retained pool or world callback')
assert(Flight.trail_timing(2.5)>Flight.trail_timing(1) and math.abs(Flight.trail_spacing(2.5)-.35)<.00001)
-- Newly replicated tools may not yet report velocity; legal 95-speed motion
-- still produces a connected orange trail with the normal spatial spacing.
local fast=shot();Flight.attach(fast,'orange_bolt')
local distance=require('nw/spell_limits').max_speed*FRAMES
for i=1,6 do
 step(fast,i*distance,0,0)
 assert(fast._nw_tool_flight.path,'legal maximum-speed motion broke the tool trail')
 local newest={}
 for _,part in pairs(fast._nw_tool_flight.parts) do newest[#newest+1]=part.fx.x end
 table.sort(newest)
 assert(#newest>2)
 for j=2,#newest do assert(math.abs(newest[j]-newest[j-1]-.14)<.00001) end
end
Flight.detach(fast,true)
local giant=shot(2.5);Flight.attach(giant,'orange_bolt');step(giant,1,0,0)
local pool=TheWorld._nw_tool_flights
assert(pool.count>0)
TheWorld:PushEvent('onremove')
assert(pool.count==0 and not TheWorld._nw_tool_flights and next(TheWorld.events.onremove)==nil)
for _,t in ipairs(tasks) do assert(t.cancelled,'tool world cleanup leaked task') end
for _,e in ipairs(entities) do
 if e.anim and e.anim:match('_tail_dir_') then assert(not e.valid,'tool cleanup leaked tail entity') end
end
''')

    def test_isolated_bank_and_landing_prefabs(self):
        import build_tool_flight as builder
        build, animations, images, manifest = builder.make_bank()
        self.assertEqual((len(images), len(animations)), (24, 896))
        self.assertEqual(set(manifest['kinds']), {'fishingrod', 'oceanfishingrod', 'trident', 'farm_hoe', 'yoth_lance', 'orange_bolt'})
        for image in images.values():
            self.assertIsNotNone(image.getchannel('A').getbbox())
            self.assertEqual(image.getpixel((0, 0))[3], 0)
        left = animations.find("anim[@name='farm_hoe_dir_64']/frame/element")
        self.assertLess(float(left.get('m_a')), 0)
        self.assertGreater(float(left.get('m_d')), 0, 'left-facing hoe turned upside down')
        # Check the actual painted blade, not just the matrix determinant:
        # the previous pre-flipped source was upside down despite that passing.
        hoe = images['farm_hoe_head_00']
        blade = [(x-hoe.width/2, y-hoe.height/2) for y in range(hoe.height) for x in range(hoe.width)
                 if (lambda r,g,b,a: a>128 and min(r,g,b)>100 and max(r,g,b)-min(r,g,b)<30)(*hoe.getpixel((x,y)))]
        self.assertTrue(blade)
        for direction in (0, 64):
            part = animations.find(f"anim[@name='farm_hoe_dir_{direction}']/frame/element")
            b,d = float(part.get('m_b')),float(part.get('m_d'))
            self.assertGreater(sum(b*x+d*y for x,y in blade)/len(blade), 10,
                               'hoe blade should hang below its shaft in either horizontal direction')
        hook_info = manifest['kinds']['oceanfishingrod']['groups']['head']
        self.assertEqual(hook_info['frames'], 8)
        hook = images['oceanfishingrod_head_00']
        head_area = (211,62,302,131)
        for index in range(8):
            self.assertEqual(images[f'oceanfishingrod_head_{index:02}'].crop(head_area).tobytes(),
                             hook.crop(head_area).tobytes(), 'native hook body shifted while its line moved')
        info = manifest['kinds']['orange_bolt']['groups']['tail']
        lengths = []
        for name in info['symbols'][:5]:
            image = images[name]
            box = image.getchannel('A').point(lambda a: 255 if a > 10 else 0).getbbox()
            lengths.append((box[2] - box[0]) * info['display_size'][0] / image.width)
        self.assertLess(max(lengths) - min(lengths), 3)
        self.assertTrue(all(length > .28 * 150 for length in lengths))
        vm = LuaRuntime()
        vm.globals().package.path = (ROOT / 'mod/scripts/?.lua').as_posix() + ';' + vm.globals().package.path
        vm.execute('''
Asset=function(kind,path) return path end
Prefab=function(name,fn,assets) return {name=name,fn=fn,assets=assets} end
TheWorld={ismastersim=true}
function CreateEntity()
 local e={entity={},AnimState={},events={},valid=true}
 local noop=function() end
 for _,name in ipairs({'AddTransform','AddAnimState','AddNetwork','SetPristine'}) do e.entity[name]=noop end
 function e.AnimState:SetBank(bank) e.bank=bank end
 e.AnimState.SetBuild=noop
 function e.AnimState:PlayAnimation(name,loop) e.animation=name;e.loop=loop end
 e.AddTag=noop
 function e:ListenForEvent(name,fn) self.events[name]=fn end
 function e:DoTaskInTime(time,fn) self.timeout=time end
 function e:Remove() self.valid=false end
 return e
end
''')
        prefabs = vm.execute((ROOT / 'mod/scripts/prefabs/nw_tool_land_fx.lua').read_text('utf8'))
        self.assertEqual(len(prefabs), 7)
        for prefab in prefabs:
            fx = prefab['fn']()
            self.assertEqual(fx['bank'], prefab['name'].removeprefix('nw_tool_land_'))
            self.assertEqual(fx['animation'], 'land')
            self.assertFalse(fx['loop'])
            self.assertIsNone(fx['components'])
            fx['events']['animover'](fx)
            self.assertFalse(fx['valid'])


if __name__ == '__main__': unittest.main()
