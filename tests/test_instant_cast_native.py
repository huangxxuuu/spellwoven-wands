"""Exercise instant casting through installed DST controller, locomotor and SG code.

Only engine services and entity/component shells are faked. Preview dispatch,
duplicate suppression, RPC callbacks and buffered-action lifetime run native Lua.
"""
import os
from pathlib import Path
import re
import unittest
from zipfile import ZipFile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


def load_methods(lua, archive, filename, cls, names):
    source = archive.read("scripts/" + filename + ".lua").decode()
    lua.execute(cls + "={}")
    for name in names:
        start = source.index("function " + cls + ":" + name + "(")
        boundary = re.search(r"^(?:function |local function |return " + cls + r"\b)", source[start + 1:], re.M)
        end = start + 1 + boundary.start() if boundary else len(source)
        lua.execute(source[start:end])


class NativeInstantCastTest(unittest.TestCase):
    def exercise(self, path, instant, mounted=False):
        archive_path = GAME / "data/databundles/scripts.zip"
        if not archive_path.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + lua.globals().package.path
        with ZipFile(archive_path) as archive:
            for filename, cls, names in (
                ("entityscript", "EntityScript", ("GetBufferedAction", "PreviewBufferedAction", "PerformPreviewBufferedAction", "PushBufferedAction", "PerformBufferedAction", "ClearBufferedAction")),
                ("stategraph", "StateGraphInstance", ("PreviewAction", "StartAction")),
                ("components/locomotor", "LocoMotor", ("PreviewAction", "PushAction")),
                ("components/playercontroller", "PlayerController", ("OnRightClick", "DoAction", "OnRemoteRightClick", "RemoteBufferedAction")),
            ):
                load_methods(lua, archive, filename, cls, names)
            # Keep native RPC registry, metatables and queues together so closures
            # share the same locals. Only TheNet's C transport remains a shell.
            rpc_source = archive.read("scripts/networkclientrpc.lua").decode()
            lua.execute(rpc_source[rpc_source.index("local RPC_QUEUE_RATE_LIMIT ="):])
        lua.globals().test_path = path
        lua.globals().test_instant = instant
        lua.globals().test_mounted = mounted
        lua.execute(r'''
EQUIPSLOTS={HANDS="hands"};CONTROL_SECONDARY="right"
ACTIONS={NW_CAST={code=123,mod_name="nw_test",distance=math.huge,invalid_hold_action=true},WALKTO={},ATTACK={}}
RPC={RightClick=1};USERID_RPCS={}
local tick=10
GetTick=function() return tick end;GetTime=function() return tick/30 end
GetTickTime=function() return 1/30 end
TheSim={GetPersistentString=function(_,_,cb) cb(false,"") end,
    SetPersistentString=function(_,_,_,_,cb) cb() end}
SetClientRequestedAction=function() end;ClearClientRequestedAction=function() end
local pos={x=4,y=0,z=2,Get=function(self) return self.x,self.y,self.z end}
TheInput={GetWorldPosition=function() return pos end,GetWorldEntityUnderMouse=function() end,
    GetHUDEntityUnderMouse=function() end,IsControlPressed=function() return true end}
local Mode=require("nw/cast_mode")
local Cast=require("nw/cast_action")
local Pose=require("nw/hold_pose")
local pose_state,pose_init
State=function(value) return value end
ACTIONS.NW_CAST.pre_action_cb=Cast.prepare
local count=0
local wand={IsValid=function() return true end,
    _nw_ready={value=function() return true end},_nw_cancast={value=function() return true end},
    components={nw_wand={CanCast=function() return true,nil,{} end,
        Cast=function(_,doer)
            if test_instant then
                assert(doer.sg.currentstate.name==(test_mounted and "mounted_idle" or "nw_hold_pose"),
                    "actual Cast must use the authoritative pose or retain mounted idle")
                if not test_mounted then assert(doer._nw_pose_hold,"server cast requires a live pose lease") end
            end
            count=count+1;return true
        end}}}
local function action(p)
    return {doer=p,invobject=wand,action=ACTIONS.NW_CAST,options={},pos=pos,rotation=0,distance=math.huge,
        GetActionPoint=function(self) return self.pos end,
        SetActionPoint=function(self,p) self.pos=p end,
        IsValid=function() return true end,TestForStart=function() return true end,
        Fail=function(self) self.failed=true end,Succeed=function() end,
        Do=function(self) return Cast.perform(self) end}
end
local function player(master,predicted)
    local p=setmetatable({components={combat={InCooldown=function() return false end},
            inventory={GetEquippedItem=function() return wand end,GetActiveItem=function() end},
            rider={IsRiding=function() return test_mounted end}},
        replica={inventory={GetEquippedItem=function() return wand end}},
        Transform={GetWorldPosition=function() return 0,0,0 end},
        IsValid=function() return true end,HasTag=function() return false end,
        FacePoint=function() end,PushEvent=function() end,
        ListenForEvent=function() end,
        DoTaskInTime=function(self,delay,fn)
            if delay==0 then self.activate=fn end
            return {Cancel=function() end}
        end}, {__index=EntityScript})
    p.AnimState={PlayAnimation=function(_,name) p.animation=name;p.animframe=0 end,
        PushAnimation=function() end,IsCurrentAnimation=function(_,name) return p.animation==name end,
        GetCurrentAnimationFrame=function() return p.animframe end,
        GetCurrentAnimationNumFrames=function() return p.animation=="nw_hold_cast_pre" and 11 or 36 end,
        SetFrame=function(_,frame) p.animframe=frame end}
    p.sg=setmetatable({inst=p,statemem={},states={},currentstate={name=master and test_mounted and "mounted_idle" or "idle"},
        sg={actionhandlers={
        [ACTIONS.NW_CAST]={deststate=master and Cast.server_state or Cast.client_state}}},
        HasStateTag=function() return false end,
        GoToState=function(self,state)
            if self.currentstate.name==pose_state.name then pose_state.onexit(p) end
            self.states[#self.states+1]=state;self.currentstate={name=state};self.statemem={}
            if state==pose_state.name then pose_state.onenter(p) end
        end}, {__index=StateGraphInstance})
    local c=setmetatable({inst=p,ismastersim=master,remote_controls={},
        classified={iscontrollerenabled={value=function() return true end}},client_last_predict_walk={},
        UsingMouse=function() return true end,IsAOETargeting=function() return false end,
        IsEnabled=function() return true end,IsBusy=function() return false end,
        GetRightMouseAction=function() return action(p) end,GetMapTarget=function() end,
        ClearActionHold=function() end,DoActionAutoEquip=function() end,
        EncodeControlMods=function() return 17 end,DecodeControlMods=function() end,ClearControlMods=function() end,
        CanLocomote=function() return true end,OnRemoteBufferedAction=function() end,
        GetPlatformRelativePosition=function(_,x,z) return nil,x,z end}, {__index=PlayerController})
    p.components.playercontroller=c
    p.components.playeractionpicker={DoGetMouseActions=function() return nil,action(p) end}
    if master or predicted then
        c.locomotor=setmetatable({inst=p,Clear=function() end,FaceMovePoint=function() end,
            WantsToMoveForward=function() return false end,HasDestination=function() return false end}, {__index=LocoMotor})
        p.components.locomotor=c.locomotor
    end
    local previous=TheWorld.ismastersim
    TheWorld.ismastersim=master;pose_init(p);TheWorld.ismastersim=previous
    return p,c
end
local siminit,playerinit
local env={GetModConfigData=function() return test_instant end,
    AddSimPostInit=function(fn) siminit=fn end,AddPlayerPostInit=function(fn) playerinit=fn end,
    AddModRPCHandler=AddModRPCHandler,AddClientModRPCHandler=AddClientModRPCHandler}
TheWorld={ismastersim=test_path=="host",Map={IsPassableAtPoint=function() return true end}}
Pose.install({AddModRPCHandler=AddModRPCHandler,
    AddStategraphState=function(name,state) assert(name=="wilson");pose_state=state end,
    AddPlayerPostInit=function(fn) pose_init=fn end},_G)
local p,c=player(test_path=="host",test_path=="predicted")
ThePlayer=p
Mode.install(env,_G,ACTIONS.NW_CAST);siminit()
if test_path~="host" then
    -- Native Lua RPC registration/send/receive/queue dispatch, with C engine
    -- calls replaced by payload capture. Do not assume how C serializes false:
    -- the mode protocol must emit a numeric 0/1, never a boolean.
    local query
    TheNet={SendModRPCToServer=function(_,namespace,id,request)
        assert(namespace=="nw_weave" and type(request)=="number")
        query={namespace,id,request}
    end,
    SendModRPCToClient=function(_,namespace,id,userid,value,request)
        assert(userid=="native_test")
        assert(type(value)=="number" and value==(test_instant and 1 or 0),"mode must use explicit numeric wire values")
        HandleClientModRPC(1,namespace,id,{value,request})
    end,
    CallRPC=function(_,fn,sender,data)
        TheWorld.ismastersim=true
        fn(sender,unpack(data))
        TheWorld.ismastersim=false
        return true
    end,
    CallClientRPC=function(_,fn,data) fn(unpack(data));return true end}
    p.userid="native_test"
    playerinit(p);p.activate()
    assert(query and not Mode.ready(),"unsynchronized mode must remain unavailable")
    local state=CLIENT_MOD_RPC.nw_weave.cast_mode_state
    -- An absent first argument must not be mistaken for the explicit normal
    -- enum. This is input validation, not an invented C false->nil model.
    HandleClientModRPC(1,state.namespace,state.id,{[2]=query[3]})
    HandleRPCQueue()
    assert(not Mode.ready(),"nil response falsely acknowledged normal mode")
    HandleModRPC(p,1,query[1],query[2],{query[3]})
    HandleRPCQueue()
end
assert(Mode.ready() and Mode.enabled()==test_instant and ACTIONS.NW_CAST.instant==test_instant)
local packets={}
SendRPCToServer=function(...) packets[#packets+1]={...} end
local remote,server
if test_path~="host" then remote,server=player(true,false) end
for frame=1,2 do
    tick=10+frame
    local previous=#packets
    c:OnRightClick(true)
    if test_path=="host" then
        if test_instant then
            assert(count==frame,"host instant cast did not execute once per frame")
            assert(p:GetBufferedAction()==nil,"host instant left buffered action")
            assert(#p.sg.states==(test_mounted and 0 or 1),"host instant must enter only one pose, never attack")
            if not test_mounted then assert(p.sg.states[1]=="nw_hold_pose" and p.sg.statemem.recoil>0) end
        else
            assert(p.sg.states[#p.sg.states]=="attack","legacy host lost attack")
            assert(p:GetBufferedAction()~=nil,"legacy host lost buffered attack")
            assert(p:PerformBufferedAction())
        end
    else
        if test_path=="predicted" then
            if test_instant then
                assert(#p.sg.states==0,"instant preview entered attack/previewaction")
                assert(p:GetBufferedAction()==nil,"instant preview was not cleared natively")
            else
                assert(p.sg.states[#p.sg.states]=="attack","legacy prediction lost attack")
                assert(p:GetBufferedAction()~=nil)
                -- Native attack's scheduled preview boundary, without importing its animation services.
                p:PerformPreviewBufferedAction()
                p:ClearBufferedAction()
            end
        end
        local actionpackets=0
        for i=previous+1,#packets do
            local packet=packets[i]
            assert(packet[1]==RPC.RightClick)
            if packet[2]~=nil then
                actionpackets=actionpackets+1
                assert(packet[2]==123 and packet[3]==pos.x and packet[4]==pos.z and packet[10]=="nw_test")
                TheWorld.ismastersim=true
                server:OnRemoteRightClick(packet[2],pos,packet[5],packet[6],packet[7],packet[8],packet[9],packet[10])
                if test_instant then
                    assert(remote:GetBufferedAction()==nil,"server instant left buffered action")
                    assert(#remote.sg.states==(test_mounted and 0 or 1),"server instant must enter only one pose, never attack")
                    if not test_mounted then assert(remote.sg.states[1]=="nw_hold_pose" and remote.sg.statemem.recoil>0) end
                else
                    assert(remote.sg.states[#remote.sg.states]=="attack","legacy remote lost attack")
                    assert(remote:PerformBufferedAction())
                end
                TheWorld.ismastersim=false
            end
        end
        -- Prediction also sends one control-down packet, which has no action code.
        assert(actionpackets==1,"native action RPC duplicated or second frame was suppressed")
        assert(count==frame,"remote execution was not exactly once per frame")
    end
end
''')

    def test_instant_host(self):
        self.exercise("host", True)

    def test_instant_predicted(self):
        self.exercise("predicted", True)

    def test_instant_unpredicted(self):
        self.exercise("unpredicted", True)

    def test_mounted_instant_host(self):
        self.exercise("host", True, mounted=True)

    def test_mounted_instant_predicted(self):
        self.exercise("predicted", True, mounted=True)

    def test_mounted_instant_unpredicted(self):
        self.exercise("unpredicted", True, mounted=True)

    def test_legacy_host(self):
        self.exercise("host", False)

    def test_legacy_predicted(self):
        self.exercise("predicted", False)

    def test_legacy_unpredicted(self):
        self.exercise("unpredicted", False)


if __name__ == "__main__":
    unittest.main()
