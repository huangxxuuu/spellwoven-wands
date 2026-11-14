-- Exercise real beam/projectile integration without a game server. Collision
-- payloads and the entity ledger outlive the front, but never the last segment.
local now,blasts=0,0
local candidates={}
local noop=function() end
GetTime=function() return now end
DEGREES=math.pi/180
TheWorld={Map={IsPassableAtPoint=function() return true end}}
TheSim={FindEntities=function() return candidates end}
local Effects=require("nw/spell_effects")
local real_blast=Effects.blast
local Explosions=require("nw/explosions")
local Bounds=require("nw/world_bounds")
local Flight=require("nw/flight")
local Beam=require("nw/end_beam")
local P=require("nw/projectiles")
local Path=require("nw/beam_path")
local owner={valid=true,components={combat={CanTarget=function() return true end,IsAlly=function() return false end}}}
owner.Transform={GetWorldPosition=function() return 0,0,0 end}
function owner:IsValid() return self.valid end
function owner:HasTag() return false end
function owner:GetPhysicsRadius() return .5 end
Effects.live=function(e) return e and e.valid end
Effects.direct=function(_,e,p) e.damage=e.damage+p.damage;e.direct=e.direct+1 end
Effects.blast=function() blasts=blasts+1 end
Effects.fx=function()
    return {SetImpact=noop,SetRadius=noop,Transform={SetPosition=noop}}
end
Explosions.hit=function(_,p,x,z)
    if p._test_shot then p._test_shot.explosions=p._test_shot.explosions+1 end
end
local guid=100
local function target(x,z,wall,radius)
    guid=guid+1
    local e={GUID=guid,x=x,z=z or 0,valid=true,dead=false,damage=0,direct=0,components={}}
    e.components.health={IsDead=function() return e.dead end}
    e.components.combat={GetAttacked=noop}
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return false end
    function e:HasTag(tag) return wall and tag=="wall" or false end
    function e:GetPhysicsRadius() return radius or .1 end
    return e
end
local function shot(lifetime,flags,scale)
    now=0;owner.valid=true
    local e={valid=true,x=0,z=0,removed=0,payloads=0,explosions=0,stopped=0,publishes={},head_stops=0,components={}}
    local p={id="end_beam",name="beam",damage=12,end_damage=16,speed=26,lifetime=lifetime,
        size_mult=scale or 1,flags=flags or {pierce_all={}},event="hit"}
    p._test_shot=e
    local group={remaining=1,healed={}}
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetRotation=function(_,angle) e.rotation=angle end}
    e.Physics={Stop=function() e.stopped=e.stopped+1 end,SetMotorVel=function(_,speed) e.speed=speed end,
        Teleport=function(_,x,y,z) e.x,e.z=x,z end}
    function e:IsValid() return self.valid end
    function e:Remove() assert(self.valid);self.valid=false;self.removed=self.removed+1;group.remaining=group.remaining-1 end
    function e:StopBeamHead() self.head_stops=self.head_stops+1 end
    function e:PublishBeam(segments,time,ended,force)
        self.publishes[#self.publishes+1]={count=#segments,time=time,ended=ended,force=force}
    end
    e._shot={owner=owner,p=p,damage=12,speed=26,remaining=lifetime,travelled=0,
        x=0,z=0,dx=1,dz=0,time=0,age=0,height=1.4,hit={},group=group,
        hits_left=2,bounces=p.flags.bounce and p.flags.bounce.bounces}
    e._shot.fire=function(x,z,dx,dz,hit)
        assert(group.remaining==1,"payload reservation must stay active while residue can hit")
        e.payloads=e.payloads+1;e.last_payload_target=hit
        if e.onpayload then e.onpayload(hit) end
        return true
    end
    Flight.reset(e._shot,1,0)
    return e
end
local function step(e,time,x,z)
    now=time
    if x then e.x,e.z=x,z or 0 end
    P.step(e,time,{})
end
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a).." ~= "..tostring(b)) end

