-- Actual wire codec + local renderer. No native gameplay prefab is spawned.
local now,dedicated,created,removed,started,cancelled=100,false,0,0,0,0
local noop=function() end
GetTime=function() return now end
TheNet={IsDedicated=function() return dedicated end}
ANIM_ORIENTATION={OnGround=1}
local function events(e)
    e.events={}
    function e:ListenForEvent(name,fn)
        self.events[name]=self.events[name] or {}
        self.events[name][fn]=true
    end
    function e:RemoveEventCallback(name,fn)
        if self.events[name] then
            self.events[name][fn]=nil
            if not next(self.events[name]) then self.events[name]=nil end
        end
    end
    function e:PushEvent(name)
        local callbacks={}
        for fn in pairs(self.events[name] or {}) do callbacks[#callbacks+1]=fn end
        for _,fn in ipairs(callbacks) do fn(self) end
    end
    return e
end
TheWorld=events({})
function TheWorld:DoPeriodicTask(period,fn)
    assert(period==1/30 and not self.tick,"beam visuals share one scheduler")
    self.tick=fn;started=started+1
    return {Cancel=function() self.tick=nil;cancelled=cancelled+1 end}
end
CreateEntity=function()
    created=created+1
    local e={valid=true,entity={},Transform={},AnimState={},plays=0}
    for _,name in ipairs({"AddTransform","AddAnimState","SetCanSleep"}) do e.entity[name]=noop end
    e.entity.AddNetwork=function() error("beam spans must remain local") end
    e.entity.SetParent=function() error("confirmed paths must stay in world space") end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.SetRotation=function(_,rotation) e.rotation=rotation end
    e.AnimState.SetBank=function(_,value) e.bank=value end
    e.AnimState.SetBuild=function(_,value) e.build=value end
    e.AnimState.SetOrientation=function(_,value) e.orientation=value end
    for _,name in ipairs({"SetLightOverride","SetFinalOffset","SetBloomEffectHandle"}) do e.AnimState[name]=noop end
    e.AnimState.SetMultColour=function(_,r,g,b,a) e.colour={r,g,b,a} end
    e.AnimState.SetScale=function(_,x,y) e.sx,e.sy=x,y end
    e.AnimState.PlayAnimation=function(_,animation,loop) e.animation,e.loop=animation,loop;e.plays=e.plays+1 end
    e.AnimState.SetTime=function(_,time) e.time=time end
    e.AddTag=noop
    function e:IsValid() return self.valid end
    function e:Remove() assert(self.valid,"no double removal");self.valid=false;removed=removed+1 end
    return e
end
local function net(value)
    return {v=value,value=function(self) return self.v end,set=function(self,v) self.v=v end}
end
local function anchor(x,z)
    local inst=events({valid=true,x=x or 0,z=z or 0})
    inst._height=net(1.4);inst._beam_path=net("");inst._beam_ended=net(false)
    inst.Transform={GetWorldPosition=function() return inst.x,0,inst.z end}
    function inst:IsValid() return self.valid end
    function inst:Remove() self.valid=false;self:PushEvent("onremove") end
    return inst
end
local function near(a,b) assert(math.abs(a-b)<.00001,tostring(a).." ~= "..tostring(b)) end
local function tick(time)
    now=time
    if TheWorld.tick then TheWorld.tick(TheWorld) end
end
local function segment(id,x1,x2,born,radius,z1,z2)
    return {id=id,x1=x1,z1=z1 or 0,x2=x2,z2=z2 or 0,born=born,radius=radius or .12}
end
local Path=require("nw/beam_path")
local Beam=require("nw/beam_visual")
local old=segment(1,0,1,8.7)
local young=segment(2,1,2,9.8,.2)
local inst=anchor(2)
inst._beam_path:set(Path.encode({old,young},10))
local state=Beam.attach(inst)
assert(Beam.attach(inst)==state and created==2 and started==1)
assert(not state.tip and state.parts[1] and state.parts[2])
local first,second=state.parts[1],state.parts[2]
assert(first.fx.bank=="wagdrone_laserwire_fx" and first.fx.animation=="beam_straight" and first.fx.loop)
assert(first.fx.orientation==ANIM_ORIENTATION.OnGround and first.fx.colour[3]>first.fx.colour[1])
near(now-first.born,1.3) -- Unrelated server/client clocks; late join starts old.
near(first.fx.sx,.5);near(first.fx.sy,2*.12*Path.width(1.3)/(44/150))
near(first.fx.colour[4],Path.width(1.3));near(second.fx.colour[4],1)
near(second.fx.sy,2*.2/(44/150));near(first.fx.x,.5);near(first.fx.y,1.4)
local born=first.born
tick(100.1)
inst:PushEvent("nw_beamdirty") -- Same snapshot must not restore width or age.
near(first.born,born);near(first.fx.sx,.5)
near(first.fx.sy,2*.12*Path.width(1.4)/(44/150))
near(second.fx.sy,2*.2/(44/150))
assert(first.fx.plays==1 and created==2,"dirty replay must not restart the material")
tick(100.21)
assert(not state.parts[1] and not first.fx.valid and state.retired==1)
inst._beam_path:set(Path.encode({old,young},10.1))
inst:PushEvent("nw_beamdirty")
assert(not state.parts[1] and created==2,"retired IDs must not reappear from delayed snapshots")
near(second.born,99.8)

local newest=segment(3,2,3,10.08,.25)
inst.x=3;inst._beam_path:set(Path.encode({young,newest},10.11));inst:PushEvent("nw_beamdirty")
local third=state.parts[3]
assert(third and created==3 and not state.tip)
inst.x=3.8;tick(100.24)
local tip=state.tip
assert(tip and created==4 and #TheWorld._nw_beam_visuals.shots==1)
near(tip.fx.sx,.4);near(third.fx.sx,.5)
inst.x=4.3;tick(100.26)
assert(state.tip==tip);near(tip.fx.sx,.65)
inst._beam_ended:set(true);inst:PushEvent("nw_beamdirty")
assert(not state.tip and not tip.fx.valid and state.parts[2] and state.parts[3],"ending only removes the temporary front")
inst.x=6;tick(100.3)
assert(not state.tip and third.fx.valid and third.fx.sy>0,"confirmed path outlives the advancing head")

inst._beam_path:set(Path.encode({newest},10.2));inst:PushEvent("nw_beamdirty")
assert(not state.parts[2] and not second.fx.valid and state.parts[3],"omitted spans are reclaimed")
inst._beam_ended:set(false)
inst._beam_path:set(Path.encode({young},10.1));inst:PushEvent("nw_beamdirty")
assert(state.ended and state.parts[3] and not state.parts[2],"stale snapshot cannot roll back the path or reopen the head")
inst._height:set(2.1);inst:PushEvent("nw_projectiledirty")
near(third.fx.y,2.1)
inst:Remove()
assert(not inst._nw_beam_visual and not third.fx.valid and not TheWorld.tick and not TheWorld._nw_beam_visuals)
assert(not next(inst.events) and not next(TheWorld.events) and started==cancelled)

-- One temporary connector smooths ordinary replication gaps, never a jump
-- or a stale snapshot. It is excluded from the confirmed server path table.
now=200
local front=anchor(1)
front._beam_path:set(Path.encode({segment(1,0,1,19.95)},20))
local live=Beam.attach(front)
front.x=2;tick(200.05)
assert(live.tip and live.parts[1]);near(live.tip.length,1)
front.x=10;tick(200.06)
assert(not live.tip,"teleports must not draw a connector across the jump")
front.x=2;tick(200.4)
assert(not live.tip,"a missing snapshot must not leave a speculative connector")
front:PushEvent("nw_beamdirty")
assert(not live.tip,"duplicate snapshots must not renew front freshness")
front._beam_path:set(Path.encode({segment(2,1,2,20.49)},20.5));front:PushEvent("nw_beamdirty")
front.x=3;tick(200.41)
assert(live.tip and live.parts[2] and not live.parts[1])
local remaining=live.parts[2].fx
TheWorld:PushEvent("onremove")
assert(not front._nw_beam_visual and not remaining.valid and not TheWorld.tick and not next(TheWorld.events))

-- Empty, attached roots also detach during world shutdown, even with no task.
local empty=anchor()
empty._beam_path:set(Path.encode({},30))
assert(Beam.attach(empty) and not TheWorld.tick)
TheWorld:PushEvent("onremove")
assert(not empty._nw_beam_visual and not next(TheWorld.events))
assert(removed==created and started==cancelled)
dedicated=true
local before=created
local server=anchor()
server._beam_path:set(Path.encode({segment(1,0,1,29.9)},30))
assert(not Beam.attach(server));Beam.refresh(server)
assert(created==before and not server._nw_beam_visual and not TheWorld.tick,"dedicated server creates no local spans")
print("beam visual: native spans, age-monotonic snapshots, fixed length, narrowing width, bounded front, end/world cleanup and dedicated skip")
