-- Exercise the installed SG/RPC callbacks, including delayed and reordered RPCs.
local Pose=require("nw/hold_pose")
local Mode=require("nw/cast_mode")
local enabled=true
Mode.enabled=function() return enabled end
EQUIPSLOTS={HANDS="hands"}
ACTIONS={NW_CAST={}}
local now=0
GetTime=function() return now end
local state,receive,postinit
local sent={}
local G={TheWorld={ismastersim=true},GetTime=GetTime,EQUIPSLOTS=EQUIPSLOTS,
    State=function(value) return value end,MOD_RPC={nw_weave={hold_pose="pose_rpc"}},
    SendModRPCToServer=function(...) sent[#sent+1]={...} end}
TheWorld=G.TheWorld
Pose.install({
    AddModRPCHandler=function(_,name,fn) assert(name=="hold_pose");receive=fn end,
    AddStategraphState=function(name,value) assert(name=="wilson");state=value end,
    AddPlayerPostInit=function(fn) postinit=fn end,
},G)

local function player()
    local p={components={},tags={},events={},tasks={},plays={},faces={},valid=true}
    local wand={components={nw_wand={CanCast=function() error("pose must not query mana or cast readiness") end}},
        IsValid=function(self) return self.valid~=false end}
    p.wand,p.equipped=wand,wand
    p.components.inventory={GetEquippedItem=function() return p.equipped end,
        GetActiveItem=function() return p.activeitem end}
    p.components.combat={InCooldown=function() error("combat cooldown must not gate a pose") end}
    p.components.locomotor={WantsToMoveForward=function() return p.moving end,
        HasDestination=function() return p.destination end,
        FaceMovePoint=function(_,x,y,z) p.faces[#p.faces+1]={x,y,z} end}
    p.components.playercontroller={inst=p,IsEnabled=function() return not p.disabled end,
        IsBusy=function() return p.busy end}
    p.components.rider={IsRiding=function() return p.riding end}
    p.Transform={GetWorldPosition=function() return 0,0,0 end}
    p.AnimState={PlayAnimation=function(_,name)
            p.plays[#p.plays+1]=name;p.animation=name;p.animframe=0
        end,
        PushAnimation=function(_,name,loop) p.loop,p.looping=name,loop end,
        AnimDone=function() return p.animdone end,
        IsCurrentAnimation=function(_,name) return p.animation==name end,
        GetCurrentAnimationNumFrames=function()
            return (p.animation=="nw_hold_cast_pre" or p.animation=="nw_hold_cast_pst") and 11 or 36
        end,
        GetCurrentAnimationFrame=function() return p.animframe end,
        SetFrame=function(_,frame) p.animframe=frame end}
    p.sg={currentstate={name="idle"},statemem={},enters=0}
    function p.sg:HasStateTag(tag)
        if self.currentstate.name==state.name then
            for _,value in ipairs(state.tags) do if tag==value then return true end end
        end
        return p.statetags and p.statetags[tag] or false
    end
    function p.sg:GoToState(name)
        if self.currentstate.name==state.name then state.onexit(p) end
        self.currentstate={name=name};self.statemem={};self.enters=self.enters+1
        if name==state.name then state.onenter(p) end
    end
    function p:IsValid() return self.valid end
    function p:HasTag(tag) return self.tags[tag] end
    function p:GetBufferedAction() return self.buffered end
    function p:ClearBufferedAction() error("pose must preserve native buffered actions") end
    function p:DoTaskInTime(delay,fn)
        local task={at=now+delay,fn=fn,Cancel=function(self) self.cancelled=true end}
        self.tasks[#self.tasks+1]=task
        return task
    end
    function p:ListenForEvent(event,fn) self.events[event]=fn end
    function p:event(event,data) if self.events[event] then self.events[event](self,data) end end
    postinit(p)
    return p
end
local function active(p) return p.sg.currentstate.name==state.name and not p.sg.statemem.releasing end
local function update(p) state.onupdate(p) end
local function lastplay(p) return p.plays[#p.plays] end
local function start(p,serial,x,z) receive(p,1,serial or 1,p.wand,x or 8,z or 3) end
local function expire(p)
    local task=p._nw_pose_hold.task
    now=task.at;task.fn()
end

local p=player()
start(p)
assert(active(p) and p.sg:HasStateTag("idle") and p.sg:HasStateTag("canrotate"))
assert(not p.sg:HasStateTag("busy") and not p.sg:HasStateTag("attack"))
assert(lastplay(p)=="nw_hold_cast_pre" and p.loop=="nw_hold_cast_loop" and p.looping)
assert(p.faces[1][1]==8 and p.faces[1][3]==3)
local lease=p._nw_pose_hold.task
now=now+.25;start(p,2,5,6)
assert(lease.cancelled and p.sg.enters==1 and #p.plays==1,"heartbeat must preserve the running loop")
lease.fn()
assert(active(p),"a cancelled old lease must not expire its replacement")
expire(p)
assert(not p._nw_pose_hold and p.sg.statemem.releasing and lastplay(p)=="nw_hold_cast_pst")
update(p);assert(p.sg.currentstate.name==state.name,"post animation must finish before returning idle")
start(p,3)
assert(active(p) and lastplay(p)=="nw_hold_cast_pre","renewed input can recover after a lost heartbeat")
receive(p,0,4)
p.animdone=true;p.buffered={action="chop"}
update(p)
assert(p.sg.currentstate.name==state.name and p.buffered.action=="chop",
    "finishing the pose must not consume an incoming native action")
p.buffered=nil;update(p)
assert(p.sg.currentstate.name=="idle")

-- The extend and retract clips are reverses: rapid input changes must switch
-- at the matching pose rather than jumping to either end of the animation.
p=player();start(p);p.animframe=3
receive(p,0,2)
assert(lastplay(p)=="nw_hold_cast_pst" and p.animframe==7,
    "releasing partway through extension must retract from the current pose")
p.animframe=4;start(p,3)
assert(active(p) and lastplay(p)=="nw_hold_cast_pre" and p.animframe==6,
    "pressing during retraction must extend from the current pose")

-- Actual successful casts drive bounded recoil; empty/cooling held input has
-- no impulse. Finish pre explicitly because this fixture has no AnimState clock.
local function finish_pre(v)
    v.animation="nw_hold_cast_loop";v.animframe=0;update(v)
end
local function shot(v) v._nw_pose_on_cast(v,v.wand) end
p=player();start(p);shot(p)
local first_recoil=p.sg.statemem.recoil
assert(first_recoil>0 and #p.plays==1,"first shot must not restart or skip extension")
now=now+.4;update(p)
assert(p.sg.statemem.recoil==first_recoil and #p.plays==1)
finish_pre(p)
assert(lastplay(p)=="nw_hold_cast_recoil_05" and p.sg.enters==1)
local plays=#p.plays
update(p);assert(#p.plays==plays,"unchanged recoil level must not restart its clip")
p.animframe=23
p.buffered={action=ACTIONS.NW_CAST,invobject=p.wand}
shot(p)
assert(p.sg.statemem.recoil>first_recoil,"current successful cast's native buffer is allowed")
assert(p.animframe==23,"a new recoil level must preserve the running body cycle")
p.buffered=nil
for i=1,50 do shot(p) end
assert(p.sg.statemem.recoil==1 and lastplay(p)=="nw_hold_cast_recoil_12",
    "rapid continuous firing must saturate at the maximum small recoil pose")
p.animframe=35;plays=#p.plays;shot(p)
assert(p.animframe==35 and #p.plays==plays,"saturated recoil must keep animating, without restarting the cycle")
now=now+.2;update(p)
assert(math.abs(p.sg.statemem.recoil-.5)<.000001 and lastplay(p)=="nw_hold_cast_recoil_06")
assert(p.animframe==35,"decay changes intensity at the same cycle frame")
now=now+.2;update(p)
assert(p.sg.statemem.recoil<.000001 and active(p) and lastplay(p)=="nw_hold_cast_loop",
    "stopped fire returns to stable aim without releasing held input")
assert(p.animframe==35,"the neutral loop must inherit the recoil cycle frame")
plays=#p.plays;now=now+.1;start(p,2);update(p)
assert(#p.plays==plays,"cooldown/mana hold heartbeats must not produce recoil")
shot(p);local single=p.sg.statemem.recoil
now=now+1/30;shot(p)
assert(p.sg.statemem.recoil>single,"higher fire rate accumulates more recoil")
now=now+.3;update(p);shot(p)
assert(math.abs(p.sg.statemem.recoil-single)<.000001,"slow shots reset to the single-shot kick")

-- Release smoothly settles recoil; repressing while settling preserves pose.
receive(p,0,3)
assert(p.sg.statemem.releasing and not p.sg.statemem.post)
local before,enters=p.sg.statemem.recoil,p.sg.enters
now=now+.02;update(p)
assert(p.sg.statemem.recoil<before and not p.sg.statemem.post)
start(p,4)
assert(active(p) and p.sg.enters==enters and p.sg.statemem.recoil>0,
    "repress during recoil return must not jump back to extension")
receive(p,0,5);now=now+.1;update(p)
assert(p.sg.statemem.post and lastplay(p)=="nw_hold_cast_pst")
p.animframe=4;start(p,6)
assert(active(p) and p.animframe==6 and lastplay(p)=="nw_hold_cast_pre")

-- Success notifications cannot resurrect released input or steal other states.
p=player();start(p);finish_pre(p);receive(p,0,2)
plays=#p.plays;shot(p);assert(#p.plays==plays and p.sg.statemem.releasing)
p.sg:GoToState("hit");shot(p);assert(p.sg.currentstate.name=="hit" and #p.plays==plays)
p=player();start(p);finish_pre(p);p._nw_pose_on_cast(p,player().wand)
assert(p.sg.statemem.recoil==0,"foreign wand success cannot drive the held wand")
for _,block in ipairs({
    function(v) v.moving=true end,
    function(v) v.tags.frozen=true end,
    function(v) v.equipped=nil end,
    function(v) v.buffered={action="chop"} end,
}) do
    p=player();start(p);finish_pre(p);block(p);shot(p)
    assert(p.sg.statemem.recoil==0,"invalid live state suppresses the shot impulse")
end
for _,event in ipairs({"attacked","death","unequip"}) do
    p=player();start(p);finish_pre(p);shot(p)
    p:event(event,{eslot="hands"})
    assert(p.sg.statemem.post and lastplay(p)=="nw_hold_cast_pst",
        "interruptions must not wait for recoil to settle")
end
p=player();start(p);finish_pre(p);shot(p);receive(p,0,2);p.moving=true;update(p)
assert(p.sg.statemem.post,"movement during release must bypass remaining recoil")

-- Release ordering, duplicates, and sequence wrap must not resurrect a hold.
p=player();start(p,10);receive(p,0,12)
local enters,plays=p.sg.enters,#p.plays
start(p,11);start(p,12)
assert(p.sg.enters==enters and #p.plays==plays and not p._nw_pose_hold)
start(p,13);assert(active(p))
receive(p,0,12);assert(active(p),"an old release must not cancel newer held input")
p=player();start(p,2147483646);start(p,2147483647);start(p,1)
assert(active(p) and p._nw_pose_serial==1)
receive(p,0,2147483647);assert(active(p),"pre-wrap release is stale after wrap")
receive(p,0,2);assert(p.sg.statemem.releasing)

-- Reject malformed or foreign requests before any gameplay state transition.
for _,serial in ipairs({0,-1,1.5,2147483648,math.huge,0/0}) do
    p=player();start(p,serial);assert(p.sg.enters==0 and not p._nw_pose_hold)
end
p=player();receive(p,2,1,p.wand,2,3);assert(p.sg.enters==0)
receive(p,1,2,p.wand,math.huge,3);assert(p.sg.enters==0)
receive(p,1,3,p.wand,2,nil);assert(p.sg.enters==0)
receive(p,1,4,player().wand,2,3);assert(p.sg.enters==0)
p.valid=false;start(p,5);assert(p.sg.enters==0)
p=player();receive(p,1,1,p.wand,0,0)
assert(active(p) and #p.faces==0,"zero aim direction must not rotate the player")

-- Native movement, controller/UI state, equipment and mount eligibility.
local blockers={
    function(v) v.moving=true end,
    function(v) v.destination=true end,
    function(v) v.buffered={action="walk"} end,
    function(v) v.components.locomotor.bufferedaction={action="walk"} end,
    function(v) v.disabled=true end,
    function(v) v.busy=true end,
    function(v) v.activeitem={} end,
    function(v) v._nw_editing=true end,
    function(v) v._nw_edit_until=now+1 end,
    function(v) v.riding=true end,
    function(v) v.equipped=nil end,
    function(v) v.wand.valid=false end,
}
for _,tag in ipairs({"busy","attack","moving","sleeping","frozen","dead","nointerrupt","playerghost"}) do
    local blockedtag=tag
    blockers[#blockers+1]=function(v) v.tags[blockedtag]=true end
    blockers[#blockers+1]=function(v) v.statetags={[blockedtag]=true} end
end
for _,block in ipairs(blockers) do
    p=player();block(p);start(p);assert(not active(p),"ineligible player must not start a pose")
    p=player();start(p);block(p);update(p)
    assert(p.sg.statemem.releasing and not p._nw_pose_hold,"eligibility loss must release an existing pose")
end
p=player();p.sg:GoToState("chop");start(p)
assert(p.sg.currentstate.name=="chop" and #p.plays==0,"request must not interrupt another native state")
for _,name in ipairs({"idle","funnyidle","wes_funnyidle","wx78_funnyidle","waxwell_funnyidle"}) do
    p=player();p.sg.currentstate.name=name;start(p)
    assert(active(p),name.." must yield directly to the hold pose")
end
for _,name in ipairs({"chop","mine","emote","hiding","mounted","hit","frozen","unknown_idle"}) do
    p=player();p.sg.currentstate.name=name;p.statetags={idle=true};start(p)
    assert(p.sg.currentstate.name==name and #p.plays==0,name.." must not be stolen even with an idle tag")
    assert(not p._nw_pose_ensure(p,p.wand),"server action uses the same natural idle boundary")
end
p=player();start(p);local task=p._nw_pose_hold.task;p.sg:GoToState("hit")
assert(task.cancelled and not p._nw_pose_hold)
receive(p,0,2);assert(p.sg.currentstate.name=="hit" and #p.plays==1,
    "late release must not steal a state entered after the pose")
for _,event in ipairs({"attacked","death","playerdeactivated"}) do
    p=player();start(p);p:event(event)
    assert(p.sg.statemem.releasing and not p._nw_pose_hold,event.." must release the pose")
end
p=player();start(p);p:event("unequip",{eslot="body"});assert(active(p))
p:event("unequip",{eslot="hands"});assert(not p._nw_pose_hold)
p=player();start(p);task=p._nw_pose_hold.task;p:event("onremove")
assert(task.cancelled and not p._nw_pose_hold)

-- Full action -> pose -> Cast order, without any hold RPC. Never pass through
-- native idle.onenter (which would clear this NW_CAST buffered action).
local Cast=require("nw/cast_action")
Mode.ready=function() return true end
local tick=100
GetTick=function() return tick end
local function perform(v,can_cast)
    tick=tick+1
    v.components.combat.InCooldown=function() return false end
    local plan={}
    v.wand.components.nw_wand.CanCast=function() return can_cast~=false,nil,plan end
    v.wand.components.nw_wand.Cast=function()
        assert(v.riding or (active(v) and v._nw_pose_hold),"server pose must exist before the first shot")
        assert(v.buffered and v.buffered.action==ACTIONS.NW_CAST,"entry must preserve the native action")
        v.casts=(v.casts or 0)+1
        return true
    end
    local act={doer=v,invobject=v.wand,action=ACTIONS.NW_CAST,
        GetActionPoint=function() return {x=8,z=3} end}
    v.buffered=act
    local ok=Cast.perform(act)
    v.buffered=nil
    return ok
end
for _,name in ipairs({"idle","funnyidle","wes_funnyidle","wx78_funnyidle","waxwell_funnyidle"}) do
    p=player();p.sg.currentstate.name=name
    assert(perform(p) and p.casts==1 and p.sg.enters==1)
    assert(p._nw_pose_serial==nil and p._nw_pose_hold.transient and p.sg.statemem.recoil>0)
    finish_pre(p)
    assert(p.sg.statemem.releasing and not p._nw_pose_hold and not p.sg.statemem.post,
        "action-only click shows recoil then releases without input RPCs")
    now=now+.1;update(p);p.animdone=true;update(p)
    assert(p.sg.currentstate.name=="idle","action-only click must finish retracting automatically")
end
p=player();assert(perform(p));receive(p,0,2)
assert(p.sg.statemem.releasing and not p.sg.statemem.post,
    "a release beating hold must preserve the transient shot's recoil")
finish_pre(p)
assert(lastplay(p)=="nw_hold_cast_recoil_05")
start(p,1);assert(p.sg.statemem.releasing,"late hold older than release cannot resurrect a click")
start(p,3);assert(active(p) and not p._nw_pose_hold.transient,"new held input may adopt the transient pose")
p=player();assert(perform(p));start(p,1)
assert(not p._nw_pose_hold.transient,"a later first hold RPC adopts the action-started pose")
finish_pre(p);assert(active(p),"adopted hold must retain the usual heartbeat lease")
p=player();assert(not perform(p,false) and active(p) and p.sg.statemem.recoil==0,
    "an empty/cooling action can pose but cannot kick")
finish_pre(p);assert(p.sg.statemem.post and not p._nw_pose_hold)
for _,name in ipairs({"mounted_idle","graze","graze_empty","bellow","shake","shake_woby","alert_woby","bark_woby"}) do
    p=player();p.riding=true;p.sg.currentstate.name=name
    assert(perform(p) and p.sg.currentstate.name==name and #p.plays==0,
        "mounted natural idles retain their existing instant route without a hold pose")
    p=player();p.sg.currentstate.name=name
    assert(not perform(p) and #p.plays==0,"mounted states cannot grant on-foot instant casts")
end
for _,block in ipairs(blockers) do
    p=player();block(p)
    if not p.riding then
        local before=p.sg.enters
        -- Existing native buffered actions are checked independently of our
        -- action fixture, which deliberately owns the NW_CAST buffer.
        assert(not p._nw_pose_ensure(p,p.wand) and p.sg.enters==before)
    end
end

-- Remote clients send bounded RPCs and never enter a predicted local SG pose.
G.TheWorld.ismastersim=false
p=player();G.ThePlayer=p
assert(p._nw_pose_on_cast==nil,"remote clients do not synthesize shot recoil")
assert(p._nw_pose_ensure==nil,"remote clients do not enter an authoritative cast pose")
local pc=p.components.playercontroller
Pose.update(pc,nil);assert(#sent==0)
Pose.update(pc,p.wand,{x=7,z=9})
assert(#sent==1 and sent[1][1]=="pose_rpc" and sent[1][2]==1 and sent[1][3]==1)
assert(sent[1][4]==p.wand and sent[1][5]==7 and sent[1][6]==9 and p.sg.enters==0)
now=now+.24;Pose.update(pc,p.wand,{x=4,z=5});assert(#sent==1)
now=pc._nw_pose_input.next_send;Pose.update(pc,p.wand,{x=4,z=5});assert(#sent==2 and sent[2][5]==4)
Pose.update(pc,nil);assert(#sent==3 and sent[3][2]==0,"release bypasses the heartbeat interval")
Pose.update(pc,nil);assert(#sent==3,"idle input must not spam releases")
pc._nw_pose_input.serial=2147483647
Pose.update(pc,p.wand,{x=0/0,z=1});assert(sent[4][3]==1 and sent[4][5]==nil and sent[4][6]==nil)
p:event("playerdeactivated");assert(#sent==5 and sent[5][2]==0)
receive(p,1,20,p.wand,1,2);assert(p.sg.enters==0,"client RPC handler must not mutate local state")

-- Host uses the same lease and turn path without sending an RPC.
G.TheWorld.ismastersim=true
p=player();Pose.update(p.components.playercontroller,p.wand,{x=6,z=2})
assert(active(p) and #sent==5 and p.faces[1][1]==6)
enabled=false;Pose.update(p.components.playercontroller,p.wand,{x=6,z=2})
assert(p.sg.statemem.releasing and not p._nw_pose_hold)
print("hold pose: server SG lease, sequence ordering/wrap, interruption, client RPC pacing and host recovery")
