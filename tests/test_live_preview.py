"""Exercise the real client tool lifecycle with a minimal Lua engine adapter."""
import sys
import unittest
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import live_preview


class PreviewTests(unittest.TestCase):
    def test_refuse_unowned_install(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            game = Path(tmp)
            (game / 'data').mkdir()
            (game / 'mods/nw_live_preview').mkdir(parents=True)
            with self.assertRaisesRegex(RuntimeError, 'unowned'):
                live_preview.publish(game, 'r1', 'unused')

    def test_client_lifecycle(self):
        stage = live_preview.STAGE
        self.assertTrue((stage / 'live/current.txt').exists(), 'Build preview resources first')
        vm = LuaRuntime(unpack_returned_tuples=True)
        vm.globals().MODROOT = stage.as_posix() + '/'
        vm.execute('''
GLOBAL=_G; FRAMES=1/30; DEGREES=math.pi/180
AddClassPostConstruct=function(name,fn) assert(name=='widgets/controls') end
ANIM_ORIENTATION={BillBoard=1,OnGround=2}
TheCamera={heading=0,pitch=35}; now=0
function GetTime() return now end
tasks={};entities={};loaded={};unloads=0
TheWorld={DoPeriodicTask=function(self,period,fn)
 local t={fn=fn,Cancel=function(self) self.cancelled=true end};tasks[#tasks+1]=t;return t
end}
function CreateEntity()
 local e={valid=true,entity={},Transform={},AnimState={},x=0,y=0,z=0,r=0}
 local noop=function() end
 for _,k in ipairs({'AddTransform','AddAnimState','SetParent','SetCanSleep'}) do e.entity[k]=noop end
 e.entity.IsVisible=function() return true end
 e.Transform.SetPosition=function(_,x,y,z) e.x=x;e.y=y;e.z=z end
 e.Transform.GetWorldPosition=function() return e.x,e.y,e.z end
 e.Transform.SetRotation=function(_,r) e.r=r end
 e.Transform.GetRotation=function() return e.r end
 e.Transform.SetScale=noop
 for _,k in ipairs({'SetBank','SetBuild','SetOrientation','SetLightOverride','PlayAnimation','OverrideSymbol','SetTime'}) do e.AnimState[k]=noop end
 e.AddTag=noop;e.ForceFacePoint=noop
 e.IsValid=function() return e.valid end
 e.Remove=function() e.valid=false end
 entities[#entities+1]=e;return e
end
ThePlayer=CreateEntity()
Asset=function(kind,path) assert(io.open(path,'rb')) return {type=kind,file=path} end
TheSim={RegisterPrefab=function(_,name,assets) loaded[name]=assets end,
 LoadPrefabs=function(_,names) assert(loaded[names[1]]) end,
 UnloadPrefabs=function() unloads=unloads+1 end,
 UnregisterPrefabs=function(_,names) loaded[names[1]]=nil end}
function advance()
 now=now+FRAMES
 local batch={};for _,t in ipairs(tasks) do batch[#batch+1]=t end
 for _,t in ipairs(batch) do if not t.cancelled then t.fn() end end
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
nw_preview('arrow',10,90,2)
for i=1,10 do advance() end
nw_preview_stop()
for _,t in ipairs(tasks) do assert(t.cancelled,'periodic task leaked') end
for _,e in ipairs(entities) do assert(e==ThePlayer or not e.valid,'visual entity leaked') end
assert(next(loaded)==nil,'asset registration leaked')
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
assert(panel.speed==60,'speed exceeds supported limit')
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
''')


if __name__ == '__main__':
    unittest.main()
