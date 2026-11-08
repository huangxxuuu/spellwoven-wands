"""Run installed native controller AND picker methods, with no controller hooks (Lua 5.1)."""
from pathlib import Path
from zipfile import ZipFile
import re
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path("E:/SteamLibrary/steamapps/common/Don't Starve Together")


def main():
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT / 'mod/scripts/?.lua').as_posix() + ';' + vm.globals().package.path
    with ZipFile(GAME / "data/databundles/scripts.zip") as archive:
        for cls, filename, methods in (
            ('PlayerController','playercontroller',('OnRightClick','DoAction','OnRemoteRightClick')),
            ('PlayerActionPicker','playeractionpicker',('SortActionList','GetEquippedItemActions',
                'GetPointActions','GetRightClickActions','DoGetMouseActions')),
        ):
            source=archive.read(f'scripts/components/{filename}.lua').decode()
            vm.execute(f'{cls}={{}}')
            for name in methods:
                start=source.index(f'function {cls}:{name}(')
                end=re.search(rf'^function {cls}:|^return {cls}',source[start+1:],re.M)
                vm.execute(source[start:start+1+end.start()])
    vm.execute('''
EQUIPSLOTS={HANDS="hands"};CONTROL_SECONDARY="right"
ACTIONS={NW_CAST={code=123,mod_name="nw_test",invalid_hold_action=true,priority=10},WALKTO={},ATTACK={}}
RPC={RightClick=1}
GetTime=function() return 0 end
TheSim={GetPersistentString=function(_,_,cb) cb(false,"") end,
    SetPersistentString=function(_,_,_,_,cb) cb() end}
EntityScript={}
Vector3=function(x,y,z)
    return {x=x,y=y,z=z,Get=function(self) return self.x,self.y,self.z end,
        is_a=function(_,cls) return cls==Vector3 end}
end
OrderByPriority=function(a,b) return a.priority>b.priority end
CanEntitySeePoint=function() return true end;CanEntitySeeTarget=function() return true end
local ground=Vector3(4,0,-2)
local feet=Vector3(8,0,3)
local highlight={Flash=function() end}
local target={Transform={},components={highlight=highlight},replica={},IsValid=function() return true end,
    HasTag=function() return false end,is_a=function(_,cls) return cls==EntityScript end,
    GetPosition=function() return feet end}
TheInput={GetWorldPosition=function() return ground end,
    GetWorldEntityUnderMouse=function() return target end,
    GetHUDEntityUnderMouse=function() end,IsControlPressed=function() return true end}
local Direction=require("nw/cast_direction")
local A=require("nw/cast_action")
ACTIONS.NW_CAST.pre_action_cb=A.prepare
local plan={}
local landed
local wand={components={nw_wand={CanCast=function() return true,nil,plan end,
    Cast=function(_,_,pos) landed=pos;return true end}},
    IsValid=function() return true end,
    HasTag=function(_,tag) return tag=="allow_action_on_impassable" end,
    _nw_ready={value=function() return true end},_nw_cancast={value=function() return true end}}
local function player()
    return {components={},replica={inventory={GetEquippedItem=function() return wand end,GetActiveItem=function() end}},
        Transform={GetWorldPosition=function() return 0,0,0 end},
        IsValid=function() return true end,HasTag=function() return false end,
        GetBufferedAction=function() end}
end
BufferedAction=function(p,t,act,item,pos)
    return {doer=p,invobject=item,action=act,target=t,point=pos,rotation=0,options={},
        GetActionPoint=function(self) return self.point end,
        SetActionPoint=function(self,value) self.point=value end}
end
function wand:CollectActions(kind,owner,point,actions,right)
    if kind=="POINT" then A.point(self,owner,point,actions,right)
    elseif kind=="EQUIPPED" then A.equipped(self,owner,point,actions,right) end
end
local function controller(p,master)
    local c=setmetatable({inst=p,ismastersim=master,remote_controls={},
        UsingMouse=function() return true end,IsAOETargeting=function() return false end,
        IsControlPressed=function() return false end,
        IsEnabled=function() return true end,IsBusy=function() return false end,
        GetRightMouseAction=function(self) return self.act end,GetMapTarget=function() end,
        ClearActionHold=function() end,DoActionAutoEquip=function() end,
        EncodeControlMods=function() return 17 end,DecodeControlMods=function() end,ClearControlMods=function() end,
        CanLocomote=function() return true end,
        GetPlatformRelativePosition=function(_,x,z) return "boat",x-100,z-200 end}, {__index=PlayerController})
    p.components.playercontroller=c
    return c
end
local function picker(p)
    local pick=setmetatable({inst=p,map=TheWorld.Map,containers={},
        GetLeftClickActions=function() return {} end,
        GetSteeringActions=function() end,GetCannonAimActions=function() end,GetGolfAimActions=function() end,
        GetSceneActions=function() return {} end,GetPointSpecialActions=function() return {} end},
        {__index=PlayerActionPicker})
    p.components.playeractionpicker=pick
    A.install_picker(pick)
    return pick
end
SetClientRequestedAction=function() end;ClearClientRequestedAction=function() end
for _,path in ipairs({"host","predicted","unpredicted"}) do
    for _,mode in ipairs({"target","mouse"}) do
        TheWorld={ismastersim=path=="host",Map={IsPassableAtPoint=function() return true end}}
        Direction.set(mode)
        local p=player();ThePlayer=p
        local pc=controller(p,path=="host");pc.handler={}
        local pick=picker(p)
        Direction.receive(p,mode,true)
        local original=pc.DoAction
        pc.act=pick:GetRightClickActions(ground,target)[1]
        assert(pc.act and pc.DoAction==original and pc.OnRightClick==PlayerController.OnRightClick)
        -- Native entity sorting really discards the cursor position. Our supported
        -- picker callback must supply a point action only for mouse mode.
        assert(mode=="mouse" and pc.act:GetActionPoint()==ground and pc.act.target==nil
            or mode=="target" and pc.act:GetActionPoint()==nil and pc.act.target==target)
        if path~="unpredicted" then pc.locomotor={
            PushAction=function(_,a) A.prepare(a);assert(A.perform(a)) end,
            PreviewAction=function(_,a) A.prepare(a);assert(A.client_state(p,a)=="attack");a.preview_cb() end}
        end
        local packets={}
        SendRPCToServer=function(...) packets[#packets+1]={...} end
        pc:OnRightClick(true)
        if path~="host" then
            local packet=packets[#packets]
            assert(packet[2]==123 and packet[3]==-96 and packet[4]==-202)
            assert(packet[5]==target,"both modes must leave the native entity RPC unchanged")
            assert(packet[11]=="boat" and packet[12]==true)
            local remote=player();local server=controller(remote,true)
            picker(remote)
            Direction.receive(remote,mode,true)
            server.locomotor={PushAction=function(_,a) A.prepare(a);assert(A.perform(a)) end}
            -- The engine resolves platform-relative coordinates before the Lua RPC handler.
            TheWorld.ismastersim=true
            server:OnRemoteRightClick(packet[2],ground,packet[5],packet[6],packet[7],packet[8],packet[9],packet[10])
        end
        assert(landed==(mode=="target" and feet or ground),path.."/"..mode.." landed at wrong point")
    end
end
-- Server records, not the listen host's local setting, decide the same request.
TheWorld.ismastersim=true;Direction.set("target");ThePlayer=player()
local remote=player();local server=controller(remote,true);local pick=picker(remote)
Direction.receive(remote,"mouse",true)
server.locomotor={PushAction=function(_,a) A.prepare(a);assert(A.perform(a)) end}
server:OnRemoteRightClick(123,ground,target,0,false,17,nil,"nw_test")
assert(landed==ground)
Direction.receive(remote,"target",true)
server:OnRemoteRightClick(123,ground,target,0,false,17,nil,"nw_test")
assert(landed==feet)
-- Unrelated/native priorities, existing callbacks and action filters still work.
Direction.receive(remote,"mouse",true)
local blocker={{action={}}}
pick.rightclickoverride=function() return blocker,false end
A.install_picker(pick)
assert(pick:GetRightClickActions(ground,target)==blocker)
pick.rightclickoverride=nil;A.install_picker(pick)
local callback=pick.rightclickoverride;A.install_picker(pick);assert(pick.rightclickoverride==callback)
pick.actionfilter=function() return false end
assert(#pick:GetRightClickActions(ground,target)==0)
pick.actionfilter=nil;pick.GetSteeringActions=function() return blocker end
assert(pick:GetRightClickActions(ground,target)==blocker)
pick.GetSteeringActions=function() end
local oldinv=remote.replica.inventory
remote.replica.inventory={GetEquippedItem=function() end,GetActiveItem=function() end}
local actions,usedefault=pick.rightclickoverride(remote,target,ground)
assert(actions==nil and usedefault)
remote.replica.inventory=oldinv
assert(#pick:GetRightClickActions(Vector3(40,0,0),target)==0,"mouse mode validated entity instead of ground")
local oldfeet=feet;feet=Vector3(40,0,0)
assert(#pick:GetRightClickActions(ground,target)==1,"distant hovered tree blocked a valid ground shot")
feet=oldfeet
print("PASS unmodified native controller + real action picker: both coordinates sent, both modes, host/prediction paths, per-player authority, filters and priorities")
''')


if __name__ == '__main__':
    main()
