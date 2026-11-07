-- Actual visual scheduler + field callbacks: members never change gameplay
-- timing, and raw removal cannot create a shatter/payload/ending effect.
local now,guid,created,dedicated,timeScale=0,0,0,false,1
local paused=false
local tasks,fxs,controllers={},{},{}
GetTime=function() return now end
FRAMES=1/30
ANIM_ORIENTATION={BillBoard=2,OnGround=1}
TheCamera={heading=0}
TheNet={IsDedicated=function() return dedicated end}
local noop=function() end
local function net()
    local n={v=0}
    function n:set(v) self.v=v end
    function n:value() return self.v end
    return n
end
net_float=net;net_tinybyte=net;net_smallbyte=net;net_ushortint=net
local function entity()
    guid=guid+1;created=created+1
    local e={GUID=guid,valid=true,visible=true,x=0,y=0,z=0,scale=1,components={},events={},clips={}}
    function e:IsValid() return self.valid end
    e.tags={}
    function e:HasTag(tag) return self.tags[tag]==true end
    function e:AddTag(tag) self.tags[tag]=true end
    function e:IsInLimbo() return false end
    function e:Show() self.visible=true end
    function e:Hide() self.visible=false end
    function e:GetDistanceSqToPoint(x,y,z) return (self.x-x)^2+(self.z-z)^2 end
    function e:GetPhysicsRadius() return .1 end
    function e:SetPhysicsRadiusOverride(r) self.physicsradius=r end
    function e:ListenForEvent(name,fn,source)
        source=source or self;source.events[name]=source.events[name] or {}
        table.insert(source.events[name],{target=self,fn=fn})
    end
    function e:RemoveEventCallback(name,fn,source)
        local list=(source or self).events[name] or {}
        for i=#list,1,-1 do if list[i].target==self and list[i].fn==fn then table.remove(list,i) end end
    end
    function e:PushEvent(name)
        local copy={};for i,v in ipairs(self.events[name] or {}) do copy[i]=v end
        for _,v in ipairs(copy) do if v.target.valid then v.fn(self) end end
    end
    function e:Remove() if self.valid then self:PushEvent("onremove");self.valid=false end end
    function e:DoTaskInTime(delay,fn)
        local t={inst=self,at=now+delay,fn=fn,Cancel=function(t) t.cancelled=true end}
        tasks[#tasks+1]=t;return t
    end
    function e:DoPeriodicTask(period,fn,delay)
        local t=self:DoTaskInTime(delay or period,fn);t.period=period;return t
    end
    function e:AddComponent(name)
        if name=="health" then
            self.components.health={SetMaxHealth=function(h,n) h.currenthealth=n end,SetInvincible=noop,IsDead=function() return false end}
            return self.components.health
        elseif name=="combat" then
            self.components.combat={SetTarget=function(c,target) c.target=target end,CanTarget=function() return true end,IsAlly=function() return false end}
            return self.components.combat
        end
        assert(name=="updatelooper","unexpected gameplay component on a local visual controller: "..name)
        local c={callbacks={}}
        function c:AddOnWallUpdateFn(fn) self.callbacks[fn]=true end
        function c:RemoveOnWallUpdateFn(fn) self.callbacks[fn]=nil end
        function c:OnWallUpdate(dt)
            -- Native updatelooper suppresses wall callbacks while paused.
            if not paused then for fn in pairs(self.callbacks) do fn(e,dt) end end
        end
        self.components[name]=c;controllers[#controllers+1]=self
        return c
    end
    e.entity=setmetatable({IsVisible=function() return e.visible end,GetParent=function() return e.parent end,
        AddNetwork=function() e.networked=true end,AddPhysics=function() e.physical=true end,
        SetParent=function(_,p) e.parent=p.inst end,inst=e},{__index=function() return noop end})
    e.Transform={GetWorldPosition=function() return e.x,e.y,e.z end,
        SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end,
        SetScale=function(_,x,y,z) assert(x==y and y==z);e.scale=x end,
        GetScale=function() return e.scale,e.scale,e.scale end,SetFourFaced=noop}
    e.AnimState=setmetatable({
        SetBank=function(_,name) e.bank=name end,
        SetScale=function(_,x,y) e.artscale={x,y} end,
        SetOrientation=function(_,orientation) e.orientation=orientation end,
        SetFinalOffset=function(_,offset) e.finaloffset=offset end,
        PlayAnimation=function(_,name,loop) e.anim=name;e.clips[#e.clips+1]={name=name,at=now,loop=loop,playback=e.playback or 1} end,
        PushAnimation=function(_,name,loop) e.queued=name;e.clips[#e.clips].queued=name end,
        SetTime=function(_,t) e.animtime=t end,
        SetDeltaTimeMultiplier=function(_,speed) assert(speed>0 and speed<math.huge);e.playback=speed end,
    },{__index=function() return noop end})
    return e
end
CreateEntity=entity
TheWorld=entity();TheWorld.ismastersim=true
TheSim={FindEntities=function() return {} end,GetTimeScale=function() return timeScale end}
local function wallframe(dt)
    for _,e in ipairs(controllers) do
        if e.valid then
            assert(not e.networked and not e.physical,"wall controller is strictly local and visual")
            e.components.updatelooper:OnWallUpdate(dt)
        end
    end
end
local function simulation(target)
    while true do
        local nexttask
        for _,t in ipairs(tasks) do
            if not t.cancelled and t.inst.valid and t.at<=target+1e-9 and (not nexttask or t.at<nexttask.at) then nexttask=t end
        end
        if not nexttask then break end
        now=nexttask.at
        if nexttask.period then nexttask.at=now+nexttask.period else nexttask.cancelled=true end
        nexttask.fn(nexttask.inst)
    end
    now=target
end
local function advance(target)
    while now<target-1e-9 do
        local step=math.min(1/120,target-now)
        simulation(now+step)
        wallframe(step)
    end
    simulation(target)
end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." ~= "..tostring(b)) end
Asset=function() end
Prefab=function(name,fn) return {name=name,fn=fn} end
MakeProjectilePhysics=noop
local prefabs={}
for _,file in ipairs({"nw_field_stage_fx","nw_garden"}) do
    local values={dofile("mod/scripts/prefabs/"..file..".lua")}
    for _,p in ipairs(values) do prefabs[p.name]=p.fn end
end
SpawnPrefab=function(name)
    assert(prefabs[name],name)
    local e=prefabs[name]();fxs[#fxs+1]=e;return e
end
local Stages=require("nw/field_stages")
local Members=require("nw/field_member_visual")
local Fields=require("nw/expanded_fields")
local Effects=require("nw/spell_effects")
local Guard=require("nw/guard_ring")
local function field(id,p,loading)
    local e=entity();Stages.setup(e,id);Stages.attach(e,id)
    p=p or {id=id,radius=3,flags={}}
    require("nw/projectile_size").field(e,p)
    Stages.start(e,id,p,loading);return e,p
end
local function active(s)
    local n=0;for _,part in ipairs(s.members) do if part.fx.valid then n=n+1 end end;return n
end

-- World positions do not depend on camera or parent rotation. Compiled radius
-- is already giant-scaled: 7.5 remains 7.5, while each shield is 2 * 2.5 large.
local guard=field("guard_ring",{id="guard_ring",radius=7.5,size_mult=2.5})
guard._nw_guard_left=2
advance(.1)
local gs=guard._nw_field_members
local a=gs.members[1]
near((a.x^2+a.z^2)^.5,7.5);near(a.scale,5)
local before={a.x,a.z}
TheCamera.heading=135;guard.rotation=180
-- Evaluate at the same world time, with the actual shared callback.
wallframe(0)
near(a.x,before[1]);near(a.z,before[2])
-- Rendering must continue between 30 Hz simulation ticks. Neither GetTime nor
-- the replicated anchor advances during these four 120 Hz render frames.
local function angle_delta(x,z,px,pz) return math.atan2(x*pz-z*px,x*px+z*pz) end
local fixed=now
for i=1,4 do
    local x,z=a.x,a.z
    wallframe(1/120)
    assert(math.abs(angle_delta(x,z,a.x,a.z))>1e-5,"shield freezes between simulation ticks")
end
near(now,fixed)
local x,z=a.x,a.z
paused=true
for i=1,12 do wallframe(1/120) end
near(a.x,x);near(a.z,z)
paused=false
timeScale=0
for i=1,12 do wallframe(1/120) end
near(a.x,x);near(a.z,z)
timeScale=1
wallframe(1/120)
local normal_step=angle_delta(x,z,a.x,a.z)
x,z=a.x,a.z;timeScale=.5;wallframe(1/120)
near(angle_delta(x,z,a.x,a.z),normal_step*.5)
timeScale=1
local start=gs.started
advance(.25)
assert(guard._nw_stage_phase:value()==Stages.phase.idle,"late join must receive settled idle")
local late=entity();Stages.setup(late,"guard_ring")
for _,key in ipairs({"phase","seq","size","radius","count","age","seed"}) do
    late["_nw_stage_"..key]:set(guard["_nw_stage_"..key]:value())
end
Stages.attach(late,"guard_ring");advance(.3)
assert(late._nw_field_members.members[1].fx.anim=="guard_member_idle")
late:Remove()
assert(Guard.consume(guard,entity()) and guard._nw_guard_left==1)
advance(.34)
near(gs.started,start)
assert(gs.members[2].fx.anim=="guard_member_end" and gs.members[1].fx.valid)
advance(.7)
assert(active(gs)==1,"consumed shield must finish independently")
local shatters=0
for _,clip in ipairs(gs.members[2].fx.clips) do if clip.name=="guard_member_end" then shatters=shatters+1 end end
assert(shatters==1,"remaining shield's idle update cannot restart the retired shield's shatter")
assert(Guard.consume(guard,entity()) and not guard.valid)
local ending=fxs[#fxs]
local old_controller=gs.pool.controller
advance(.74)
assert(active(ending._nw_field_members)==1,"last shield end must not resurrect the consumed shield")
assert(ending._nw_field_members.members[1].fx.anim=="guard_member_end")
advance(1.05)
assert(not ending.valid and not TheWorld._nw_field_members and not old_controller.valid)

-- A raw removal cleans members and the shared task immediately, with no end.
local raw=field("vital_ring")
advance(1.1)
local oldfx=#fxs
local raw_state=raw._nw_field_members
local raw_controller=raw_state.pool.controller
raw:Remove()
assert(#fxs==oldfx and active(raw_state)==0 and not TheWorld._nw_field_members and not raw_controller.valid)

-- Execute the real vital-ring prefab: healing and visual pulse happen at the
-- same three callbacks, even when lifetime and giant size are modified.
package.loaded["nw/field_motion"]={start=function() return true end}
local healed={}
local owner=entity()
owner.components.health={currenthealth=10,IsDead=function() return false end,GetMaxWithPenalty=function() return 100 end,
    DoDelta=function(self,n) self.currenthealth=self.currenthealth+n;healed[#healed+1]=now end}
Effects.scan=function() return {owner} end
local ring=prefabs.nw_vital_ring()
local launched=now
local cleaned=0
ring:Launch(owner,{id="vital_ring",kind="field",radius=6,size_mult=2,field_lifetime_mult=2,flags={}},0,0,1,0,function() cleaned=cleaned+1 end)
advance(launched+.25)
local rs=ring._nw_field_members
assert(active(rs)==26)
for i=1,8 do near((rs.members[i].x^2+rs.members[i].z^2)^.5,6);near(rs.members[i].scale,2) end
for i=9,20 do
    local part=rs.members[i]
    assert(part.kind=="vital" and part.index==i)
    assert(part.scale>=2*.36-1e-6 and part.scale<=2*.62+1e-6,"small mushrooms keep their own giant-scaled size")
    local r=(part.x^2+part.z^2)^.5
    assert(r>=6*.83-1e-6 and r<=6*1.13+1e-6,"fillers must stay around the actual healing boundary")
    local nearest=math.huge
    for j=1,8 do
        local main=rs.members[j]
        nearest=math.min(nearest,math.abs(angle_delta(main.x,main.z,part.x,part.z)))
    end
    assert(nearest>.08,"small mushrooms should fill gaps rather than stack on large mushrooms")
end
local seed=ring._nw_stage_seed:value()
assert(seed>0)
local next_cast=field("vital_ring")
assert(next_cast._nw_stage_seed:value()~=seed,"separate casts must not reuse the same layout seed")
next_cast:Remove()
local late_vital=entity();Stages.setup(late_vital,"vital_ring")
for _,key in ipairs({"phase","seq","size","radius","count","age","seed"}) do
    late_vital["_nw_stage_"..key]:set(ring["_nw_stage_"..key]:value())
end
Stages.attach(late_vital,"vital_ring");wallframe(0)
for i=1,20 do
    local a,b=rs.members[i],late_vital._nw_field_members.members[i]
    near(a.x,b.x);near(a.z,b.z);near(a.scale,b.scale)
    assert(b.fx.anim=="vital_member_idle","late join must not regrow the mushroom field")
end
late_vital:Remove()
-- Identical seed and elapsed time reproduce all members, including randomized
-- light centres, drift speeds and phases, despite unrelated controller GUIDs.
local replicas={}
for i=1,2 do
    local e=entity();Stages.setup(e,"vital_ring")
    Stages.effect_state(e,"vital_ring","idle",2,6,20,.8,seed)
    Stages.attach(e,"vital_ring");replicas[i]=e
end
wallframe(0)
for i=1,26 do
    local a,b=replicas[1]._nw_field_members.members[i],replicas[2]._nw_field_members.members[i]
    near(a.x,b.x);near(a.y,b.y);near(a.z,b.z);near(a.scale,b.scale)
end
local first_mote=replicas[1]._nw_field_members.members[21]
local mx,mz=first_mote.x,first_mote.z
wallframe(1/120)
assert(math.abs(first_mote.x-mx)+math.abs(first_mote.z-mz)>1e-6,"motes move at render cadence too")
for i=21,26 do
    local a,b=replicas[1]._nw_field_members.members[i],replicas[2]._nw_field_members.members[i]
    near(a.x,b.x);near(a.y,b.y);near(a.z,b.z)
end
for _,e in ipairs(replicas) do e:Remove() end
local px,pz=rs.members[3].x,rs.members[3].z
TheCamera.heading=290;ring.rotation=-90
wallframe(0)
near(rs.members[3].x,px);near(rs.members[3].z,pz)
for i=1,3 do
    advance(launched+i*2+.04)
    assert(#healed==i and ring._nw_stage_phase:value()==Stages.phase.pulse)
    near(healed[i],launched+i*2)
    assert(rs.members[1].fx.anim=="vital_member_pulse")
    assert(rs.members[21].fx.anim=="vital_mote_pulse","independent light motes acknowledge the same heal callback")
end
advance(launched+6.2)
assert(not ring.valid and cleaned==1 and #healed==3)
local tail=fxs[#fxs]
assert(tail._nw_stage_seed:value()==seed,"ending FX must retain this cast's layout seed")
advance(launched+6.24)
assert(tail._nw_field_members and tail._nw_field_members.members[1].fx.anim=="vital_member_end")
for i=1,20 do
    local a,b=rs.members[i],tail._nw_field_members.members[i]
    near(a.x,b.x);near(a.z,b.z);near(a.scale,b.scale)
end
advance(launched+6.55)
assert(not tail.valid and not TheWorld._nw_field_members)

-- Meteor waits for its actual modified deadline, falls once, then ends while
-- its gameplay entity is removed immediately (the independent FX is harmless).
Effects.scan=function() return {} end
local blasts=0
Effects.blast=function() blasts=blasts+1 end
local moon,mp=field("moon_fall",{id="moon_fall",radius=2,field_lifetime_mult=3,flags={}})
local launched=now
Fields.actions.moon_fall(moon,owner,mp,0,0)
advance(launched+2.15);assert(moon.anim=="moon_fall_warning" and blasts==0)
advance(launched+2.17);assert(moon.anim=="moon_fall_fall" and blasts==0)
advance(launched+2.4);assert(not moon.valid and blasts==1)
local falls=0;for _,clip in ipairs(moon.clips) do if clip.name=="moon_fall_fall" then falls=falls+1 end end
assert(falls==1)

-- Footprints track actual compiled radius, with giant applied only once to
-- both the gameplay anchor and its independent ending visual.
-- Moon measures the solid body (100 px), excluding its surrounding flame tail.
for id,width in pairs({shock_ring=191,vortex=220,moon_fall=100}) do
    for _,size in ipairs({1,2.5}) do
        local radius=2.3*size
        local e=field(id,{id=id,radius=radius,size_mult=size,flags={}})
        local orientation=id=="moon_fall" and ANIM_ORIENTATION.BillBoard or ANIM_ORIENTATION.OnGround
        assert(e.orientation==orientation,"circular fields must project on the actual ground plane")
        local expected=radius*2*(id=="moon_fall" and .6 or 1)
        near(width/150*e.artscale[1]*e.scale,expected)
        if id=="moon_fall" then
            local shadow=e._nw_moon_shadow
            assert(shadow and shadow.valid and not shadow.networked and not shadow.physical)
            assert(shadow.orientation==ANIM_ORIENTATION.OnGround)
            near(609.30005/150*shadow.scale*e.scale,expected)
            near(609.30005,296.77435*shadow.artscale[2])
            local late=entity();Stages.setup(late,id)
            late._nw_moon_radius:set(e._nw_moon_radius:value())
            Stages.attach(late,id)
            near(late._nw_moon_shadow.scale,shadow.scale)
            late:Remove();assert(not late._nw_moon_shadow.valid)
        end
        Stages.finish(e)
        local ending=fxs[#fxs]
        assert(ending.orientation==orientation,"ending visual must use the same ground plane as the active field")
        near(width/150*ending.artscale[1]*ending.scale,expected)
        e:Remove()
        if id=="moon_fall" then assert(not e._nw_moon_shadow.valid) end
    end
end

for _,id in ipairs({"crystal_mine","sleep_crystal","payload_egg","moon_fall","delay_seal",
    "detonate","rain_cloud","storm_cloud","guard_ring","deer_decoy","vital_ring"}) do
    local upright=entity();Stages.setup(upright,id)
    assert(upright.orientation==ANIM_ORIENTATION.BillBoard)
    Stages.effect_state(upright,id,"end",1,2,1,0,1)
    assert(upright.orientation==ANIM_ORIENTATION.BillBoard,"other bodies and endings must remain upright")
    upright:Remove()
end

-- Deer expiry makes one direct spin contact and retires gameplay immediately;
-- its half-second tail contains no damage tasks or chained placements.
for _,size in ipairs({1,2.5}) do
    local p={id="deer_decoy",radius=3*size,size_mult=size,damage=5,flags={}}
    local e=field("deer_decoy",p)
    near(e.scale,size);near(e.artscale[1],2);near(e.artscale[2],2)
    Stages.pulse(e)
    near(e.artscale[1]*e.scale,2*size)
    Stages.finish(e)
    local ending=fxs[#fxs]
    near(ending.artscale[1]*ending.scale,2*size)
    near(ending.artscale[2]*ending.scale,2*size)
    near(e._nw_field_stages.radius,3*size);near(p.damage,5)
    e:Remove()
end
local Hits=require("nw/expanded_hits")
local card
for _,v in ipairs(require("nw/expansion")) do if v.id=="deer_decoy" then card=v end end
assert(card and card.damage==5)
owner:AddComponent("combat")
local target=entity();target:AddComponent("health");target:AddComponent("combat");target.x=1
local player=entity();player:AddTag("player");player:AddComponent("health");player:AddComponent("combat");player.x=2
local far=entity();far:AddComponent("health");far:AddComponent("combat");far.x=4
local placement=entity();placement:AddComponent("health");placement:AddComponent("combat")
placement._nw_break=function() error("deer must not trigger a placed crystal or payload") end
local structure=entity();structure:AddTag("structure");structure:AddComponent("health");structure:AddComponent("combat")
Effects.scan=function() return {target,player,far,placement,structure} end
local damage={}
local original_direct=Effects.direct
Effects.direct=function(caster,e,p)
    assert(caster==owner and p.damage==5)
    if e==player then assert(p.flags.targets.self and p.flags.targets.players_other) end
    damage[e]=(damage[e] or 0)+1
end
local deer,dp=field("deer_decoy",{id="deer_decoy",radius=3,damage=card.damage,field_lifetime_mult=2,flags={}})
local launched=now
local prior_blasts=blasts
Fields.actions.deer_decoy(deer,owner,dp,0,0)
assert(deer.bank==Stages.bank and deer.anim=="deer_decoy_spawn" and deer.queued=="deer_decoy_idle")
advance(launched+5.99)
assert(deer.valid and not next(damage) and target.components.combat.target==deer)
advance(launched+6)
assert(not deer.valid and blasts==prior_blasts and damage[target]==1 and damage[player]==1)
assert(not damage[far] and not damage[placement] and not damage[structure])
local tail=fxs[#fxs]
assert(tail.valid and tail.anim=="deer_decoy_end" and not tail.components.health and not tail.components.combat)
advance(launched+6.49);assert(tail.valid)
advance(launched+6.5);assert(not tail.valid and damage[target]==1 and damage[player]==1)
Effects.direct=original_direct
Effects.scan=function() return {} end

-- Cloud gathering completes at the first warning, and its longer dispersed
-- tail retires independently of gameplay, even with long-life/giant modifiers.
near(Stages.duration("storm_cloud","spawn"),.5)
near(Stages.duration("storm_cloud","warning"),.3)
near(Stages.duration("storm_cloud","end"),.8)
near(Stages.duration("rain_cloud","spawn"),.2)
near(Stages.duration("rain_cloud","end"),.3)
local loaded_storm=field("storm_cloud",nil,true)
assert(loaded_storm.anim=="storm_cloud_idle" and loaded_storm._nw_field_stages.storm_cycle==nil)
for cycle=1,4 do
    local index=(cycle-1)%3+1
    local suffix=index==1 and "" or "_"..index
    Stages.warning(loaded_storm)
    assert(loaded_storm.anim=="storm_cloud_warning"..suffix and loaded_storm.queued=="storm_cloud_idle"..suffix)
    Stages.pulse(loaded_storm)
    assert(loaded_storm.anim=="storm_cloud_pulse"..suffix and loaded_storm.queued=="storm_cloud_idle"..suffix)
end
loaded_storm:Remove()
local rain=field("rain_cloud")
Stages.warning(rain);assert(rain.anim=="rain_cloud_warning" and rain.queued=="rain_cloud_idle")
Stages.pulse(rain);assert(rain.anim=="rain_cloud_pulse" and rain._nw_field_stages.storm_cycle==nil)
rain:Remove()
local electric_hits={}
local original_electric=Hits.electric
Hits.electric=function(caster,e,x,z,damage,p,base_only,height,lift)
    assert(caster==owner and e==target and damage==7 and base_only==false)
    electric_hits[#electric_hits+1]={at=now,height=height,lift=lift}
end
Effects.scan=function() return {target} end
for _,lifetime in ipairs({1,2,.5,.25,1/64}) do
    electric_hits={}
    target._nw_storm_next=nil
    local visual_scale=math.min(1,lifetime)
    local storm,sp=field("storm_cloud",{id="storm_cloud",damage=7,radius=7.5,size_mult=2.5,field_lifetime_mult=lifetime,flags={}})
    storm.Transform:SetPosition(0,.4,0)
    local launched=now
    Fields.actions.storm_cloud(storm,owner,sp,0,0)
    near(storm.playback,1/visual_scale)
    assert(storm.finaloffset==4,"cloud foreground must cover the top of the attack arc")
    advance(launched+.49*visual_scale)
    assert(storm.anim=="storm_cloud_spawn" and #electric_hits==0,"gathering must not be interrupted or strike early")
    advance(launched+2.55*lifetime)
    local warns,pulses={},{}
    for _,clip in ipairs(storm.clips) do
        if clip.name:match("^storm_cloud_warning") then
            warns[#warns+1]=clip.at;near(clip.playback,1/visual_scale)
            local suffix=#warns==1 and "" or "_"..#warns
            assert(clip.name=="storm_cloud_warning"..suffix and clip.queued=="storm_cloud_idle"..suffix)
        elseif clip.name:match("^storm_cloud_pulse") then
            pulses[#pulses+1]=clip.at;near(clip.playback,1/visual_scale)
            local suffix=#pulses==1 and "" or "_"..#pulses
            assert(clip.name=="storm_cloud_pulse"..suffix and clip.queued=="storm_cloud_idle"..suffix)
        end
    end
    assert(#warns==3 and #pulses==3 and not storm.valid)
    assert(warns[1]>=launched+Stages.duration("storm_cloud","spawn")/storm.playback-1e-6,
        "even stacked short-life modifiers must finish gathering before warning")
    local expected_hits,next_hit={},-math.huge
    for i=1,3 do
        near(pulses[i],launched+i*.8*lifetime);near(warns[i],pulses[i]-.3*visual_scale)
        -- Preserve the existing per-target .45 s cooldown, which intentionally
        -- suppresses repeat damage from tightly spaced short-lived strikes.
        if pulses[i]>=next_hit then expected_hits[#expected_hits+1]=pulses[i];next_hit=pulses[i]+.45 end
    end
    assert(#electric_hits==#expected_hits)
    for i,at in ipairs(expected_hits) do
        near(electric_hits[i].at,at);near(electric_hits[i].height,.4);near(electric_hits[i].lift,345/150*2.5)
    end
    local tail=fxs[#fxs]
    assert(tail.valid and tail.anim=="storm_cloud_end" and not tail.components.health and not tail.components.combat)
    near(tail.scale,2.5)
    assert(tail.finaloffset==4,"the fading cloud retains its arc occlusion order")
    near(tail.playback,1)
    advance(launched+2.55*lifetime+.79)
    assert(tail.valid and #electric_hits==#expected_hits,"dispersal must remain visual only")
    advance(launched+2.55*lifetime+.8)
    assert(not tail.valid and #electric_hits==#expected_hits,"dispersal must retire with its final frame")
end
Hits.electric=original_electric
Effects.scan=function() return {} end
-- The two shock pulses retain their existing gameplay times.
local shock,sp=field("shock_ring",{id="shock_ring",radius=2,flags={}})
local launched=now
Fields.actions.shock_ring(shock,owner,sp,0,0)
advance(launched+2)
local pulses={};for _,clip in ipairs(shock.clips) do if clip.name=="shock_ring_pulse" then pulses[#pulses+1]=clip.at end end
assert(#pulses==2);near(pulses[1],launched+.85);near(pulses[2],launched+1.85)

-- A failed egg release retains its animation and entity, then can retry once.
local egg,ep=field("payload_egg",{id="payload_egg",radius=1,flags={}})
local ok=false
Fields.actions.payload_egg(egg,owner,ep,0,0,1,0,function() return ok end)
oldfx=#fxs;egg._nw_break(owner)
assert(egg.valid and not egg._nw_spent and #fxs==oldfx)
ok=true;egg._nw_break(owner);egg._nw_break(owner)
assert(not egg.valid and #fxs==oldfx+1)
local loaded=field("sleep_crystal",nil,true)
assert(loaded.anim=="sleep_crystal_idle")
loaded:Remove()

-- Unload and dedicated-server paths cannot leak local sprites/tasks.
local unload=field("vital_ring");advance(now+.04)
local us=unload._nw_field_members
local unload_controller=us.pool.controller
TheWorld:PushEvent("onremove")
assert(active(us)==0 and not unload._nw_field_members and not TheWorld._nw_field_members and not unload_controller.valid)
dedicated=true
local plain=entity();Stages.setup(plain,"guard_ring")
local total=created
assert(not Members.attach(plain,"guard_ring") and created==total)
local moon_server=entity();Stages.setup(moon_server,"moon_fall")
total=created;Stages.attach(moon_server,"moon_fall")
assert(created==total and not moon_server._nw_moon_shadow,"dedicated servers must not create local shadows")
print("field stages: real timing, giant world members, shield consumption, late join, raw removal, unload and dedicated cleanup")
