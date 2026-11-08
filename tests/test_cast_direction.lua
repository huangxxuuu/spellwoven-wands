local Direction=require("nw/cast_direction")
local reads,writes={},{}
TheSim={GetPersistentString=function(_,key,cb)
        assert(key==Direction.key);reads[#reads+1]=cb
    end,
    SetPersistentString=function(_,key,value,encode,cb)
        assert(key==Direction.key and not encode);writes[#writes+1]={value=value,cb=cb}
    end}
assert(Direction.get()=="target")
local restored
Direction.load(function(value) restored=value end)
Direction.load()
assert(#reads==1)
assert(not Direction.set("invalid") and Direction.get()=="target" and #writes==0)
Direction.set("mouse");Direction.set("target");Direction.set("mouse")
reads[1](true,"target")
assert(restored=="mouse","late load overwrote a live choice")
assert(#writes==1 and writes[1].value=="mouse")
writes[1].cb();assert(#writes==2 and writes[2].value=="mouse");writes[2].cb()
package.loaded["nw/cast_direction"]=nil
Direction=require("nw/cast_direction")
Direction.load();reads[2](true,"mouse")
assert(Direction.get()=="mouse","preference lost on restart")
package.loaded["nw/cast_direction"]=nil
Direction=require("nw/cast_direction")
Direction.load();reads[3](true,"broken preference")
assert(Direction.get()=="target","corrupt preference must use the default")
TheSim.SetPersistentString=function(_,_,_,_,cb) cb() end

EQUIPSLOTS={HANDS="hands"};CONTROL_SECONDARY="right"
ACTIONS={NW_CAST={code=123,mod_name="nw_test"},OTHER={}}
RPC={RightClick=9}
local ground={x=4,z=-2}
TheInput={GetWorldPosition=function() return ground end,IsControlPressed=function() return true end}
GetTime=function() return 0 end
TheWorld={ismastersim=true,Map={IsPassableAtPoint=function(_,x) return x~=5 end}}
local plan={}
local result
local wand={components={nw_wand={CanCast=function() return true,nil,plan end,
    Cast=function(_,_,pos) result=pos;return true end}},
    _nw_ready={value=function() return true end},_nw_cancast={value=function() return true end}}
local inv={GetEquippedItem=function() return wand end,GetActiveItem=function() end}
local p={components={},replica={inventory=inv},Transform={GetWorldPosition=function() return 0,0,0 end},
    HasTag=function() return false end}
local targetpos={x=8,z=3}
local target={Transform={},IsValid=function() return true end,GetPosition=function() return targetpos end}
local A=require("nw/cast_action")
local function action()
    local a={action=ACTIONS.NW_CAST,doer=p,invobject=wand,target=target,point=ground,rotation=0}
    function a:GetActionPoint() return self.point end
    function a:SetActionPoint(value) self.point=value end
    return a
end
ThePlayer=p;p.components.playercontroller={UsingMouse=function() return true end}
-- Server authority is the per-player record, never the host's saved preference.
Direction.set("mouse")
assert(not Direction.uses_mouse(p))
local a=action();A.prepare(a);assert(a._nw_aim_target==target and A.perform(a) and result==targetpos)
assert(Direction.receive(p,"mouse",true) and Direction.uses_mouse(p))
a=action();A.prepare(a)
assert(a.target==nil and a._nw_aim_target==nil and A.perform(a) and result==ground)
local original=ground;ground={x=80,z=0}
assert(A.aim_point(a)==original,"already submitted shot changed with the cursor")
ground=original
Direction.set("target");assert(Direction.uses_mouse(p),"server must use the received preference")
local other={components={}}
assert(Direction.receive(other,"target",true) and not Direction.uses_mouse(other) and Direction.uses_mouse(p))
assert(not Direction.receive(p,"invalid",true) and not Direction.receive(p,"target","true"))
assert(Direction.uses_mouse(p),"invalid RPC changed the preference")
Direction.receive(p,"mouse",false);assert(not Direction.uses_mouse(p),"gamepad mode should select targets")
Direction.receive(p,"mouse",true)
-- Lock each accepted shot's mode; a later sync must not retarget it.
a=action();A.prepare(a);Direction.receive(p,"target",true)
assert(A.perform(a) and result==ground)
a=action();A.prepare(a);Direction.receive(p,"mouse",true)
assert(A.perform(a) and result==targetpos)
-- Never substitute the entity position if mouse mode lacks a valid ground point.
a=action();a.point=nil;A.prepare(a);assert(not A.perform(a))
a=action();a.point={x=0/0,z=0};A.prepare(a);assert(not A.perform(a))
TheWorld.ismastersim=false;Direction.set("mouse")
assert(Direction.uses_mouse(p) and not Direction.uses_mouse(other))
assert(A.client_state(p,action())=="attack")
p.components.playercontroller.UsingMouse=function() return false end
assert(not Direction.uses_mouse(p) and A.aim_point(action())==targetpos)
print("cast direction: local persistence/races, server authority, per-player records, invalid RPCs/points, locked shots and gamepad fallback")
