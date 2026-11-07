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
    return {SetImpact=noop,Transform={SetPosition=noop}}
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
    local e={valid=true,x=0,z=0,removed=0,payloads=0,explosions=0,stopped=0,publishes={},head_stops=0}
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
