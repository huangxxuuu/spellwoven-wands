-- Exercise the local input adapter on both native click paths. The real SG
-- and server-side interrupted/successful launches are covered by smoke_input.
local Hold=require("nw/hold_cast")
local Direction=require("nw/cast_direction")
TheSim={SetPersistentString=function(_,_,_,_,cb) cb() end}
EQUIPSLOTS={HANDS="hands"}
ACTIONS={NW_CAST={},OTHER={}}
CONTROL_SECONDARY,CONTROL_PRIMARY="right","left"
CONTROL_MOVE_UP,CONTROL_MOVE_DOWN,CONTROL_MOVE_LEFT,CONTROL_MOVE_RIGHT="up","down","a","d"
local keys,now,ready,screen,hud_item={},0,true
TheInput={IsControlPressed=function(_,k) return keys[k] end,
    GetHUDEntityUnderMouse=function() return hud_item end}
TheNet={GetAveragePing=function() return 150 end}
TheFrontEnd={GetActiveScreen=function() return screen end}
GetTime=function() return now end
IsPaused=function() return false end
for _,master in ipairs({true,false}) do
for _,mode in ipairs({"target","mouse"}) do
    Direction.set(mode)
    keys,now,ready,hud_item={},0,true,nil
    TheWorld={ismastersim=master}
    local w={components={nw_wand={CanCast=function() return ready end}},IsValid=function() return true end,
        _nw_ready={value=function() return true end},_nw_cancast={value=function() return ready end}}
    local equipped,mouse=w,4
    local inv={GetActiveItem=function() end,GetEquippedItem=function() return equipped end}
    local tags,shots,releases,other={}, {},0,0
    local p={replica={inventory=inv},HUD={},Transform={GetWorldPosition=function() return 0,0,0 end},
        HasTag=function(_,tag) return tags[tag] end,IsActionsVisible=function() return true end,
        GetBufferedAction=function() end}
    ThePlayer=p;screen=p.HUD
    local pc={inst=p,handler={},ismastersim=master,
        IsEnabled=function() return true end,IsBusy=function() return false end,
        IsAOETargeting=function() return false end,UsingMouse=function() return true end,
        GetRightMouseAction=function(self) return self.act end}
    p.components={playercontroller=pc}
    Direction.receive(p,mode,true)
    TheInput.GetWorldPosition=function() return {x=mouse,z=0} end
    local tree={IsValid=function() return true end,GetPosition=function() return {x=40,z=0} end}
    function pc:OnUpdate()
        if not ready then self.act=nil;return end
        local point={x=mouse,z=0}
        self.act={action=self.other and ACTIONS.OTHER or ACTIONS.NW_CAST,invobject=w,doer=p,
            target=mode=="mouse" and tree or nil,
            GetActionPoint=function() return point end}
    end
    function pc:OnRightClick(down)
        if not down then releases=releases+1
        elseif self.act.action==ACTIONS.NW_CAST then shots[#shots+1]=self.act:GetActionPoint().x
        else other=other+1 end
    end
    Hold.install(pc)
    local function frame() now=now+1/30;pc:OnUpdate(1/30) end
    local function press() keys.right=true;pc:OnRightClick(true) end
    local function release() keys.right=nil;pc:OnRightClick(false) end
    frame();press();assert(#shots==1 and shots[1]==4)
    for i=1,9 do frame() end
    assert(#shots==1,"unconfirmed native click was sent twice")
    tags.attack=true;frame();tags.attack=nil;ready=false;frame()
    ready=true;keys.d=true;mouse=8;frame();assert(#shots==1)
    keys.d=nil;frame();assert(#shots==2 and shots[2]==8)
    release();frame();assert(releases==1 and #shots==2)
    keys.d=true;press();frame();assert(#shots==2)
    keys.d=nil;frame();assert(#shots==3)
    ready=false;frame();release();ready=true;frame();assert(#shots==3)
    ready=false;frame();press();frame();assert(#shots==3)
    ready=true;frame();assert(#shots==4)
    tags.attack=true;frame();tags.attack=nil;screen={};frame()
    screen=p.HUD;frame();assert(#shots==4);release()
    press();equipped=nil;frame();equipped=w;frame();assert(#shots==5);release()
    pc.other=true;frame();press();pc.other=false;frame();assert(other==1 and #shots==5);release()
    p._nw_hud_dragging={};frame();press()
    for i=1,45 do frame() end
    assert(#shots==5,"dragging a HUD panel must not cast, even outside its hitbox")
    p._nw_hud_dragging=nil;frame();assert(#shots==5,"ending drag must not rearm held casting")
    release();press();assert(#shots==6);release()
end
end
