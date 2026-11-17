local Mode=require("nw/cast_mode")
Mode.enabled=function() return true end
Mode.ready=function() return true end
local Pose=require("nw/hold_pose")
local pose_wand,pose_point
Pose.update=function(_,wand,point) pose_wand,pose_point=wand,point end
local Hold=require("nw/hold_cast")
local Cast=require("nw/cast_action")
EQUIPSLOTS={HANDS="hands"}
ACTIONS={NW_CAST={},OTHER={}}
CONTROL_SECONDARY,CONTROL_PRIMARY="right","left"
CONTROL_MOVE_UP,CONTROL_MOVE_DOWN,CONTROL_MOVE_LEFT,CONTROL_MOVE_RIGHT="up","down","a","d"
local tick,keys,ready=0,{},true
GetTick=function() return tick end
GetTime=function() return tick/30 end
IsPaused=function() return false end
TheWorld={ismastersim=false}
local hud,screen={},nil
TheFrontEnd={GetActiveScreen=function() return screen end}
local hud_item
TheInput={IsControlPressed=function(_,key) return keys[key] end,
    IsMouseDown=function(_,button) return button==1001 and keys.right end,
    GetHUDEntityUnderMouse=function() return hud_item end,
    GetWorldPosition=function() return {x=7,z=0} end}
local valid=true
local w={components={},IsValid=function() return valid end,HasTag=function(_,tag) return tag=="nw_wand" end,
    _nw_ready={value=function() return true end},_nw_cancast={value=function() return ready end}}
local equipped=w
local inv={GetEquippedItem=function() return equipped end,GetActiveItem=function() end}
local tags,buffered={},nil
local p={components={},replica={inventory=inv},HUD=hud,Transform={GetWorldPosition=function() return 0,0,0 end},
    IsValid=function() return true end,HasTag=function(_,tag) return tags[tag] end,
    GetBufferedAction=function() return buffered end,IsActionsVisible=function() return true end}
ThePlayer=p;screen=hud
local busy,requests,releases,other=false,0,0,0
local pc={inst=p,handler={},ismastersim=false,
    UsingMouse=function() return true end,IsEnabled=function() return true end,
    IsBusy=function() return busy end,IsAOETargeting=function() return false end,
    GetRightMouseAction=function(self) return self.act end}
p.components.playercontroller=pc
Cast.input_action=function() return pc.act end -- picker is covered by native integration
function pc:OnUpdate()
    local pos={x=4,z=0}
    self.act={action=self.other and ACTIONS.OTHER or ACTIONS.NW_CAST,invobject=w,doer=p,
        GetActionPoint=function() return pos end}
end
function pc:OnRightClick(down)
    if not down then releases=releases+1
    elseif self.act.action==ACTIONS.NW_CAST then requests=requests+1
    else other=other+1 end
end
Hold.install(pc)
local function frame() tick=tick+1;pc:OnUpdate(1/30) end
local function press() keys.right=true;pc:_nw_cast_key_event(true) end
local function release() keys.right=nil;pc:_nw_cast_key_event(false) end
frame();press();assert(requests==1 and pose_wand==w and pose_point.x==4)
pc:OnUpdate(0);release();press();assert(requests==1,"same-tick re-press must not duplicate a request")
for i=1,30 do frame() end
assert(requests==31,"zero cooldown must not wait for an attack tag or one-second retry")
ready=false
for i=1,3 do frame() end
assert(requests==34,"stale replicated readiness must not pace instant requests")
assert(pose_wand==w,"cooldown must not lower the wand")
keys.d=true;frame();assert(requests==34 and pose_wand==nil)
keys.d=nil;frame();assert(requests==35 and pose_wand==w)
busy=true;frame();busy=false
tags.attack=true;frame();tags.attack=nil
buffered={};frame();buffered=nil
pc.locomotor={bufferedaction={}};frame();pc.locomotor=nil
assert(requests==35,"movement, busy or pending actions must pause repeated requests")
assert(pose_wand==nil,"pending actions must take priority over the pose")
frame();assert(requests==36)
release();for i=1,3 do frame() end
assert(requests==36,"release must stop repeats even when readiness later changes")
assert(pose_wand==nil,"release must lower the wand")
ready=true;frame();assert(requests==36)
press();assert(requests==37)
screen={};frame();screen=hud;frame();assert(requests==37,"leaving the HUD must disarm held casting")
assert(pose_wand==nil)
release();frame();press();assert(requests==38)
equipped=nil;frame();equipped=w;frame();assert(requests==38,"re-equipping must not restore a cancelled hold")
assert(pose_wand==nil)
release();frame();press();assert(requests==39)
p._nw_editing=true;frame();p._nw_editing=nil;frame();assert(requests==39)
release();frame();pc.other=true;pc:OnUpdate(0);press()
assert(other==1 and requests==39,"unrelated right-click actions must keep their native path")
release();pc.other=false;frame()
p._nw_hud_dragging={};press();frame();p._nw_hud_dragging=nil;frame()
assert(requests==39,"ending a HUD drag must not arm instant casting")
release();frame();press();assert(requests==40)
valid=false;frame();valid=true;frame();assert(requests==40)
assert(pose_wand==nil)
release();frame()
-- No right-click candidate exists when an unready wand has no legal cast.
pc.act=nil;press()
assert(requests==40 and pose_wand==w and pose_point.x==7,
    "pressing an empty wand must still start the pose toward the cursor")
release();assert(pose_wand==nil)
assert(releases>0)
print("instant hold: frame-bounded native requests, stale readiness, release/movement/UI/equipment cancellation")
