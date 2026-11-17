"""Exercise dedicated casting through installed DST Input/PlayerController Lua.

Only C physical state/mapping, FrontEnd consumption, event subscriptions,
Binding synchronization, action selection and DoAction/SG lifetime are shells.
The production cast_input, cast_key and hold_cast code runs unchanged. Engine
binding persistence, real settings UI and network transport need game testing.
"""
import os
from pathlib import Path
import re
import unittest
from zipfile import ZipFile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOD_ROOT = Path(os.environ.get("NW_CAST_TEST_MOD_ROOT", str(ROOT / "mod")))
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


def load_methods(lua, archive, filename, cls, names):
    source = archive.read("scripts/" + filename + ".lua").decode()
    lua.execute(cls + "={}")
    for name in names:
        start = source.index("function " + cls + ":" + name + "(")
        boundary = re.search(r"^(?:function |local function |return " + cls + r"\b)", source[start + 1:], re.M)
        end = start + 1 + boundary.start() if boundary else len(source)
        if filename == "input" and name == "ResolveVirtualControls":
            # Keep the native resolver's local remap tables/predicates in its
            # lexical scope; extracting just the method hides virtual controls.
            start = source.index("local RemapTo_CONTROL_INVENTORY =")
        lua.execute(source[start:end])


class NativeCastInputTest(unittest.TestCase):
    def exercise(self, case, master, instant):
        archive_path = GAME / "data/databundles/scripts.zip"
        if not archive_path.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = (MOD_ROOT / "scripts/?.lua").as_posix() + ";" + lua.globals().package.path
        lua.execute("ValidateLineNumber=function() end")
        with ZipFile(archive_path) as archive:
            constants = archive.read("scripts/constants.lua").decode()
            # Native integer enums, including physical/custom/virtual bounds.
            lua.execute("\n".join(re.findall(
                r"^(?:CONTROL|VIRTUAL_CONTROL)_[A-Z0-9_]+\s*=\s*\d+[^\r\n]*", constants, re.M)))
            load_methods(lua, archive, "input", "Input", (
                "OnControl", "OnRawKey", "OnMouseButton", "IsMouseDown", "IsKeyDown",
                "IsControlPressed", "ResolveVirtualControls", "AddGeneralControlHandler",
                "AddKeyHandler", "AddMouseButtonHandler"))
            load_methods(lua, archive, "components/playercontroller", "PlayerController", (
                "OnControl", "OnRightClick", "RemoteStopControl"))
        lua.globals().test_master = master
        lua.globals().test_instant = instant
        lua.globals().test_case = case
        lua.execute(r'''
EQUIPSLOTS={HANDS="hands"}
ACTIONS={NW_CAST={code=123,mod_name="test"},BLINK={code=124},WALKTO={}}
RPC={RightClick=1,StopControl=2}
local ticks,shots,blinks,actions,stops,packets=0,0,0,0,0,0
local ready_at,attacking_until,mana=0,0,true
local visible,fallback_hides=true,false
GetTick=function() return ticks end;GetTime=function() return ticks/30 end
IsPaused=function() return false end
local physical_state={}
local mapping={[CONTROL_PRIMARY]=1000,[CONTROL_SECONDARY]=1001,[CONTROL_MOVE_UP]=119,[CONTROL_ACTION]=102}
local c_calls={}
local function strict_control(control)
    assert(type(control)=="number" and control==math.floor(control) and control>=0 and control<CONTROL_CUSTOM_START,
        "C control enum boundary violated: "..tostring(control))
end
TheSim={GetDigitalControl=function(_,control) strict_control(control);return physical_state[mapping[control]] or false end,
    GetMouseButtonState=function(_,button) return physical_state[button] or false end,
    IsKeyDown=function(_,code) return physical_state[code] or false end}
TheInputProxy={GetLocalizedControl=function(_,device,control,localized,raw)
    c_calls[#c_calls+1]=control
    strict_control(control)
    assert(device==0 and localized==false and raw==true)
    return 1,1,mapping[control]
end}
TheNet={GetAveragePing=function() return 150 end,IsDedicated=function() return false end}
SendRPCToServer=function(kind)
    if kind==RPC.StopControl then stops=stops+1 else packets=packets+1 end
end
local screen,scheme,spellwheel,crafting= nil,1,false,false
TheFrontEnd={GetActiveScreen=function() return screen end,
    OnControl=function() return screen~=ThePlayer.HUD end,OnMouseButton=function() end}
local function events()
    local handlers={}
    return {AddEventHandler=function(_,event,fn)
        handlers[event]=handlers[event] or {};table.insert(handlers[event],fn);return {}
    end,HandleEvent=function(_,event,...)
        for _,fn in ipairs(handlers[event] or {}) do fn(...) end
    end}
end
TheInput=setmetatable({mouse_enabled=true,oncontrol=events(),onkey=events(),
    onmousebutton=events(),onkeydown=events(),onkeyup=events(),
    GetHUDEntityUnderMouse=function() end,
    GetWorldPosition=function() return {x=4,y=0,z=2} end,
    GetActiveControlScheme=function(_,category) assert(category==CONTROL_SCHEME_CAM_AND_INV);return scheme end,
    GetWorldEntityUnderMouse=function() end}, {__index=Input})
local binding,synced,subscriber="mouse:1002",true
package.loaded["nw/cast_binding"]={get=function() return binding end,ready=function() return synced end,
    subscribe=function(fn) subscriber=fn;return function() end end}
local wand={IsValid=function() return true end,_nw_ready={value=function() return true end},
    _nw_cancast={value=function() return mana and ticks>=ready_at end},
    components={nw_wand={CanCast=function() return mana and ticks>=ready_at end}}}
local equipped=wand
local inv={GetEquippedItem=function() return equipped end,GetActiveItem=function() end,IsVisible=function() return false end}
local p={components={},replica={inventory=inv},HUD={
    IsSpellWheelOpen=function() return spellwheel end,IsCraftingOpen=function() return crafting end,
    IsControllerInventoryOpen=function() return false end},
    Transform={GetWorldPosition=function() return 0,0,0 end},
    HasTag=function(_,tag) return tag=="attack" and ticks<attacking_until end,
    IsActionsVisible=function() return visible end,GetBufferedAction=function() end,
    ListenForEvent=function(self,event,fn) self[event]=fn end}
p.sg={currentstate={name="idle"},HasStateTag=function(_,tag) return p:HasTag(tag) end}
ThePlayer=p;screen=p.HUD
local function action(kind)
    return {doer=p,invobject=wand,action=kind,rotation=0,GetActionPoint=function() return {x=4,z=2} end}
end
local Cast=require("nw/cast_action")
-- Action selection is a shell: ready wand supplies NW_CAST; native scene/
-- character actions supply BLINK. Only a dedicated right key gets that fallback.
Cast.input_action=function(player,native)
    assert(player==p)
    if native then return action(ACTIONS.BLINK) end
    if mana and ticks>=ready_at then return action(ACTIONS.NW_CAST) end
    if binding=="mouse:1001" then return action(ACTIONS.BLINK) end
end
local pc=setmetatable({inst=p,ismastersim=test_master,remote_controls={},
    UsingMouse=function() return true end,IsEnabled=function() return true end,
    IsBusy=function() return false end,IsAOETargeting=function() return false end,
    IsTwinStickAiming=function() return false end,
    IsControllerTargetLockEnabled=function() return false end,
    ClearActionHold=function() end,GetMapTarget=function() end,
    EncodeControlMods=function() return 0 end,
    GetPlatformRelativePosition=function(_,x,z) return nil,x,z end,
    GetRightMouseAction=function() return action(ACTIONS.BLINK) end,
    DoActionButton=function() actions=actions+1 end,OnUpdate=function() end,
    DoAction=function(_,act)
        if act.non_preview_cb then act.non_preview_cb() end
        if act.action==ACTIONS.BLINK then
            blinks=blinks+1
            if fallback_hides then visible=false end
            return
        end
        assert(act.action==ACTIONS.NW_CAST)
        shots=shots+1;ready_at=ticks+4
        if not test_instant then attacking_until=ticks+2 end
    end}, {__index=PlayerController})
p.components.playercontroller=pc
local forwarded={}
pc.handler=TheInput:AddGeneralControlHandler(function(control,value)
    forwarded[#forwarded+1]={control,value}
    pc:OnControl(control,value)
end)
-- Boot the real mode module into an acknowledged mode; mode RPC is tested elsewhere.
TheWorld={ismastersim=true}
local siminit
require("nw/cast_mode").install({GetModConfigData=function() return test_instant end,
    AddSimPostInit=function(fn) siminit=fn end,AddPlayerPostInit=function() end,
    AddModRPCHandler=function() end,AddClientModRPCHandler=function() end},_G,ACTIONS.NW_CAST)
siminit();TheWorld.ismastersim=test_master
local input=require("nw/cast_input")
input.install({AddPlayerPostInit=function(fn) fn(p) end},_G)
require("nw/hold_cast").install(pc)
p.playeractivated()
local function frame(n) for _=1,n or 1 do ticks=ticks+1;pc:OnUpdate(1/30) end end
local function settle() frame(30) end
local function bind(value) binding=value;subscriber() end
local function physical(code,down,order)
    physical_state[code]=down
    local function controls()
        for id,mapped in pairs(mapping) do
            if mapped==code then TheInput:OnControl(id,down,down and 1 or 0) end
        end
    end
    local function raw()
        if code>=1000 then TheInput:OnMouseButton(code,down,0,0) else TheInput:OnRawKey(code,down) end
    end
    if order=="raw" then raw();controls() else controls();raw() end
end
local function click(code,order) physical(code,true,order);physical(code,false,order) end
local cases={}
function cases.bindings()
    for _,secondary in ipairs({1001,1002,1001}) do
        mapping[CONTROL_SECONDARY]=secondary
        for _,key in ipairs({"mouse:1002","mouse:1005","mouse:1006","key:107"}) do
            bind(key);settle()
            local code=tonumber(key:match(":(%d+)$"))
            for _,order in ipairs({"raw","control"}) do
                local before=shots;click(code,order)
                assert(shots==before+1,"independent single cast missing/duplicated: "..key.."/"..order)
                settle();assert(shots==before+1,"released click repeated")
                before=shots;physical(code,true,order);frame(45)
                assert(shots>before+1,"hold failed to poll raw binding: "..key)
                physical(code,false,order);before=shots;settle();assert(shots==before,"release did not stop hold")
            end
            if secondary~=code then
                local before,oldblink=shots,blinks;click(secondary)
                assert(shots==before and blinks==oldblink+1,"native secondary must retain BLINK")
            end
        end
    end
    if not test_master then assert(packets>0 and stops>0,"native client RPC branches were bypassed") end
end
function cases.conflicting_controls()
    bind("key:102")
    for _,order in ipairs({"control","raw"}) do
        settle();local before,oldactions=shots,actions
        physical(102,true,order)
        assert(shots==before+1 and actions==oldactions,"F game action leaked or cast duplicated")
        assert(not TheInput:IsControlPressed(CONTROL_ACTION),"held F control leaked while casting")
        physical(102,false,order);settle()
    end
    bind("key:119");settle();local before=shots
    physical(119,true);assert(shots==before+1,"bound W was incorrectly treated as movement")
    assert(not TheInput:IsControlPressed(CONTROL_MOVE_UP));physical(119,false)
    bind("key:102");equipped=nil;settle();local oldactions=actions;physical(102,true)
    assert(TheInput:IsControlPressed(CONTROL_ACTION),"unequipped game input poll was swallowed")
    physical(102,false);assert(actions==oldactions+1,"unequipped F game action was swallowed")
end
function cases.simultaneous_buttons()
    bind("mouse:1002");settle();physical(1002,true)
    local before,oldblink=shots,blinks
    click(1001)
    assert(blinks==oldblink+1 and shots==before,"right secondary was swallowed while holding middle cast")
    frame(30);assert(shots>before,"secondary right action disarmed independent middle hold")
    physical(1002,false)
end
function cases.right_fallback()
    bind("mouse:1001");settle()
    click(1001);assert(shots==1 and blinks==0)
    click(1001);assert(shots==1 and blinks==1,"cooldown right key failed native fallback")
    settle();mana=false;click(1001)
    assert(shots==1 and blinks==2,"empty mana right key failed native fallback")
    bind("mouse:1002");click(1002)
    assert(shots==1 and blinks==2,"custom cast key incorrectly triggered BLINK fallback")
    physical(1002,false);mana=true;settle();click(1002)
    assert(shots==2,"mana recovery did not restore casting")
end
function cases.ui_and_focus()
    for _,block in ipairs({"screen","capture","edit","drag"}) do
        settle()
        if block=="screen" then screen={} elseif block=="capture" then p._nw_binding_capture={}
        elseif block=="edit" then p._nw_editing=true else p._nw_hud_dragging={} end
        local before=shots;physical(1002,true);frame()
        screen=p.HUD;p._nw_binding_capture=nil;p._nw_editing=nil;p._nw_hud_dragging=nil
        frame(30);assert(shots==before,"UI-held key cast after returning: "..block)
        physical(1002,true);frame();assert(shots==before,"raw key repeat rearmed after UI: "..block)
        physical(1002,false);settle();click(1002);assert(shots==before+1,"new click did not recover after UI")
    end
    settle();physical(1002,true);OnFocusLost();local before=shots
    frame(30);OnFocusGained();frame(30)
    assert(shots==before,"focus restoration rearmed held button")
    physical(1002,false);settle();click(1002);assert(shots==before+1)
    local cancelled=false;p._nw_binding_capture={cancel=function() cancelled=true;p._nw_binding_capture=nil end}
    OnFocusLost();assert(cancelled,"OS focus loss did not cancel capture");OnFocusGained()
end
function cases.switch_and_unequip()
    physical(1002,true);bind("key:107");local before=shots
    frame(30);assert(shots==before,"old held binding survived preference change")
    physical(1002,false);click(107);assert(shots==before+1,"new binding failed")
    settle();physical(107,true);equipped=nil;frame();before=shots
    equipped=wand;frame(30);assert(shots==before,"reequipping resurrected held cast")
    physical(107,false);settle();click(107);assert(shots==before+1)
    settle();physical(107,true);synced=false;subscriber();before=shots
    frame(30);synced=true;subscriber();frame(30);assert(shots==before,"sync return resurrected old hold")
    physical(107,false);settle();click(107);assert(shots==before+1)
end
function cases.missing_release()
    physical(1002,true)
    -- A missing raw up still leaves a cleared engine state for polling.
    physical_state[1002]=false;frame();local before=shots
    settle();assert(shots==before,"missing up ignored physical polling")
    physical(1002,true);physical(1002,false)
    assert(shots==before+1,"missing raw up swallowed the next press")
end
function cases.lost_control_release()
    bind("key:102");physical(102,true)
    assert(shots==1 and #forwarded==0,"bound F control down must initially be swallowed")
    -- Lose both release callbacks, then stop intercepting because no wand is
    -- equipped. The new native press must clear stale swallowed-control state.
    physical_state[102]=false;frame();equipped=nil
    physical(102,true);physical(102,false)
    assert(actions==1,"unequipped native F down did not reach the controller")
    assert(#forwarded==2 and forwarded[1][1]==CONTROL_ACTION and forwarded[1][2]==true
        and forwarded[2][1]==CONTROL_ACTION and forwarded[2][2]==false,
        "stale swallowed state ate the native control release after a new down")
end
function cases.raw_fallback_ownership()
    bind("mouse:1001");mana=false;fallback_hides=true
    physical(1001,true,"raw")
    assert(not visible and blinks==1 and #forwarded==0,
        "raw fallback changed action visibility and leaked the same native control down")
    physical(1001,false,"raw")
    visible=true;fallback_hides=false;settle()
    click(1001,"raw")
    assert(blinks==2 and #forwarded==0,
        "releasing a raw-owned fallback did not restore one action on the next press")
end
function cases.legacy_virtual_boundary()
    local Key=require("nw/cast_key")
    local fixed=Key.matches_control
    -- Preserve a runtime-only copy of the original unsafe helper. The actual
    -- Input/hold hooks and native inventory alias reach the same C boundary
    -- as the load-time crash, without reverting files or calling a real C API.
    Key.matches_control=function(value,control)
        local _,code=Key.decode(value)
        if not code or not TheInputProxy then return false end
        local device,count,a,b,c,d=TheInputProxy:GetLocalizedControl(0,control,false,true)
        if device~=1 or not count or count<1 then return false end
        return a==code or (count>=2 and b==code) or (count>=3 and c==code) or (count>=4 and d==code)
    end
    local ok,err=pcall(function() return TheInput:IsControlPressed(VIRTUAL_CONTROL_INV_LEFT) end)
    Key.matches_control=fixed
    assert(not ok and tostring(err):find("C control enum boundary violated",1,true),
        "old helper did not reproduce the native load-time virtual-control boundary violation")
    assert(c_calls[#c_calls]==VIRTUAL_CONTROL_INV_LEFT,"reproduction missed the offending virtual ID")
end
function cases.virtual_inventory_boundary()
    local Key=require("nw/cast_key")
    local aliases={
        {VIRTUAL_CONTROL_INV_LEFT,CONTROL_INVENTORY_LEFT},
        {VIRTUAL_CONTROL_INV_RIGHT,CONTROL_INVENTORY_RIGHT},
        {VIRTUAL_CONTROL_INV_UP,CONTROL_INVENTORY_UP},
        {VIRTUAL_CONTROL_INV_DOWN,CONTROL_INVENTORY_DOWN},
    }
    -- inventorybar polls these as soon as the player HUD is constructed. Keep
    -- the real resolver and its lexical remap tables, not a hand-coded alias.
    for _,pair in ipairs(aliases) do
        assert(TheInput:ResolveVirtualControls(pair[1])==pair[2],"native inventory alias changed")
        assert(not TheInput:IsControlPressed(pair[1]))
        assert(c_calls[#c_calls]==pair[2],"C mapping lookup did not receive resolved inventory control")
    end
    bind("key:107");physical_state[107]=true
    for _,pair in ipairs(aliases) do
        mapping[pair[2]]=107
        assert(Input.IsControlPressed(TheInput,pair[1]),"native control fixture must be physically pressed")
        assert(Key.matches_control(binding,pair[1]),"legal virtual alias was not matched to the cast key")
        assert(not TheInput:IsControlPressed(pair[1]),"bound virtual inventory control leaked into game polling")
        assert(c_calls[#c_calls]==pair[2])
    end
    physical_state[107]=false
    spellwheel=true
    local before=#c_calls
    for _,pair in ipairs(aliases) do
        assert(TheInput:ResolveVirtualControls(pair[1])==nil)
        assert(not Key.matches_control(binding,pair[1]))
        assert(not TheInput:IsControlPressed(pair[1]))
    end
    assert(#c_calls==before,"disabled virtual controls must not enter the C mapping API")
    spellwheel=false
    assert(TheInput:ResolveVirtualControls(CONTROL_CAM_AND_INV_MODIFIER)==nil)
    assert(not Key.matches_control(binding,CONTROL_CAM_AND_INV_MODIFIER) and #c_calls==before)
    -- Only matches_control promises to validate arbitrary caller input. Native
    -- IsControlPressed retains its own engine contract; do not feed it 999.
    for _,invalid in ipairs({-1,.5,CONTROL_CUSTOM_START,999,VIRTUAL_CONTROL_START+999,
        math.huge,-math.huge,0/0,"secondary",true,{}}) do
        local ok,matched=pcall(Key.matches_control,binding,invalid)
        assert(ok and not matched,"invalid matches_control input must safely return false")
    end
    assert(not Key.matches_control(binding,nil))
    assert(#c_calls==before,"invalid matches_control input reached the C mapping API")
    for _,id in ipairs(c_calls) do strict_control(id) end
end
cases[test_case]()
''')

    def run_case(self, case):
        for master in (True, False):
            for instant in (False, True):
                with self.subTest(master=master, instant=instant):
                    self.exercise(case, master, instant)

    def test_independent_bindings_and_order(self):
        self.run_case("bindings")

    def test_conflicting_game_controls(self):
        self.run_case("conflicting_controls")

    def test_simultaneous_buttons(self):
        self.run_case("simultaneous_buttons")

    def test_right_fallback(self):
        self.run_case("right_fallback")

    def test_ui_and_focus(self):
        self.run_case("ui_and_focus")

    def test_switch_and_unequip(self):
        self.run_case("switch_and_unequip")

    def test_missing_release_recovers(self):
        self.run_case("missing_release")

    def test_lost_control_release_after_unequip(self):
        self.run_case("lost_control_release")

    def test_raw_fallback_keeps_control_ownership(self):
        self.run_case("raw_fallback_ownership")

    def test_legacy_helper_reproduces_virtual_control_crash_boundary(self):
        self.run_case("legacy_virtual_boundary")

    def test_native_virtual_inventory_polling_and_enum_boundary(self):
        self.run_case("virtual_inventory_boundary")


if __name__ == "__main__":
    unittest.main()
