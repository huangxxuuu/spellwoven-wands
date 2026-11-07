-- A contact cue has its own replicated lifetime and never restarts on dirty.
local now,dedicated=0,false
local entities={}
local function noop() end
GetTime=function() return now end
DEGREES=math.pi/180
ANIM_ORIENTATION={BillBoard=2}
TheCamera={heading=0,pitch=35}
TheNet={IsDedicated=function() return dedicated end}
TheWorld={ismastersim=false}
Asset=noop;Prefab=function(_,fn) return fn end
local function net()
    return {v=0,set=function(self,v) self.v=v end,value=function(self) return self.v end}
end
net_byte=net;net_float=net
CreateEntity=function()
    local e={GUID=#entities+1,valid=true,events={},tasks={},periodic={},entity={},Transform={},AnimState={},plays=0}
    entities[#entities+1]=e
    for _,name in ipairs({"AddTransform","AddAnimState","AddNetwork","SetCanSleep","SetPristine"}) do e.entity[name]=noop end
    e.entity.SetParent=function(_,parent) e.parent=parent end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.SetScale=function(_,x,y,z) e.sx,e.sy,e.sz=x,y,z end
    for _,name in ipairs({"SetBank","SetBuild","SetLightOverride"}) do e.AnimState[name]=noop end
    e.AnimState.SetOrientation=function(_,v) e.orientation=v end
    e.AnimState.PlayAnimation=function(_,name,loop) e.anim,e.loop=name,loop;e.plays=e.plays+1 end
    e.AnimState.SetTime=function(_,age) e.age=age end
    function e:AddTag() end
    function e:ListenForEvent(event,fn) self.events[event]=fn end
    function e:DoTaskInTime(delay,fn) self.tasks[#self.tasks+1]={delay=delay,fn=fn} end
    function e:DoPeriodicTask(period,fn)
        local task={period=period,fn=fn,Cancel=function(self) self.cancelled=true end}
        self.periodic[#self.periodic+1]=task
        return task
    end
    function e:Hide() self.hidden=true end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false;if self.events.onremove then self.events.onremove(self) end end
    return e
end
local make=require("prefabs/nw_elemental_hit_fx")
local client=make()
client.tasks[1].fn(client)
assert(#entities==1,"uninitialized cue must not flash the default element")
client._height:set(1.7);client._size:set(2.5);client._heading:set(0);client._kind:set(1)
client.events.nw_elemental_hitdirty()
local visual=entities[2]
assert(visual.parent==client.entity and visual.y==1.7 and visual.sx==2.5*.85)
assert(visual.orientation==ANIM_ORIENTATION.BillBoard and visual.anim:find("^fire_hit_dir_") and not visual.loop)
local previous=visual.anim
now=.1;TheCamera.heading=90;client.periodic[1].fn()
assert(visual.anim~=previous and math.abs(visual.age-.1)<1e-8,"turning camera must preserve impact age")
local plays=visual.plays
client.events.nw_elemental_hitdirty()
assert(visual.plays==plays and #entities==2,"dirty packets must not replay or duplicate the cue")
client._size:set(1);client.events.nw_elemental_hitdirty()
assert(visual.sx==.85 and visual.y==1.7)
now=.2;client.periodic[1].fn()
assert(visual.hidden and client.periodic[1].cancelled,"contact only lasts six frames")
client.events.nw_elemental_hitdirty();assert(visual.plays==plays and #entities==2)
client:Remove();assert(not visual:IsValid())

TheWorld.ismastersim=true
for _,headless in ipairs({false,true}) do
    dedicated=headless;now=1
    local before=#entities
    local host=make()
    assert(host.tasks[1].delay==.2)
    host:SetImpact("frost",1.4,1,math.pi)
    assert(host._kind:value()==2 and host._heading:value()==math.pi)
    assert(#entities==before+(headless and 1 or 2),"dedicated hosts create no local sprite")
    if not headless then
        local frost=entities[#entities]
        assert(frost.sx==.7 and frost.anim:find("^frost_hit_dir_"))
        host.tasks[1].fn(host);assert(not frost:IsValid() and host.periodic[1].cancelled)
    else host.tasks[1].fn(host) end
end

local AnimatedFlight=require("nw/elemental_flight")
dedicated=false
for _,id in ipairs({"gust","spore_ball","flint_lance","slime","grow_orb","heal_bolt",
    "star_vortex","glass_disc","land_hook","tri_electric","end_beam","soundwave","bee_swarm","fireflies",
    "note_a","ocarina_b","note_c","ocarina_d","ocarina_e","ocarina_f","ocarina_gsharp","ocarina_a2","ocarina_g"}) do
    local cue=make()
    cue:SetImpact(id,1.6,2.5,math.pi/3)
    local expected=AnimatedFlight.resolve(id)
    local art=entities[#entities]
    assert(cue._kind:value()>5 and art.anim==expected.."_hit_dir_"..AnimatedFlight.direction(math.pi/3,expected))
    assert(art.y==1.6 and art.sx>0)
    cue.tasks[1].fn(cue)
    assert(not art:IsValid())
end

-- Exercise the real swept collision path; expiry and silent cleanup never cue.
local P=require("nw/projectiles")
local Flight=require("nw/flight")
local Effects=require("nw/spell_effects")
local Bounds=require("nw/world_bounds")
local candidates,cues={},{}
local owner={valid=true,components={combat={CanTarget=function() return true end,IsAlly=function() return false end}}}
function owner:IsValid() return self.valid end
TheWorld={Map={IsPassableAtPoint=function() return true end}}
TheSim={FindEntities=function() return candidates end}
SpawnPrefab=function(name)
    assert(name=="nw_elemental_hit_fx","contact cue must not create other gameplay effects")
    local cue={}
    cue.Transform={SetPosition=function(_,x,y,z) cue.x,cue.y,cue.z=x,y,z end}
    cue.SetImpact=function(_,id,height,size,heading) cue.id,cue.height,cue.size,cue.heading=id,height,size,heading end
    cues[#cues+1]=cue
    return cue
end
Effects.direct=function() end -- Existing status tests own fire/cold gameplay.
local function target(x,wall)
    local e={GUID=math.floor(x*10),components={health={IsDead=function() return false end},combat={GetAttacked=noop}}}
    e.Transform={GetWorldPosition=function() return x,0,0 end}
    function e:IsValid() return true end
    function e:IsInLimbo() return false end
    function e:HasTag(tag) return wall and tag=="wall" or false end
    function e:GetPhysicsRadius() return .5 end
    return e
end
local function shot(id,base,flags)
    local p={id=id,base=base,flags=flags or {},damage=9,speed=15,lifetime=1.2}
    local e={valid=true,x=3,z=0}
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetRotation=noop}
    e.Physics={SetMotorVel=noop,Teleport=function(_,x,_,z) e.x,e.z=x,z end}
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false end
    e._shot={owner=owner,p=p,x=0,z=0,dx=1,dz=0,time=0,age=0,remaining=1.2,
        travelled=0,hit={},damage=9,speed=15,height=1.65}
    Flight.reset(e._shot,1,0)
    return e
end
for _,id in ipairs({"fire","frost","fire_hit","frost_timer","arrow","heavy","scatter",
    "arrow_hit","arrow_timer","heavy_hit","heavy_timer","scatter_hit","scatter_timer"}) do
    local base=id:match("^(.-)_")
    local e=shot(id,base);e._shot.p.size_mult=2.5
    candidates={target(2)};local count=#cues
    P.step(e,.1,{})
    local cue=cues[#cues]
    assert(not e.valid and #cues==count+1 and cue.id==(base or id))
    assert(cue.height==1.65 and cue.size==2.5 and cue.heading==0 and cue.y==0)
    assert(math.abs(cue.x-1.2)<1e-8,"giant cue uses the actual swept contact point")
end
local e=shot("fire_hit","fire");e._shot.hits_left=3
local releases=0
e._shot.p.event="hit";e._shot.fire=function() releases=releases+1;return true end
candidates={target(2)};local count=#cues;P.step(e,.1,{})
assert(e.valid and #cues==count+1 and releases==1)
candidates={target(5)};e.x=6;P.step(e,.2,{})
assert(e.valid and #cues==count+2 and releases==2,"each piercing contact cues once")
candidates={};e.x=20;P.step(e,1.3,{})
assert(not e.valid and #cues==count+2 and releases==2,"expiry neither cues nor replays a successful payload")

e=shot("frost");e._shot.bounces=1;candidates={target(2,true)};count=#cues
P.step(e,.1,{})
assert(e.valid and e._shot.dx<0 and #cues==count+1 and cues[#cues].heading==0,"bounce cue keeps incoming direction")
e=shot("fire",nil,{phase_wall={}});P.step(e,.1,{})
assert(e.valid and #cues==count+1,"phased walls are not contacts")
for _,id in ipairs({"spark"}) do
    e=shot(id);P.step(e,.1,{})
    assert(not e.valid and #cues==count+1,"other projectile artwork remains unchanged")
end

local blasts,heals=0,0
Effects.blast=function() blasts=blasts+1 end
P.heal_fx=function() heals=heals+1 end
for _,id in ipairs({"gust","spore_ball","flint_lance","slime","grow_orb","heal_bolt",
    "star_vortex","glass_disc","tri_electric","bee_swarm","fireflies",
    "note_a","ocarina_b","note_c","ocarina_d","ocarina_e","ocarina_f","ocarina_gsharp","ocarina_a2","ocarina_g"}) do
    e=shot(id);candidates={target(2)};count=#cues
    if id=="heal_bolt" then
        e._shot.p.heal=8
        candidates[1].components.health.DoDelta=function(_,amount) assert(amount==8) end
    end
    P.step(e,.1,{})
    assert(not e.valid and #cues==count+1 and cues[#cues].id==AnimatedFlight.resolve(id))
end
assert(blasts==1 and heals==1,"spore contact blasts once and successful healing retains its contact cue")
local ally=Effects.ally
Effects.ally=function() return true end
e=shot("gust",nil,{heal_ally={heal=4}});e._shot.group={healed={}}
local ally_releases=0
e._shot.p.event="hit";e._shot.fire=function() ally_releases=ally_releases+1;return true end
candidates={target(2)};count=#cues
candidates[1].components.health.DoDelta=function(_,amount) assert(amount==4) end
P.step(e,.1,{})
assert(not e.valid and #cues==count+1 and heals==2 and e._shot.group.healed[candidates[1]])
assert(ally_releases==1,"ally cue must not add a hit release before the existing termination payload")
Effects.ally=ally

-- Beam contacts, one endpoint explosion and the retained damaging residue
-- are covered by test_end_beam.lua. Its SetImpact art is still checked above.
-- A visual-only break/ally cue must not release a payload.
e=shot("spore_ball");e._shot.p.event="hit"
e._shot.fire=function() error("visual-only contact cannot execute payloads") end
P.contact_fx(e._shot,1,2)
assert(cues[#cues].id=="spore_ball" and blasts==1 and e.valid)

candidates={};count=#cues
e=shot("fire");P.step(e,1.3,{})
assert(not e.valid and #cues==count,"natural expiration has no impact cue")
owner.valid=false;e=shot("frost");P.step(e,.1,{})
assert(not e.valid and #cues==count,"invalid owner cleanup stays silent")
owner.valid=true
local clip=Bounds.clip;Bounds.clip=function() return 0 end
e=shot("fire");P.step(e,.1,{})
assert(not e.valid and #cues==count,"world boundary cleanup stays silent")
Bounds.clip=clip
print("elemental impacts: contact-only cues, variants, pierce/bounce, silent cleanup, replicated phase and dedicated hosts")