-- Three targets pierce even if a stale hits_left value is finite. The same
-- active beam owns front and residue cooldowns, full damage and hit payloads.
local a,b,c=target(1),target(2),target(3)
local e=shot(.2);candidates={a,b,c}
step(e,.1,4)
assert(a.damage==12 and b.damage==12 and c.damage==12 and e.payloads==3 and e.explosions==3)
assert(e.valid and not e._shot.beam.ended and #e._shot.beam.segments==1)
local d=target(5);candidates[#candidates+1]=d
local blast_count=blasts
local partner={valid=true,_shot={partner=e},IsValid=function(self) return self.valid end}
e._shot.partner=partner
-- Avoid exercising unrelated arc rendering; the finish still unpairs it.
local Hits=require("nw/expanded_hits")
local original_step=Hits.step;Hits.step=noop
step(e,.2,6)
Hits.step=original_step
assert(e.valid and e._shot.beam.ended and e._shot.payload_finished and blasts==blast_count+1)
assert(e.head_stops==1 and e.stopped==1 and e._shot.group.remaining==1)
assert(not e._shot.partner and not partner._shot.partner)
assert(d.damage==12 and e.payloads==4 and e.explosions==4)
local newcomer=target(5.8);candidates[#candidates+1]=newcomer
step(e,.3)
assert(newcomer.damage==12 and e.last_payload_target==newcomer and e.payloads==5 and e.explosions==5,
    "a new target entering after the front ends still receives a full hit and payload")
step(e,.59)
assert(a.damage==12 and e.payloads==5)
step(e,.6)
assert(a.damage==24 and b.damage==24 and c.damage==24 and d.damage==12 and newcomer.damage==12)
assert(e.payloads==8 and e.explosions==8 and blasts==blast_count+1,"residue must not repeat endpoint explosions")
candidates={}
step(e,1.11)
assert(next(e._shot.beam.next_hit)==nil and next(e._shot.hit)==nil,"expired target history must not grow with beam lifetime")
step(e,1.7)
assert(not e.valid and e.removed==1 and e._shot.group.remaining==0 and blasts==blast_count+1)

-- A doubled-back path has two overlapping segments, but hits only once per
-- target per interval. The new front also cannot bypass an old segment's gate.
a=target(2);e=shot(.2);candidates={a}
step(e,.1,4);step(e,.2,0)
assert(#e._shot.beam.segments==2 and a.damage==12 and e.payloads==1)
step(e,.6)
assert(a.damage==24 and e.payloads==2 and e.explosions==2,"crossings must share one target cooldown")

-- Giant radius is baked once. Full width lasts 1.2 s, then the effective
-- collision radius shrinks with the visible 0.3 s fade.
e=shot(.1,nil,2.5);e._shot.p.event=nil;candidates={}
step(e,.1,4)
local segment=e._shot.beam.segments[1]
near(segment.radius,.3)
near(Path.width(1.2),1);near(Path.width(1.35),.5);near(Path.width(1.5),0)
local edge=target(2,.26,false,0);candidates={edge}
step(e,1.25);assert(edge.damage==12)
local fading_edge=target(2,.26,false,0)
local center=target(2,.1,false,0)
candidates={fading_edge,center};step(e,1.45)
assert(fading_edge.damage==0 and center.damage==12,"invisible faded width must not keep damaging")
step(e,1.6);assert(not e.valid)

-- Wall reflection records only the prefix before contact, never a segment
-- through the wall. Earlier hit payloads can destroy that wall before arrival.
local wall=target(2,0,true)
e=shot(4,{bounce={bounces=1},pierce_all={}});candidates={wall}
blast_count=blasts;step(e,.1,4)
assert(e.valid and not e._shot.beam.ended and e._shot.dx<0 and e._shot.bounces==0)
assert(#e._shot.beam.segments==1 and e._shot.beam.segments[1].x2<2 and blasts==blast_count)
a=target(1);wall=target(2,0,true)
e=shot(4);candidates={a,wall}
e.onpayload=function(hit) if hit==a then wall.dead=true end end
step(e,.1,4)
assert(e.valid and not e._shot.beam.ended and e._shot.beam.segments[1].x2==4,
    "a wall destroyed by an earlier payload cannot remain a stale terminal contact")

-- Owner loss and a world boundary are raw cleanup, not gameplay termination.
e=shot(4);candidates={};step(e,.1,2)
blast_count=blasts;owner.valid=false;step(e,.2,3)
assert(not e.valid and e.head_stops==0 and e.payloads==0 and blasts==blast_count)
e=shot(4);candidates={target(1)}
local clip=Bounds.clip;Bounds.clip=function() return .5 end
step(e,.1,4);Bounds.clip=clip
assert(not e.valid and e.head_stops==0 and e.payloads==0 and blasts==blast_count)
-- Ally healing and a direction controller ending are gameplay endpoints even
-- though ordinary projectiles suppress their natural-only terminal effects.
local original_ally=Effects.ally
local friend=target(1)
friend.components.health.DoDelta=function(_,amount) friend.healed=amount end
Effects.ally=function(_,entity) return entity==friend end
e=shot(4,{heal_ally={heal=5}});candidates={friend}
blast_count=blasts;step(e,.1,2)
Effects.ally=original_ally
assert(friend.healed==5 and e._shot.beam.ended and blasts==blast_count+1,
    "ally contact must burst immediately when it stops the beam front")
candidates={};step(e,.2);step(e,1.7)
assert(not e.valid and blasts==blast_count+1,"ally endpoint must not burst again during residue cleanup")

e=shot(4);candidates={}
local steer=Flight.steer
Flight.steer=function() return false end
blast_count=blasts;step(e,.1,2)
Flight.steer=steer
assert(e._shot.beam.ended and blasts==blast_count+1,
    "direction completion must burst in the frame the beam front stops")
step(e,.2);step(e,1.7)
assert(not e.valid and blasts==blast_count+1)

-- Exercise the real explosion dispatcher with no victims: the burst anchor
-- must spawn at arrival, without waiting for the remaining path to fade.
e=shot(.1);e._shot.p.event=nil;candidates={}
local fx,visuals=Effects.fx,{}
Effects.fx=function(name,x,z)
    visuals[#visuals+1]={name=name,x=x,z=z}
    return {SetRadius=noop}
end
Effects.blast=real_blast
step(e,.1,2)
assert(e.valid and e._shot.beam.ended and #visuals==1
    and visuals[1].name=="nw_soft_blast_fx" and visuals[1].x==2 and visuals[1].z==0,
    "an empty endpoint still explodes immediately")
step(e,.2);step(e,1.7)
assert(not e.valid and #visuals==1,"residue removal must not replay the endpoint visual")
Effects.fx=fx
Effects.blast=function() blasts=blasts+1 end

-- Guard interception and explicit raw removal remain silent like owner loss
-- and world clipping; neither is a gameplay endpoint.
local Guard=require("nw/guard_ring")
local Stages=require("nw/field_stages")
local guard_visual=Stages.guard;Stages.guard=noop
local Limits=require("nw/spell_limits")
local old_range=Limits.range
local guard_x=7
local defender={components={},IsValid=function() return true end,
    Transform={GetWorldPosition=function() return guard_x,0,0 end}}
local function ring()
    local r={valid=true,_nw_guard_owner=defender,_nw_guard_radius=.25,_nw_guard_left=2}
    function r:IsValid() return self.valid end
    function r:Remove() self.valid=false end
    TheWorld._nw_guards={[r]=true}
    return r
end
-- Actual ring geometry must ignore a ring beyond either accepted endpoint,
-- even when native physics crosses it during this single simulation frame.
for _,range_end in ipairs({false,true}) do
    Limits.range=range_end and 5 or 0
    guard_x=7;local r=ring()
    e=shot(range_end and 4 or .05);candidates={};blast_count=blasts
    step(e,.1,10)
    assert(e.valid and e._shot.beam.ended and e._shot.x==5 and blasts==blast_count+1
        and r._nw_guard_left==2,"a guard beyond the clipped endpoint must not swallow its explosion")
    step(e,1.7)
    assert(not e.valid and blasts==blast_count+1)
    guard_x=3;r=ring()
    e=shot(range_end and 4 or .05);local before_guard=target(1);candidates={before_guard}
    blast_count=blasts;step(e,.1,10)
    assert(not e.valid and e._nw_intercepted and r._nw_guard_left==1
        and e.head_stops==0 and blasts==blast_count and before_guard.damage==0,
        "a guard before the endpoint still intercepts silently before collision processing")
end
-- World clipping also limits the guard sweep, while retaining silent beam
-- boundary cleanup instead of turning the boundary into a gameplay endpoint.
Limits.range=0;guard_x=7;local r=ring()
e=shot(4);candidates={};blast_count=blasts
Bounds.clip=function() return .5 end
step(e,.1,10);Bounds.clip=clip
assert(not e.valid and not e._nw_intercepted and r._nw_guard_left==2 and blasts==blast_count)
TheWorld._nw_guards=nil;Stages.guard=guard_visual;Limits.range=old_range
e=shot(4);candidates={};blast_count=blasts
local intercept=Guard.intercept
Guard.intercept=function(inst) inst:Remove();return true,.5 end
step(e,.1,2);Guard.intercept=intercept
assert(not e.valid and e.head_stops==0 and not e._shot.payload_finished and blasts==blast_count)
e=shot(4);step(e,.1,2);e:Remove()
assert(e.head_stops==0 and not e._shot.payload_finished and blasts==blast_count)
-- Drive the real steering and beam loop together: sine, moving-owner orbit,
-- and their giant combination must record the actual curve with bounded age.
for _,case in ipairs({
    {flags={sine={amplitude=1.2,frequency=1.6}},scale=1},
    {flags={orbit={}},scale=1},
    {flags={orbit={},sine={amplitude=1.2,frequency=1.6}},scale=2.5},
}) do
    local owner_x=0
    owner.Transform.GetWorldPosition=function() return owner_x,0,0 end
    e=shot(4,case.flags,case.scale);candidates={};e.speed=26;e.rotation=0
    local bent=false
    for frame=1,75 do
        owner_x=owner_x+.6/30
        local angle=-e.rotation*DEGREES
        local nx,nz=e.x+math.cos(angle)*e.speed/30,e.z+math.sin(angle)*e.speed/30
        step(e,frame/30,nx,nz)
        assert(e.valid and not e._shot.beam.ended)
        local segments=e._shot.beam.segments
        assert(#segments<=46,"long-lived curved beams retain only their recent path")
        local newest=segments[#segments]
        near(newest.x2,e.x);near(newest.z2,e.z);near(newest.radius,.12*case.scale)
        if math.abs(newest.z2-newest.z1)>.01 then bent=true end
    end
    assert(bent and e._shot.beam.segments[1].born>1,"old origin must expire while the curve continues")
    if case.flags.orbit then assert(e._shot.orbit_radius>2) end
    e:Remove()
end
print("end beam: periodic payloads, shared cooldown, lingering cleanup, giant/sine/moving-owner orbit, fading width and terminal rules")

-- Compiled acceleration must reach the actual endpoint without an old 60
-- motor ceiling shortening it. The lingering path retains its own hit clock.
local Compiler=require("nw/compiler")
local saved_direct,saved_blast=Effects.direct,Effects.blast
for count,expected_speed in ipairs({26,41,62.5,93.75,95}) do
    local w=require("nw/generator").starter()
    w.stats.mana_max=10000;w.stats.draw_count=1;w.cards={}
    for n=1,count-1 do w.cards[#w.cards+1]={spell_id="speed_up",card_uid="up"..n} end
    w.cards[#w.cards+1]={spell_id="end_beam",card_uid="beam"}
    w.runtime=Compiler.initial(w.cards,w.stats,1)
    local descriptor=assert(Compiler.compile(w)).blocks[1].projectiles[1]
    near(descriptor.speed,expected_speed);near(descriptor.lifetime,.75)
    owner.Transform.GetWorldPosition=function() return 0,0,0 end
    local beam=shot(descriptor.lifetime,descriptor.flags,descriptor.size_mult)
    beam._shot.p=descriptor;beam._shot.damage=descriptor.damage
    beam._shot.speed=descriptor.speed;beam._shot.remaining=descriptor.lifetime
    Flight.reset(beam._shot,1,0);beam.speed=descriptor.speed;beam.rotation=0
    local victim=target(1);candidates={victim}
    local contacts,bursts={},{}
    Effects.direct=function(_,entity,p)
        entity.damage=entity.damage+p.damage
        contacts[#contacts+1]={time=now,damage=p.damage}
    end
    Effects.blast=function(_,x,z,p) bursts[#bursts+1]={x=x,z=z,damage=p.damage,radius=p.radius} end
    local frame=0
    while not (beam._shot.beam and beam._shot.beam.ended) do
        frame=frame+1;assert(frame<30 and beam.valid)
        local angle=-beam.rotation*DEGREES
        step(beam,frame/30,beam.x+math.cos(angle)*beam.speed/30,beam.z+math.sin(angle)*beam.speed/30)
    end
    local endpoint=expected_speed*.75
    near(beam._shot.x,endpoint);near(beam._shot.z,0)
    assert(#bursts==1 and beam.head_stops==1)
    near(bursts[1].x,endpoint);near(bursts[1].damage,16);near(bursts[1].radius,1.5)
    local segments=beam._shot.beam.segments
    local final_born=segments[#segments].born
    while frame/30<final_born+1.5-1e-6 do
        frame=frame+1;step(beam,frame/30)
        if frame/30<final_born+1.5-1e-6 then assert(beam.valid,"final residue expired early") end
    end
    assert(not beam.valid and beam.removed==1 and #bursts==1)
    assert(#contacts>=2,"the target must exercise lingering repeat damage")
    for index,contact in ipairs(contacts) do
        near(contact.damage,12)
        if index>1 then near(contact.time-contacts[index-1].time,.5) end
    end
    near(victim.damage,#contacts*12)
end
Effects.direct,Effects.blast=saved_direct,saved_blast
print("end beam compiled speed: 0-4 acceleration cards, 19.5/30.75/46.875/70.3125/71.25 endpoints, unchanged burst/residue/hit cadence")
