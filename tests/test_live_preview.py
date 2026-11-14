"""Exercise the real client tool lifecycle with a minimal Lua engine adapter."""
import sys
import tempfile
import unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import live_preview


class PreviewTests(unittest.TestCase):
    def test_elemental_watch_inputs(self):
        watched = set(live_preview.inputs())
        for name in ('fire-atlas.png', 'frost-atlas.png'):
            self.assertIn(ROOT / 'assets_src/projectiles/elemental_v1' / name, watched)
        self.assertIn(ROOT / 'tools/build_elemental_flight.py', watched)
        self.assertIn(ROOT / 'mod/scripts/nw/elemental_flight.lua', watched)
        for name in ('spell_limits.lua', 'projectile_glow.lua', 'beam_front.lua', 'projectile_size.lua',
                     'trail_budget.lua', 'beam_path.lua', 'beam_visual.lua', 'tool_flight.lua',
                     'field_stages.lua', 'field_member_visual.lua', 'electric_visual.lua'):
            self.assertIn(ROOT / 'mod/scripts/nw' / name, watched)
        for name in ('build_tool_flight.py', 'build_field_stages.py', 'build_electric_arc.py'):
            self.assertIn(ROOT / 'tools' / name, watched)
        self.assertIn(ROOT / 'tools/preview_mod/modmain.lua', watched)
        self.assertIn(ROOT / 'mod/scripts/nw/util.lua', watched)
        for path in (ROOT / 'mod/scripts/nw/constants').rglob('*.lua'):
            self.assertIn(path, watched)

    def test_refuse_unowned_install(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            game = Path(tmp)
            (game / 'data').mkdir()
            (game / 'mods/nw_live_preview').mkdir(parents=True)
            with self.assertRaisesRegex(RuntimeError, 'unowned'):
                live_preview.publish(game, 'r1', 'unused')

    def test_client_lifecycle(self):
        # Exercise freshly bundled Lua without invoking any artwork builders or
        # depending on a prior stage/main-mod installation. Asset bytes are not
        # consumed by the minimal engine adapter below.
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        stage = Path(temporary.name)
        revision = stage / 'live/r1'
        (revision / 'anim').mkdir(parents=True)
        banks = {key: 'nw_preview_' + key + '_r1' for key in
                 ('spark', 'world', 'elemental', 'tools', 'fields', 'electric')}
        (stage / 'live/current.txt').write_text('r1 ' + ' '.join(banks.values()) + '\n', encoding='utf8')
        (revision / 'visual.lua').write_text(live_preview.visual_source(banks), encoding='utf8')
        for bank in banks.values():
            (revision / 'anim' / (bank + '.zip')).touch()
        vm = LuaRuntime(unpack_returned_tuples=True)
        vm.globals().MODROOT = stage.as_posix() + '/'
        vm.execute('''
GLOBAL=_G; FRAMES=1/30; DEGREES=math.pi/180
AddClassPostConstruct=function(name,fn) assert(name=='widgets/controls') end
ANIM_ORIENTATION={BillBoard=1,OnGround=2}
TheCamera={heading=0,pitch=35}; now=0
TheNet={IsDedicated=function() return false end,IsServerPaused=function() return false end}
function GetTime() return now end
tasks={};entities={};loaded={};unloads=0
local function eventable(object)
 object.events={}
 function object:ListenForEvent(event,fn)
  self.events[event]=self.events[event] or {};self.events[event][fn]=true
 end
 function object:RemoveEventCallback(event,fn)
  if self.events[event] then self.events[event][fn]=nil end
 end
 function object:PushEvent(event)
  local callbacks={};for fn in pairs(self.events[event] or {}) do callbacks[#callbacks+1]=fn end
  for _,fn in ipairs(callbacks) do fn(self) end
 end
 return object
end
TheWorld={DoPeriodicTask=function(self,period,fn)
 local t={fn=fn,Cancel=function(self) self.cancelled=true end};tasks[#tasks+1]=t;return t
end}
eventable(TheWorld)
function CreateEntity()
 local e=eventable({valid=true,entity={},Transform={},AnimState={},components={},x=0,y=0,z=0,r=0,own_tasks={}})
 local noop=function() end
 for _,k in ipairs({'AddTransform','AddAnimState','SetParent','SetCanSleep'}) do e.entity[k]=noop end
 e.entity.IsVisible=function() return true end
 e.entity.GetParent=function() return nil end
 e.Transform.SetPosition=function(_,x,y,z) e.x=x;e.y=y;e.z=z end
 e.Transform.GetWorldPosition=function() return e.x,e.y,e.z end
 e.Transform.SetRotation=function(_,r) e.r=r end
 e.Transform.GetRotation=function() return e.r end
 e.Transform.SetFourFaced=noop
 e.Transform.SetScale=function(_,x,y,z) e.scale=x;assert(x==y and y==z) end
 for _,k in ipairs({'SetBank','SetBuild','SetOrientation','SetLightOverride','PlayAnimation','OverrideSymbol','SetTime','SetDeltaTimeMultiplier',
  'SetFinalOffset','SetSortWorldOffset','SetBloomEffectHandle','SetMultColour','PushAnimation'}) do e.AnimState[k]=noop end
 e.AnimState.SetBank=function(_,bank) e.bank=bank end
 e.AnimState.PlayAnimation=function(_,name,loop) e.anim=name;e.loop=loop end
 e.AnimState.SetScale=function(_,x,y) e.scale_x=x;e.scale_y=y end
 e.AddTag=noop;e.ForceFacePoint=noop
 e.Hide=function() e.hidden=true end;e.Show=function() e.hidden=false end
 e.DoTaskInTime=function(_,delay,fn)
  local t={due=now+delay,fn=function() fn(e) end,Cancel=function(self) self.cancelled=true end}
  tasks[#tasks+1]=t;e.own_tasks[#e.own_tasks+1]=t;return t
 end
 e.DoPeriodicTask=function(_,period,fn)
  local t={fn=function() if e.valid then fn(e) end end,Cancel=function(self) self.cancelled=true end}
  tasks[#tasks+1]=t;e.own_tasks[#e.own_tasks+1]=t;return t
 end
 function e:AddComponent(name)
  assert(name=='updatelooper','unexpected preview component: '..name)
  local component={wallfns={}}
  function component:AddOnWallUpdateFn(fn) self.wallfns[fn]=true end
  function component:RemoveOnWallUpdateFn(fn) self.wallfns[fn]=nil end
  self.components[name]=component;return component
 end
 e.IsValid=function() return e.valid end
 e.Remove=function() if e.valid then
  e.valid=false;e:PushEvent('onremove');for _,t in ipairs(e.own_tasks) do t:Cancel() end
  if e.components.updatelooper then e.components.updatelooper.wallfns={} end
 end end
 entities[#entities+1]=e;return e
end
ThePlayer=CreateEntity()
ThePlayer.HasTag=function() return false end
Asset=function(kind,path)
 if not path:match('^anim/') then local f=assert(io.open(path,'rb'));f:close() end
 return {type=kind,file=path}
end
TheSim={GetTimeScale=function() return 1 end,
 RegisterPrefab=function(_,name,assets) loaded[name]=assets end,
 LoadPrefabs=function(_,names) assert(loaded[names[1]]) end,
 UnloadPrefabs=function() unloads=unloads+1 end,
 UnregisterPrefabs=function(_,names) loaded[names[1]]=nil end}
function wallframe(dt)
 if TheNet:IsServerPaused() then return end
 local batch={};for _,e in ipairs(entities) do batch[#batch+1]=e end
 for _,e in ipairs(batch) do
  local updater=e.components.updatelooper
  if e.valid and updater then
   local callbacks={};for fn in pairs(updater.wallfns) do callbacks[#callbacks+1]=fn end
   for _,fn in ipairs(callbacks) do if e.valid then fn(e,dt) end end
  end
 end
end
function advance()
 wallframe(FRAMES/2)
 now=now+FRAMES
 local batch={};for _,t in ipairs(tasks) do batch[#batch+1]=t end
 for _,t in ipairs(batch) do
  if not t.cancelled and (not t.due or now>=t.due) then
   if t.due then t:Cancel() end;t.fn()
  end
 end
 wallframe(FRAMES/2)
end
''')
        # DST modmain has its own environment, not the game global table.
        # In particular, bare assert is absent; utilities must use GLOBAL.
        vm.eval('''function(source)
            local env={GLOBAL=_G,MODROOT=MODROOT,print=print,AddClassPostConstruct=AddClassPostConstruct}
            local fn=assert(loadstring(source));setfenv(fn,env);fn()
        end''')((ROOT / 'tools/preview_mod/modmain.lua').read_text(encoding='utf8'))
        vm.execute('''
nw_preview('spark',20)
for i=1,25 do advance() end -- includes a full launch cycle and live tail creation
assert(#entities>4,'spark trail did not create entities')
nw_preview_refresh()
assert(unloads==1,'refresh must unload prior resource registration')
-- Launch through the public entry point; inspect movement before cycle reset.
nw_preview('spark',1000)
local fast
for _,e in ipairs(entities) do if e.valid and e._visual then fast=e end end
assert(fast,'maximum speed launch failed')
local fastx=fast.x
advance()
assert(math.abs(fast.x-fastx-95*FRAMES)<.000001,'preview entry point must clamp speed to 95')
nw_preview('arrow',10,90,2)
for i=1,10 do advance() end
-- Both elemental paths use their own bank/loop and produce detached tails.
-- Run long enough to respawn a complete flight and exercise cycle cleanup.
for _,id in ipairs({'fire','frost'}) do
 nw_preview(id,20,45,2.5)
 for i=1,25 do advance() end
 local head,tail=false,false
 for _,e in ipairs(entities) do
  if e.valid and e.anim and e.anim:match('^'..id..'_dir_') then
   assert(e.bank:match('^nw_preview_elemental_'),'elemental head used production or old world bank')
   assert(e.loop and e.scale==2.5,'elemental preview applied an extra legacy scale')
   head=true
  elseif e.valid and e.anim and e.anim:match('^'..id..'_tail_dir_') then
   assert(e.bank:match('^nw_preview_elemental_'))
   assert(e.scale==2.5,'elemental tail lost giant scaling');tail=true
  end
 end
 assert(head and tail,id..' preview missed its animated head or detached tail')
 local assetcount=0
 for _,assets in pairs(loaded) do assetcount=assetcount+#assets end
 assert(assetcount==9,'preview must register six isolated banks, native laser, shadow and shock')
 nw_preview_refresh()
 for i=1,5 do advance() end
end
nw_preview('end_beam',20,45,2.5)
for i=1,20 do advance() end
local beam
for _,e in ipairs(entities) do
 if e.valid and e._beam_path then beam=e end
 assert(not (e.valid and e.anim and e.anim:match('^end_beam_dir_')),'beam kept its painted head')
end
assert(beam and beam._beam_ended:value(),'beam front did not stop at 12 units')
local lastid,last=0
for id,part in pairs(beam._nw_beam_visual.parts) do
 if id>lastid then lastid,last=id,part end
end
local lastfx=last and last.fx._nw_beam_slices[1]
assert(lastfx and lastfx.bank=='nw_end_beam' and lastfx.anim:match('^beam_'))
assert(math.abs(last.radius-.3)<.00001,'beam width ignored preview size')
local length,width,x,z=last.length,lastfx.scale_y,last.x2,last.z2
for i=1,38 do advance() end
assert(beam.valid and lastfx.valid,'beam restarted before its final span faded')
assert(last.length==length and last.x2==x and last.z2==z,'stored span moved or shortened')
assert(lastfx.scale_y>0 and lastfx.scale_y<width,'final span did not narrow during fade')
for i=1,10 do advance() end
assert(not beam.valid,'beam did not restart after all spans expired')
local restarted=false
for _,e in ipairs(entities) do if e.valid and e._beam_path then restarted=true end end
assert(restarted,'beam cycle did not relaunch')
for _,id in ipairs({'orange_bolt','fishingrod','oceanfishingrod','trident','farm_hoe','yoth_lance'}) do
 nw_preview(id,10,135,2.5)
 for i=1,12 do advance() end
 local found=false
 for _,e in ipairs(entities) do
  if e.valid and e.anim and e.anim:match('^'..id..'_dir_') then
   assert(e.bank:match('^nw_preview_tools_'),'tool used the old world bank')
   assert(e.scale==2.5,'tool size was applied twice');found=true
  end
 end
 assert(found,'tool did not render: '..id)
end
for _,id in ipairs({'crystal_mine','sleep_crystal','payload_egg','moon_fall','delay_seal',
 'detonate','rain_cloud','storm_cloud','guard_ring','shock_ring','vortex','deer_decoy',
 'vital_ring','spore_sentry'}) do
 nw_preview(id,20,45,2.5)
 for i=1,12 do advance() end
 if id=='guard_ring' or id=='vital_ring' then
  local count,large,small,motes=0,0,0,0
  local first
  for _,e in ipairs(entities) do
   if e.valid and not e.hidden and e.anim and e.anim:match('^'..(id=='guard_ring' and 'guard' or 'vital')..'_member_') then
    assert(e.bank:match('^nw_preview_fields_'),'member used production bank')
    if id=='guard_ring' then assert(e.scale==5,'shield size mismatches real field')
    elseif e.scale==2.5 then large=large+1
    else
     assert(e.scale>=2.5*.36 and e.scale<=2.5*.62,'small mushroom lost its authored size range')
     small=small+1
    end
    first=first or e
    count=count+1
   elseif e.valid and not e.hidden and e.anim and e.anim:match('^vital_mote_') then
    motes=motes+1
   end
  end
  assert(count==(id=='guard_ring' and 2 or 20),'independent members missing')
  if id=='vital_ring' then
   assert(large==8 and small==12 and motes==6,'mushroom/mote population mismatch')
  else
   local simtime,x,z=GetTime(),first.x,first.z
   wallframe(FRAMES/2)
   assert(GetTime()==simtime and (first.x~=x or first.z~=z),'shield still waits for the next simulation tick')
  end
 end
 -- Exercise pulse/end/restart and local-only ending FX, including spirit deer.
 for i=1,120 do advance() end
 nw_preview_refresh()
end
nw_preview_stop()
for _,t in ipairs(tasks) do assert(t.cancelled,'periodic task leaked') end
for _,e in ipairs(entities) do
 assert(e==ThePlayer or not e.valid,'visual entity leaked')
 assert(not e.components.updatelooper or next(e.components.updatelooper.wallfns)==nil,'wall callback leaked')
end
assert(next(loaded)==nil,'asset registration leaked')
assert(next(TheWorld.events.onremove or {})==nil,'beam world callback leaked')
-- Failed module reads must unload assets and permit retrying the same revision.
local original_open=io.open
io.open=function(path,mode)
 if path:match('/visual.lua$') then return nil end
 return original_open(path,mode)
end
nw_preview('spark')
assert(next(loaded)==nil,'failed launch retained asset registration')
for _,t in ipairs(tasks) do assert(t.cancelled,'failed launch leaked task') end
io.open=original_open
nw_preview('spark')
for i=1,10 do advance() end
assert(next(loaded)~=nil,'retry failed to load the same revision')
nw_preview_stop()
for _,e in ipairs(entities) do assert(e==ThePlayer or not e.valid,'retry leaked entity') end
''')

    def test_panel_controls(self):
        vm = LuaRuntime(unpack_returned_tuples=True)
        vm.globals().package.path = (ROOT / 'mod/scripts/?.lua').as_posix() + ';' + vm.globals().package.path
        vm.globals().max_speed = vm.execute(
            (ROOT / 'mod/scripts/nw/spell_limits.lua').read_text(encoding='utf8')).max_speed
        vm.execute('''
function Class(base,ctor)
 local c={_ctor=ctor};c.__index=c
 setmetatable(c,{__index=base,__call=function(_,...) local s=setmetatable({},c);ctor(s,...);return s end})
 return c
end
local W=Class(nil,function(self,name) self.name=name;self.children={};self.shown=true end)
function W:AddChild(child) self.children[#self.children+1]=child;return child end
function W:SetText(text) self.text=text end
function W:SetString(text) self.text=text end
function W:SetOnClick(fn) self.click=fn end
function W:Hide() self.shown=false end
function W:Show() self.shown=true end
for _,k in ipairs({'SetPosition','SetClickable','SetSize','SetTint','SetHAnchor','SetVAnchor',
 'SetScaleMode','ForceImageSize','SetImageNormalColour','SetImageFocusColour','SetFont',
 'SetTextSize','SetHoverText','StartUpdating','SetColour','SetTextColour',
 'SetTextFocusColour','SetTextDisabledColour'}) do W[k]=function() end end
local T=Class(W,function(self,font,size,text) W._ctor(self,'text');self.text=text end)
package.preload['widgets/widget']=function() return W end
package.preload['widgets/image']=function() return W end
package.preload['widgets/imagebutton']=function() return W end
package.preload['widgets/text']=function() return T end
BODYTEXTFONT='font';ANCHOR_LEFT=0;ANCHOR_BOTTOM=1;SCALEMODE_NONE=0
CONTROL_ACCEPT=1;MOUSEBUTTON_LEFT=0
calls={};running=false
api={start=function(...) calls[#calls+1]={...};running=true end,
 stop=function() running=false end,refresh=function() refreshed=true end,
 status=function() return 'ready',running,'r1' end}
''')
        panel = vm.execute((ROOT / 'tools/preview_mod/scripts/widgets/nw_live_preview_panel.lua').read_text(encoding='utf8'))
        vm.globals().panel = panel(vm.globals().api)
        vm.execute('''
function click(text)
 for _,b in ipairs(panel.body.children) do if b.text==text and b.click then b.click();return end end
 error('Missing button '..text)
end
assert(#panel.spellbuttons==20)
panel.spellbuttons[2].click();assert(#calls==0,'selection should not start stopped preview')
click('开始 / 重播');assert(calls[1][1]=='arrow' and calls[1][2]==20)
panel.spellbuttons[1].click();assert(calls[2][1]=='spark','live selection did not apply')
click('+');assert(calls[3][2]==25,'speed change did not apply')
for i=1,20 do click('+') end
assert(panel.speed==max_speed and calls[#calls][2]==max_speed,'speed differs from shared limit')
click('刷新素材');assert(refreshed)
panel.toggle.click();assert(not panel.body.shown and running,'collapse paused preview')
panel.toggle.click();assert(panel.body.shown)
click('停止');assert(not running)
panel:OnUpdate(0);assert(panel.status.text=='ready')
-- Test screen-space dragging with a scaled parent, clamping and release.
screenw=2560;screenh=1600;mouse={x=400,y=700};down=true
TheSim={GetScreenSize=function() return screenw,screenh end}
TheInput={GetScreenPosition=function() return mouse end,IsMouseDown=function() return down end}
ThePlayer={HUD={}};TheFrontEnd={GetActiveScreen=function() return ThePlayer.HUD end}
panel.parent={GetScale=function() return {x=2,y=2} end}
panel.pos={x=0,y=0};panel.saved=nil
panel.GetPosition=function(self) return self.pos end
panel.GetWorldPosition=function(self) return {x=self.pos.x*2,y=self.pos.y*2} end
panel.SetPosition=function(self,x,y) self.pos={x=x,y=y} end
panel.SetScale=function(self,x,y) self.scale={x=x,y=y} end
panel:PlaceWindow();assert(panel.pos.x*2==417,'initial panel is clipped')
assert(panel.scale.x*2==2.25,'panel should default to 2.25x')
local count=#calls
panel.zoomout.click();assert(panel.scale.x*2==2,'zoom out failed')
panel.zoomin.click();assert(panel.scale.x*2==2.25,'zoom in failed')
assert(#calls==count,'UI zoom must not relaunch or resize projectiles')
panel.handle:OnMouseButton(MOUSEBUTTON_LEFT,true)
local before=panel.pos.x*2
mouse.x=mouse.x+100;panel:PlaceWindow()
assert(panel.pos.x*2==before+100,'drag must follow screen pixels')
mouse.x=-5000;mouse.y=-5000;panel:PlaceWindow()
assert(panel.pos.x*2>=417 and panel.pos.y*2>=1328.25,'panel escaped screen')
down=false;panel:PlaceWindow();assert(not panel.drag,'drag did not release')
screenw=800;screenh=600;panel:PlaceWindow()
assert(panel.scale.y*2<1,'short screen must fit panel')
local capped=panel.actual_scale
panel.zoomout.click();assert(panel.actual_scale<capped,'shrinking capped panel had no effect')
for i=1,20 do panel.zoomout.click() end
assert(panel.ui_scale==.75,'minimum zoom failed')
click('工具刻印');assert(panel.group==2 and panel.spellbuttons[6].shown and not panel.spellbuttons[7].shown)
click('开始 / 重播');assert(calls[#calls][1]=='orange_bolt')
panel.spellbuttons[3].click();assert(calls[#calls][1]=='oceanfishingrod')
click('场地');assert(calls[#calls][1]=='crystal_mine' and panel.spellbuttons[14].shown)
panel.spellbuttons[13].click();assert(calls[#calls][1]=='vital_ring')
panel.spellbuttons[9].click();assert(calls[#calls][1]=='guard_ring')
click('投射物');assert(calls[#calls][1]=='spark' and panel.spellbuttons[20].shown)
click('停止')
''')


if __name__ == '__main__':
    unittest.main()
