-- Actual wire codec + local renderer. No native gameplay prefab is spawned.
local now,dedicated,created,removed,started,cancelled=100,false,0,0,0,0
local dark_start=math.huge
local light_samples=0
TUNING={DARK_CUTOFF=0}
TheSim={GetLightAtPoint=function(_,x,y,z,cutoff)
    light_samples=light_samples+1
    assert(y==1.4 or y==2.1,"sample the placed art, including its visual height")
    return x>=dark_start and 0 or .05
end}
ThePlayer={IsValid=function() return true end,components={playervision={HasNightVision=function() return false end}}}
TheCamera={heading=-90,pitch=35}
local noop=function() end
GetTime=function() return now end
TheNet={IsDedicated=function() return dedicated end}
ANIM_ORIENTATION={OnGround=1,BillBoard=2}
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
    local e={valid=true,entity={},Transform={},AnimState={},plays=0,rotation=0,tags={}}
    for _,name in ipairs({"AddTransform","SetCanSleep"}) do e.entity[name]=noop end
    e.entity.AddAnimState=function() assert(e.tags[1]=="can_offset_sort_pos","sorting capability must be the first tag before AnimState") end
    e.entity.AddNetwork=function() error("beam spans must remain local") end
    e.entity.SetParent=function() error("confirmed paths must stay in world space") end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.GetWorldPosition=function() return e.x or 0,e.y or 0,e.z or 0 end
    e.Transform.SetRotation=function(_,rotation) e.rotation=rotation end
    e.AnimState.SetBank=function(_,value) e.bank=value end
    e.AnimState.SetBuild=function(_,value) e.build=value end
    e.AnimState.SetOrientation=function(_,value) e.orientation=value end
    e.AnimState.SetFinalOffset=function(_,value) e.finaloffset=value end
    e.AnimState.SetSortWorldOffset=function(_,x,y,z) e.sortoffset={x,y,z} end
    e.AnimState.SetDeltaTimeMultiplier=function(_,rate) e.rate=rate end
    e.AnimState.SetLightOverride=function(_,value) e.light=value end
    e.AnimState.SetBloomEffectHandle=function(_,value) e.bloom=value end
    e.AnimState.ClearBloomEffectHandle=function() e.bloom=nil end
    e.AnimState.SetMultColour=function(_,r,g,b,a) e.colour={r,g,b,a} end
    e.AnimState.SetScale=function(_,x,y) e.sx,e.sy=x,y end
    e.AnimState.PlayAnimation=function(_,animation,loop) e.animation,e.loop=animation,loop;e.plays=e.plays+1 end
    e.AnimState.SetTime=function(_,time) e.time=time;e.timeset=now end
    e.AddTag=function(_,tag) e.tags[#e.tags+1]=tag end
    function e:Show() self.hidden=false end
    function e:Hide() self.hidden=true end
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
local function phase(fx) return (fx.time+now-fx.timeset)%(16/30) end
local function leading(fx)
    local slices=fx._nw_beam_slices
    local last=slices and slices[#slices] or fx
    return last.x+last.sx/16,last.z -- horizontal sixteenth's leading edge
end
local function centre(fx)
    local slices=fx._nw_beam_slices
    return slices and (slices[8].x+slices[9].x)*.5 or fx.x
end
local function core_scale(fx)
    -- Interior centres measure the visible path independently of extra quad
    -- coverage at a bend. Preserve the old whole-span scale assertions.
    local slices=fx._nw_beam_slices
    local a,b=slices[8],slices[9]
    return math.sqrt((b.x-a.x)^2+(b.z-a.z)^2)*16/2
end
local function edge(fx,sign)
    local a=-math.rad(fx.rotation)
    return fx.x+sign*fx.sx/16*math.cos(a),fx.z+sign*fx.sx/16*math.sin(a)
end
local function same_phase(a,b)
    local distance=math.abs(phase(a)-phase(b))
    assert(math.min(distance,16/30-distance)<.00001,"adjacent material slices must share a flowing frame")
end
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
assert(Beam.attach(inst)==state and created==34 and started==1)
assert(not state.tip and state.head and state.parts[1] and state.parts[2])
local first,second=state.parts[1],state.parts[2]
assert(first.fx.bank=="nw_end_beam" and first.fx.build=="nw_end_beam" and first.fx.animation=="beam_0_part_0" and first.fx.loop)
assert(second.fx.animation=="beam_1_part_0" and first.fx.orientation==ANIM_ORIENTATION.OnGround)
assert(#first.fx._nw_beam_slices==16,"each former quarter is split into four consecutive material clips")
for index,piece in ipairs(first.fx._nw_beam_slices) do
    assert(piece.animation=="beam_0_part_"..(index-1))
    same_phase(first.fx,piece)
    if index>1 and index<16 then near(piece.x,(index-.5)/16) end
    if index>1 then
        assert(edge(first.fx._nw_beam_slices[index-1],1)>=edge(piece,-1)-.00001,
            "fading adjacent micro-pieces meet without a gap or double alpha")
    end
end
near(edge(first.fx,-1),0) -- no extension behind the original launch point
assert(first.fx.colour[1]==1 and first.fx.colour[2]==1 and first.fx.colour[3]==1,"painted source colours must survive runtime")
local initial_head=state.head.fx
assert(initial_head.animation=="head" and initial_head.loop and initial_head.bank=="nw_end_beam_head")
assert(initial_head.orientation==ANIM_ORIENTATION.BillBoard and initial_head.rotation==0,
    "the authored star faces the camera, independently of the ground-plane path")
assert(state.connector.fx.orientation==ANIM_ORIENTATION.OnGround)
assert(second.fx.finaloffset<state.connector.fx.finaloffset and state.connector.fx.finaloffset<initial_head.finaloffset,
    "beam below connector below star, with distinct draw depths")
near(initial_head.rate,.5)
near(initial_head.time,(now*.5)%(12/30))
near(state.connector.fx.x+state.connector.fx.sortoffset[1],initial_head.x)
near(state.connector.fx.z+state.connector.fx.sortoffset[3],initial_head.z)
near(initial_head.x,2);near(initial_head.y,1.4);near(initial_head.sx,3*2*.2/(64/150))
near(initial_head.sy,second.fx.sy*1.5) -- star 3x, beam and connector 2x
near(now-first.born,1.3) -- Unrelated server/client clocks; late join starts old.
near(core_scale(first.fx),.5);near(first.fx.sy,2*2*.12*Path.width(1.3)/(64/150))
near(first.fx.colour[4],Path.width(1.3));near(second.fx.colour[4],1)
near(second.fx.sy,2*2*.2/(64/150));near(centre(first.fx),.5);near(first.fx.y,1.4)
local born=first.born
near(core_scale(second.fx),.25);near(centre(second.fx),1.25)
near(leading(second.fx),initial_head.x-2.5*second.radius)
near(second.length,1);near(second.x2,2) -- clipping never edits the wire geometry
dark_start=1.005;tick(100.01)
assert(light_samples>0 and not TheWorld._nw_projectile_glows,"beam reuses its existing clock for local light")
assert(not first.fx.hidden and first.fx.light==1 and not first.fx.bloom)
assert(not second.fx.hidden and second.fx.light==1 and not second.fx.bloom
    and not initial_head.hidden and initial_head.light==1 and not initial_head.bloom,
    "first zero starts a fade without hiding geometry")
assert(not state.connector.fx.hidden and state.connector.fx.light==1 and not state.connector.fx.bloom)
tick(100.03) -- Before the independent front freshness timeout.
near(first.fx.light,1);near(second.fx.light,.9);near(initial_head.light,.9)
near(state.connector.fx.light,.9)
near(first.fx.colour[4],Path.width(1.33));near(second.fx.colour[4],1)
dark_start=math.huge;tick(100.032)
assert(not second.fx.hidden and second.fx.light==1 and not initial_head.hidden)
assert(not state.connector.fx.hidden and state.connector.fx.light==1)
near(first.born,born)
tick(100.1)
inst:PushEvent("nw_beamdirty") -- Same snapshot must not restore width or age.
near(first.born,born);near(core_scale(first.fx),.5)
near(first.fx.sy,2*2*.12*Path.width(1.4)/(64/150))
near(second.fx.sy,2*2*.2/(64/150))
assert(not state.head and not initial_head.valid,"stale front expires even while confirmed spans remain")
assert(first.fx.plays==1 and created==34,"dirty replay must not restart the material or resurrect a head")
tick(100.21)
assert(not state.parts[1] and not first.fx.valid and state.retired==1)
inst._beam_path:set(Path.encode({old,young},10.1))
inst:PushEvent("nw_beamdirty")
assert(not state.parts[1] and created==34,"retired IDs must not reappear from delayed snapshots")
near(second.born,99.8)

local newest=segment(3,2,3,10.08,.25)
inst.x=3;inst._beam_path:set(Path.encode({young,newest},10.11));inst:PushEvent("nw_beamdirty")
local third=state.parts[3]
assert(third and created==52 and not state.tip and state.head)
inst.x=3.8;tick(100.24)
local tip=state.tip
assert(tip and created==68 and #TheWorld._nw_beam_visuals.shots==1)
assert(third.fx.animation=="beam_2_part_0" and tip.fx.animation=="beam_3_part_0")
same_phase(second.fx,third.fx);same_phase(third.fx,tip.fx)
near(core_scale(tip.fx),.0875);near(core_scale(third.fx),.5)
near(leading(tip.fx),state.head.fx.x-2.5*tip.radius)
assert(not tip.fx.hidden,"a long tip ends precisely before the short connector")
inst.x=4.3;tick(100.26)
assert(state.tip==tip);near(core_scale(tip.fx),.3375);near(core_scale(third.fx),.5)
local moving_head=state.head.fx
near(moving_head.x,4.3)
inst._beam_ended:set(true);inst:PushEvent("nw_beamdirty")
assert(not state.tip and not tip.fx.valid and state.head.fx==moving_head and moving_head.valid
    and state.parts[2] and state.parts[3],"ending retains the star while confirmed beam spans exist")
near(moving_head.x,3) -- final wire endpoint wins over a speculative old tip
inst.x=6;tick(100.3)
assert(not state.tip and third.fx.valid and third.fx.sy>0,"confirmed path outlives the advancing head")
near(moving_head.x,3)

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
local jump_tip,jump_head=live.tip.fx,live.head.fx
front.x=1+Path.front_max_distance+.01;tick(200.06)
assert(not live.tip and not live.head and not jump_tip.valid and not jump_head.valid,"teleports must remove connector and star head")
front.x=2;tick(200.4)
assert(not live.tip and not live.head,"a missing snapshot must not leave a speculative front")
front:PushEvent("nw_beamdirty")
assert(not live.tip and not live.head,"duplicate snapshots must not renew front freshness")
front._beam_path:set(Path.encode({segment(2,1,2,20.49)},20.5));front:PushEvent("nw_beamdirty")
front.x=3;tick(200.41)
assert(live.tip and live.head and live.parts[2] and not live.parts[1])
local remaining=live.parts[2].fx
TheWorld:PushEvent("onremove")
assert(not front._nw_beam_visual and not remaining.valid and not TheWorld.tick and not next(TheWorld.events))

-- Four consecutive clips must reconstruct one flowing ribbon even when server
-- birth intervals vary, snapshots omit zero-motion records, or correct an age.
now=300
local ribbon=anchor(4,3)
local pieces={segment(1,0,1,29.1,.12),segment(2,1,2,29.65,.12),
    segment(3,2,3,29.82,.12),segment(4,3,4,29.98,.12,0,3)}
ribbon._beam_path:set(Path.encode(pieces,30))
local flow=Beam.attach(ribbon)
for id=1,4 do
    assert(flow.parts[id].fx.animation=="beam_"..(id-1).."_part_0")
    same_phase(flow.parts[1].fx,flow.parts[id].fx)
end
local diagonal=flow.parts[4].fx
near(core_scale(diagonal),(math.sqrt(10)-.3)/2)
near(centre(diagonal),3.5-.15/math.sqrt(10))
near((diagonal._nw_beam_slices[8].z+diagonal._nw_beam_slices[9].z)*.5,1.5-.45/math.sqrt(10))
near(diagonal.rotation,-math.deg(math.atan2(3,1)))
tick(300.05)
ribbon.x=4.5;tick(300.06)
assert(flow.tip and flow.tip.fx.animation=="beam_0_part_0")
same_phase(flow.parts[4].fx,flow.tip.fx)
local old_time=diagonal.time
pieces[4].born=29.94
ribbon._beam_path:set(Path.encode(pieces,30.06));ribbon:PushEvent("nw_beamdirty")
near(diagonal.time,old_time)
same_phase(flow.parts[1].fx,diagonal)
assert(diagonal.plays==1,"age correction cannot restart the flowing texture")
local parallel=anchor(1)
parallel._beam_path:set(Path.encode({segment(1,0,1,39.99)},40))
local scheduler=TheWorld.tick
local other=Beam.attach(parallel)
assert(#TheWorld._nw_beam_visuals.shots==2 and TheWorld.tick==scheduler,"multiple shots share one scheduler")
ribbon:Remove()
assert(TheWorld.tick==scheduler and other.head.fx.valid,"removing one shot must preserve other shots")
parallel:Remove()
assert(not TheWorld.tick)

-- The 80-unit (2.5r) cutback consumes short terminal spans and a speculative
-- tip, but never edits their fixed geometry or reaches disconnected old art.
now=400
local short=anchor(.8)
local short_segments={segment(1,-1,.7,39.99,.4)}
for id=2,5 do short_segments[#short_segments+1]=segment(id,(id-2)*.2,(id-1)*.2,39.99,.4) end
short._beam_path:set(Path.encode(short_segments,40))
local clipped=Beam.attach(short)
near(core_scale(clipped.parts[1].fx),.85)
near(core_scale(clipped.parts[2].fx),.003/2)
assert(not clipped.parts[2].fx.hidden,"a disconnected tail retains its true material entrance")
for id=3,5 do
    assert(clipped.parts[id].fx.hidden,"short spans beyond the entrance must hide")
    near(clipped.parts[id].length,.2)
end
dark_start=-math.huge;tick(400.01)
dark_start=math.huge;tick(400.02)
assert(not clipped.parts[1].fx.hidden and clipped.parts[5].fx.hidden,
    "illumination recovery must respect the current connector clip")
short.x=1.2;tick(400.03)
near(clipped.tip.length,.4);near(core_scale(clipped.tip.fx),0)
near(core_scale(clipped.parts[2].fx),.1)
near(leading(clipped.parts[2].fx),clipped.head.fx.x-2.5*.4)
assert(not clipped.parts[2].fx.hidden and clipped.parts[3].fx.hidden)
short._beam_ended:set(true);short:PushEvent("nw_beamdirty")
assert(clipped.head and clipped.connector and not clipped.tip)
near(clipped.head.fx.x,.8)
assert(clipped.parts[5].fx.hidden,"the endpoint retains its tapered connection through residue lifetime")
short:Remove()

-- A connector only replaces a straight tail, retaining a visible entrance
-- before a corner, reversal or discontinuous path ID.
now=500
local corner=anchor(1,.2)
corner._beam_path:set(Path.encode({segment(1,0,1,49.99,.2),
    segment(2,1,1,49.99,.2,0,.2)},50))
local bent=Beam.attach(corner)
near(core_scale(bent.parts[1].fx),.5);near(centre(bent.parts[1].fx),.5)
near(core_scale(bent.parts[2].fx),.003/2)
assert(not bent.parts[2].fx.hidden and bent.connector.terminal==2)
assert(bent.head.fx.orientation==ANIM_ORIENTATION.BillBoard and bent.head.fx.rotation==0)
near(bent.connector.fx.rotation,-90)
corner.x=1;corner.z=.1;tick(500.01)
near(core_scale(bent.parts[2].fx),.1)
near(core_scale(bent.parts[1].fx),.5)
near(core_scale(bent.tip.fx),.003/2)
assert(bent.connector.terminal==3,"a reversed tip only replaces its own straight tail")
near(bent.head.fx.rotation,0);near(bent.connector.fx.rotation,90)
assert(bent.parts[2].fx.finaloffset<bent.connector.fx.finaloffset
    and bent.connector.fx.finaloffset<bent.head.fx.finaloffset,"turning retains all three draw depths")
corner.x=1+Path.front_max_distance+.01;tick(500.02)
assert(not bent.head and not bent.tip)
near(core_scale(bent.parts[2].fx),.1);assert(not bent.parts[2].fx.hidden)
corner:Remove()

now=600
local gentle=anchor(.4,.02)
gentle._beam_path:set(Path.encode({segment(1,0,.2,59.99,.2),
    segment(2,.2,.4,59.99,.2,0,.02)},60))
local curve=Beam.attach(gentle)
near(core_scale(curve.parts[1].fx),.1);near(core_scale(curve.parts[2].fx),.003/2)
assert(curve.connector.terminal==2,"even a gentle bend shortens the straight connector")
tick(600.3)
assert(not curve.head and not curve.parts[1].fx.hidden and not curve.parts[2].fx.hidden,
    "stale heads restore the full surviving confirmed path")
gentle:Remove()

now=700
local gap=anchor(.4)
gap._beam_path:set(Path.encode({segment(1,0,.2,69.99,.2),segment(3,.2,.4,69.99,.2)},70))
local separated=Beam.attach(gap)
near(core_scale(separated.parts[1].fx),.1)
near(core_scale(separated.parts[3].fx),.003/2)
assert(not separated.parts[1].fx.hidden and separated.connector.terminal==3,
    "even touching geometry cannot bridge a missing terminal path ID")
gap:Remove()

-- A very short turned tip must stay whole when there is not enough room for
-- both a visible material edge and a connector; no partially clipped gap.
now=800
local tiny=anchor(1)
tiny._beam_path:set(Path.encode({segment(1,0,1,79.99,.2)},80))
local tiny_state=Beam.attach(tiny)
assert(tiny_state.connector)
tiny.z=.004;tick(800.01)
assert(not tiny_state.connector and not tiny_state.tip.fx.hidden)
near(core_scale(tiny_state.tip.fx),.002);near(core_scale(tiny_state.parts[1].fx),.5)
tiny.z=.02;tick(800.02)
assert(tiny_state.connector and tiny_state.connector.terminal==2)
near(core_scale(tiny_state.tip.fx),.003/2)
near(tiny_state.connector.fx.sx*(80/150),.017)
tiny:Remove()

now=900
local resized=anchor(.4)
resized._beam_path:set(Path.encode({segment(1,0,.2,89.99,.1),segment(2,.2,.4,89.99,.4)},90))
local sized=Beam.attach(resized)
assert(sized.connector and sized.connector.terminal==2)
near(core_scale(sized.parts[1].fx),.1)
near(sized.connector.fx.sy,sized.parts[2].fx.sy)
near(sized.connector.fx.sx*(80/150),.197)
resized:Remove()

-- A viewer joining after the endpoint burst still sees the stationary star.
-- It survives the front freshness timeout and stays full-sized until the last
-- ribbon expires; duplicate snapshots cannot restart that lifetime.
now=950
local finished=anchor(999,999)
finished._beam_path:set(Path.encode({segment(1,0,.3,94.7,.2),segment(2,.3,.6,94.99,.2)},95))
finished._beam_ended:set(true)
local residue=Beam.attach(finished)
assert(residue.head and residue.connector and not residue.tip)
assert(residue.head.fx.orientation==ANIM_ORIENTATION.BillBoard and residue.head.fx.rotation==0,
    "late-joining viewers reconstruct the same upright terminal star")
local ending_star=residue.head.fx
near(ending_star.x,.6);near(ending_star.z,0)
local ending_scale=ending_star.sx
tick(951.25)
assert(residue.head and residue.parts[2] and not residue.parts[1],"star outlives the first expired span")
near(ending_star.sx,ending_scale)
finished:PushEvent("nw_beamdirty")
tick(951.48)
assert(ending_star.valid and residue.parts[2],"star remains through the last beam fade")
near(ending_star.x,.6);near(ending_star.sx,ending_scale)
tick(951.5)
assert(not residue.head and not residue.connector and not next(residue.parts) and not ending_star.valid)
assert(not TheWorld.tick,"no task or head survives the last beam segment")
finished:PushEvent("nw_beamdirty")
assert(not residue.head and not next(residue.parts),"late duplicate cannot resurrect the terminal star")
finished:Remove()

-- A new snapshot can lead the carrier's interpolated client Transform. Draw
-- only up to the same resolved front as the star, not a reversed speculative
-- tip with the already-confirmed beam sticking out beyond it.
now=970;TheWorld.ismastersim=false
local delayed=anchor(1.4)
delayed._beam_path:set(Path.encode({segment(1,0,1,96.99,.12),
    segment(2,1,1.5,96.99,.12),segment(3,1.5,2,96.99,.12)},97))
local lagged=Beam.attach(delayed)
local function visible_end_is_star(s)
    local head=s.head.fx
    for _,part in pairs(s.parts) do
        for _,fx in ipairs(part.fx._nw_beam_slices) do
            if not fx.hidden then
                assert(fx.x+fx.sx/16<=head.x+.00001,"confirmed path must not lead the rendered star")
            end
        end
    end
    if s.connector then
        local connector=s.connector.fx
        near(connector.x+connector.sx*(80/150)*.5,head.x)
        near(connector.x+connector.sortoffset[1],head.x)
        near(connector.z+connector.sortoffset[3],head.z)
    end
end
near(lagged.head.fx.x,1.4)
assert(lagged.front_tail.id==2 and not lagged.tip and lagged.parts[3].fx.hidden)
near(lagged.parts[3].x2,2);near(lagged.parts[2].length,.5)
visible_end_is_star(lagged)
local terminal_slice=lagged.parts[2].fx._nw_beam_slices[16]
near(terminal_slice.x+terminal_slice.sortoffset[1],lagged.head.fx.x)
near(lagged.parts[1].fx.sortoffset[1],0) -- far rear keeps normal world sorting
delayed.x=1.5;tick(970.005)
assert(lagged.connector and lagged.front_tail.id==2,"snapshot boundary reuses the preceding visible tail without a connector flash")
visible_end_is_star(lagged)
delayed.x=1.6;tick(970.01)
near(lagged.head.fx.x,1.6);assert(lagged.front_tail.id==3)
visible_end_is_star(lagged)
delayed.x=2.1;tick(970.02)
assert(not lagged.front_tail and lagged.tip)
visible_end_is_star(lagged)
delayed._beam_ended:set(true);delayed:PushEvent("nw_beamdirty")
near(lagged.head.fx.x,2);assert(not lagged.tip)
visible_end_is_star(lagged)
tick(971.25)
visible_end_is_star(lagged)
assert(lagged.head.fx.rate==.5,"terminal star keeps the slower animation clock")
for _,heading in ipairs({0,45,90,135,180,225,270,315}) do
    TheCamera.heading=heading
    tick(971.25)
    local head=lagged.head.fx
    for _,part in pairs(lagged.parts) do
        for _,fx in ipairs(part.fx._nw_beam_slices) do
            local dx,dz=fx.x-head.x,fx.z-head.z
            local a=math.rad(heading)
            local px,pz=dz*math.cos(a)-dx*math.sin(a),(dx*math.cos(a)+dz*math.sin(a))*math.sin(math.rad(35))
            if not fx.hidden and px*px+pz*pz<(.12*3*108/64)^2 then
                near(fx.x+fx.sortoffset[1],head.x)
                near(fx.z+fx.sortoffset[3],head.z)
            end
        end
    end
end
TheCamera.heading=-90
delayed:Remove();TheWorld.ismastersim=nil

-- The fastest legal beam advances over six units during two frames between
-- ordinary 0.1-second snapshots. Its star and connector must stay continuous.
now=980
local fast_step=require("nw/spell_limits").max_speed/30
local fast=anchor(0)
local fast_records={segment(1,-fast_step,0,now)}
fast._beam_path:set(Path.encode(fast_records,now))
local fast_visual=Beam.attach(fast)
for frame=1,6 do
    now=980+frame/30
    fast.x=frame*fast_step
    fast_records[#fast_records+1]=segment(frame+1,(frame-1)*fast_step,fast.x,now)
    if frame%3==0 then
        fast._beam_path:set(Path.encode(fast_records,now));fast:PushEvent("nw_beamdirty")
    else tick(now) end
    assert(fast_visual.head and fast_visual.connector,"maximum-speed front survives normal snapshot gaps")
    near(fast_visual.head.fx.x,fast.x)
    visible_end_is_star(fast_visual)
end
tick(now+Path.front_max_age+.01)
assert(not fast_visual.head and not fast_visual.tip and not fast_visual.connector
    and next(fast_visual.parts),"high-speed allowance must still reject a stale front")
fast:Remove()

-- A fresh snapshot can lead the interpolated client by two frames at 95.
-- Clip its confirmed spans to the star instead of drawing a backward tip.
now=982;TheWorld.ismastersim=false
local fast_client=anchor(tonumber(string.format("%.3f",fast_step)))
local client_records={}
for id=1,3 do client_records[id]=segment(id,(id-1)*fast_step,id*fast_step,now) end
fast_client._beam_path:set(Path.encode(client_records,now))
local fast_lagged=Beam.attach(fast_client)
assert(fast_lagged.head and fast_lagged.connector and fast_lagged.front_tail
    and fast_lagged.front_tail.id==1 and not fast_lagged.tip,
    "two-frame high-speed client lag retains the preceding connected span")
near(fast_lagged.head.fx.x,fast_client.x)
visible_end_is_star(fast_lagged)
assert(fast_lagged.parts[3].fx.hidden,"confirmed geometry beyond the client front stays hidden")
fast_client:Remove();TheWorld.ismastersim=nil

-- A turn's outside miter point must lie inside both neighbouring quads.
-- Merely subdividing rectangles, or limiting the join by tiny micro-length,
-- leaves exactly the triangular gaps seen on a curved ribbon.
local function contains(fx,x,z)
    local angle=-math.rad(fx.rotation)
    local dx,dz=x-fx.x,z-fx.z
    return math.abs(dx*math.cos(angle)+dz*math.sin(angle))<=fx.sx/16+.00001
        and math.abs(-dx*math.sin(angle)+dz*math.cos(angle))<=fx.sy*(64/150)/2+.00001
end
for _,degrees in ipairs({-90,-45,-12,-5,5,12,45,90}) do
    now=980
    local angle=math.rad(degrees)
    local turns=anchor(999,999) -- no head/connector clipping in this geometry check
    turns._beam_path:set(Path.encode({segment(1,0,1,98,.12),
        segment(2,1,1+math.cos(angle),98,.12,0,math.sin(angle))},98))
    local joined=Beam.attach(turns)
    local left,right=joined.parts[1],joined.parts[2]
    local last=left.fx._nw_beam_slices[16]
    local actual=math.atan2(right.z2-right.z1,right.x2-right.x1)
    local hx,hz=1+.24*math.tan(math.abs(actual)/2),degrees>0 and -.24 or .24
    assert(contains(last,hx,hz) and contains(right.fx,hx,hz),
        "both sides must cover the outer corner at "..degrees.." degrees")
    assert(edge(last,1)>1,"previous span extends slightly into the turn")
    near(edge(left.fx,-1),0)
    local endx,endz=edge(right.fx._nw_beam_slices[16],1)
    near(endx,right.x2);near(endz,right.z2) -- bare final end stays bounded
    tick(980.03)
    for _,part in pairs(joined.parts) do
        for _,fx in ipairs(part.fx._nw_beam_slices) do
            same_phase(left.fx,fx)
            assert(fx.plays==1,"moving/recomputing joins must never restart any material clip")
        end
    end
    turns:Remove()
end
for _,gap_case in ipairs({{id=3,start=1},{id=2,start=1.05}}) do
    now=990
    local broken=anchor(999,999)
    broken._beam_path:set(Path.encode({segment(1,0,1,99),
        segment(gap_case.id,gap_case.start,2,99)},99))
    local disconnected=Beam.attach(broken)
    near(edge(disconnected.parts[1].fx._nw_beam_slices[16],1),1)
    near(edge(disconnected.parts[gap_case.id].fx,-1),gap_case.start)
    broken:Remove()
end

now=995
local fading=anchor(999,999)
fading._beam_path:set(Path.encode({segment(1,0,1,99.5)},99.5))
local faded=Beam.attach(fading)
local fade_slices=faded.parts[1].fx._nw_beam_slices
local full_overlap=edge(fade_slices[8],1)-edge(fade_slices[9],-1)
assert(full_overlap>0,"opaque micro-pieces overlap to cover ordinary filtering seams")
tick(996.4)
local faded_overlap=edge(fade_slices[8],1)-edge(fade_slices[9],-1)
near(faded_overlap,0) -- neither doubled alpha nor a gap during the fade
near(edge(fade_slices[1],-1),0);near(edge(fade_slices[16],1),1)
for _,fx in ipairs(fade_slices) do
    same_phase(fade_slices[1],fx)
    assert(fx.plays==1,"fading must preserve all clip clocks")
end
fading:Remove()

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
print("beam visual: painted spans, age-monotonic snapshots, fixed length, narrowing width, bounded connector/star head, end/world cleanup and dedicated skip")
