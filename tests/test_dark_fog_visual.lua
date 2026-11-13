local made,time={},0
GetTime=function() return time end
FRAMES=1/30
BLENDMODE={AlphaBlended=1}
UnitRand=function() return .25 end
CreateCircleEmitter=function(radius) assert(radius>0);return function() return radius/2,0 end end
TheSim={GetTickTime=function() return FRAMES end}
local scales={}
EnvelopeManager={AddColourEnvelope=function() end,AddVector2Envelope=function(_,name,points) scales[name]=points end}
EmitterManager={AddEmitter=function(_,fx,_,fn) fx.emit=fn end}
net_bool=function() local v=false;return {value=function() return v end,set=function(_,x) v=x end} end
net_float=function() local v=0;return {value=function() return v end,set=function(_,x) v=x end} end
CreateEntity=function()
    local e={events={},entity={},Transform={SetPosition=function() end}}
    for _,name in ipairs({"AddTransform","SetCanSleep","SetPristine"}) do e.entity[name]=function() end end
    e.entity.AddNetwork=function() e.network=true end
    e.entity.SetParent=function(_,parent) assert(e.spawn_completed,"VFX must complete native prefab spawn before parenting");e.parent=parent end
    e.entity.AddVFXEffect=function()
        local effect={particles=0,advanced=0}
        for _,name in ipairs({"InitEmitters","SetRenderResources","SetMaxNumParticles","SetRotationStatus",
            "SetMaxLifetime","SetColourEnvelope","SetScaleEnvelope","SetUVFrameSize","SetBlendMode",
            "SetSortOrder","SetSortOffset","SetRadius","SetDragCoefficient"}) do
            effect[name]=function(_,...) effect[name.."Args"]={...} end
        end
        effect.AddRotatingParticleUV=function(self,...) assert(e.spawn_completed,"cannot emit before native prefab completion");self.particles=self.particles+1;self.last={...} end
        effect.FastForward=function(self,index,dt) assert(e.spawn_completed,"cannot advance before native prefab completion");assert(index==0 and dt>=0);self.advanced=self.advanced+dt end
        effect.ClearAllParticles=function(self) self.particles=0;self.cleared=true end
        e.VFXEffect=effect;return effect
    end
    e.AddTag=function() end
    e.IsValid=function() return not e.removed end
    e.ListenForEvent=function(_,event,fn) e.events[event]=fn end
    e.Remove=function() e.removed=true;if e.events.onremove then e.events.onremove(e) end end
    e.DoPeriodicTask=function(_,_,fn) e.task={fn=fn,Cancel=function(self) self.cancelled=true end};return e.task end
    e.DoTaskInTime=function(_,delay,fn) assert(delay==0);e.init=fn end
    made[#made+1]=e;return e
end
-- No native damage cloud or ember prefab may be created by this visual layer.
Asset=function(_,path) return path end
Prefab=function(name,fn,assets) return {name=name,fn=fn,assets=assets} end
TheNet={IsDedicated=function() return true end}
local prefab,vfxprefab=dofile("mod/scripts/prefabs/nw_dark_fog.lua")
SpawnPrefab=function(name)
    assert(name=="nw_dark_fog_vfx" and vfxprefab.name==name,"unexpected gameplay/ember prefab: "..name)
    local fx=vfxprefab.fn()
    assert(fx.VFXEffect and fx.VFXEffect.InitEmittersArgs[1]==1)
    assert(fx.VFXEffect.SetRenderResourcesArgs[2]=="fx/miasma.tex")
    fx.spawn_completed=true -- Native SpawnPrefab completes render-node setup after fn returns.
    return fx
end
assert(prefab.assets[1]=="fx/miasma.tex" and prefab.assets[2]=="shaders/vfx_particle.ksh")
local dedicated=prefab.fn();assert(#made==1 and dedicated.network and not dedicated.Light)
TheNet.IsDedicated=function() return false end
local client=prefab.fn();assert(#made==2 and not client._nw_dark_visuals)
client.init();assert(#made==3 and client.network and not client.persists)
local child=made[3];local effect=child.VFXEffect
assert(not child.network and child.parent==client.entity and not child.persists)
assert(effect.SetRenderResourcesArgs[2]=="fx/miasma.tex")
assert(effect.SetUVFrameSizeArgs[2]==.5 and effect.SetRadiusArgs[2]==2)
assert(effect.particles==10)
for i=1,31 do child.emit() end
assert(effect.particles==12,"active smoke continues emitting")
require("nw/dark_fog_visual").attach(client);assert(#made==3)
client._nw_dark_dissipating:set(true);client.events.nw_dark_fog_dirty()
local task=client.task;local particles=effect.particles
for i=1,60 do child.emit() end
assert(effect.particles==particles,"dissipating smoke must stop emitting immediately")
time=.2;task.fn();assert(effect.advanced>.55 and not effect.cleared)
client.events.nw_dark_fog_dirty();assert(client.task==task,"duplicate dirty events must not restart fade")
time=.4;task.fn();assert(effect.particles==0 and task.cancelled)
client:Remove();assert(child.removed)
-- A late replica already marked dissipating must never emit a fresh cloud.
local late=prefab.fn();late._nw_dark_dissipating:set(true)
local count=#made
late.init()
assert(late._nw_dark_visual_fading and #made==count and #late._nw_dark_children==0)
late:Remove();assert(late.task.cancelled)
-- Removal without a fade also clears particles and disables future emissions.
local early=prefab.fn();early.init();local earlychild=early._nw_dark_children[1]
early:Remove();earlychild.emit()
assert(earlychild.removed and earlychild.VFXEffect.particles==0)
-- Initial network sizes and a delayed size update affect the entire fog,
-- including each smoke sprite, emission footprint, height and drift.
for _,radius in ipairs({.2,.8,2,5,10}) do
    local scaled=prefab.fn();scaled._nw_dark_radius:set(radius);scaled.init()
    local vfx=scaled._nw_dark_children[1].VFXEffect
    assert(vfx.SetRadiusArgs[2]==radius)
    local points=scales[vfx.SetScaleEnvelopeArgs[2]]
    assert(math.abs(points[1][2][1]-.8*radius/2)<1e-6)
    assert(math.abs(vfx.last[3]-(radius-.8*radius/2*1.3)/2)<1e-6)
    assert(math.abs(vfx.last[6]-.01*.25*radius/2)<1e-6)
    local old=scaled._nw_dark_children[1]
    scaled._nw_dark_radius:set(radius*2);scaled.events.nw_dark_fog_size_dirty()
    assert(old.removed and old.VFXEffect.cleared)
    assert(scaled._nw_dark_children[1].VFXEffect.SetRadiusArgs[2]==radius*2)
    local current=scaled._nw_dark_children[1]
    scaled._nw_dark_dissipating:set(true);scaled.events.nw_dark_fog_dirty()
    scaled._nw_dark_radius:set(radius);scaled.events.nw_dark_fog_size_dirty()
    assert(current==scaled._nw_dark_children[1],"late size update cannot restart a fading cloud")
    scaled:Remove()
end
print("dark fog visuals: native miasma resources, dedicated skip, local particles, no embers, fade, late replica and cleanup passed")
