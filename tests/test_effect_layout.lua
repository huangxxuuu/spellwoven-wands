-- Exercise the replica's dirty handler. Each arc piece is local to the one
-- networked parent, and its image-space endpoints must land on the span.
local layout=require("nw/fx_layout")
local electric=require("nw/electric_visual")
local stages=require("nw/field_stages")
local factories,entities={},{}
Prefab=function(name,fn) factories[name]=fn;return name end
Asset=function() end
ANIM_ORIENTATION={OnGround=1,BillBoard=2}
TheCamera={heading=0,pitch=35}
GetTime=function() return 0 end
TheWorld={ismastersim=false};TheNet={IsDedicated=function() return false end}
net_float=function() return {v=0,value=function(t) return t.v end} end
net_entity=function() return {value=function(self) return self.v end} end
net_string=function() return {v="",value=function(self) return self.v end} end
CreateEntity=function()
    local e={events={},entity={},valid=true,Transform={},AnimState={}}
    entities[#entities+1]=e
    for _,name in ipairs({"AddNetwork","AddTransform","AddAnimState","SetPristine","SetParent","SetCanSleep"}) do e.entity[name]=function() end end
    for _,name in ipairs({"SetBank","SetBuild","SetOrientation","SetLightOverride","SetFinalOffset","SetBloomEffectHandle","PlayAnimation","SetMultColour"}) do e.AnimState[name]=function() end end
    e.AnimState.SetAddColour=function() end
    e.AnimState.SetTime=function() end
    e.AnimState.Hide=function(_,layer) e.hidden=layer end
    e.AnimState.SetOrientation=function(_,value) e.orientation=value end
    e.AnimState.PlayAnimation=function(_,anim) e.anim=anim end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.SetScale=function(_,x,y,z) e.scalex,e.scaley,e.scalez=x,y,z end
    e.Transform.SetRotation=function(_,r) e.rotation=r end
    e.AnimState.SetScale=function(_,a,b) e.sx,e.sy=a,b end
    function e:AddTag() end
    function e:ListenForEvent(event,fn) self.events[event]=fn end
    function e:DoTaskInTime(_,fn) fn(self) end
    function e:DoPeriodicTask(_,fn) self.tick=fn;return {Cancel=function() self.cancelled=true end} end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false;if self.events.onremove then self.events.onremove() end end
    return e
end
require("prefabs/nw_spell_fx")
local function close(a,b) return math.abs(a-b)<1e-8 end
-- Real cloud strike anchors follow the billboard artwork at every zoom/angle,
-- rather than treating its painted height as a fixed world-space Y value.
for _,size in ipairs({1,2.5,5}) do
    local lift=stages.storm_lift({size_mult=size})
    assert(close(lift*electric.pixels_per_unit,345*size))
    for _,pitch in ipairs({25,35,60}) do
        local _,_,_,raised=electric.span(3,.75,1,lift,0,math.rad(pitch))
        local _,sy=electric.project(0,raised,0,0,math.rad(pitch))
        assert(close(sy*electric.pixels_per_unit,-345*size))
    end
end
for _,v in ipairs({{0,0,0,0},{.3,0,0,0},{0,0,-2.1,0},{-3,.7,4,0},{6,-1.5,0,0},{3,.75,1,2.2},{0,.3,0,4.4}}) do
for _,heading in ipairs({0,45,110,270}) do
for _,pitch in ipairs({25,35,60}) do
    entities={}
    TheCamera.heading,TheCamera.pitch=heading,pitch
    local dx,dy,dz,lift=unpack(v)
    local arc=factories.nw_arc_fx()
    arc._dx.v=dx;arc._dy.v=dy;arc._dz.v=dz;arc._lift.v=lift;arc.events.nw_arcdirty()
    local count,scale,dir,raised=electric.span(dx,dy,dz,lift,math.rad(heading),math.rad(pitch))
    assert(#entities==count+1)
    local sx,sy=electric.project(0,raised,0,math.rad(heading),math.rad(pitch))
    assert(close(sx,0) and close(sy,-lift),"cloud start matches its billboard lift at every pitch")
    local tx,ty=electric.project(dx,dy,dz,math.rad(heading),math.rad(pitch))
    for i=2,#entities do
        local p=entities[i]
        assert(p.orientation==ANIM_ORIENTATION.BillBoard and p.anim=="arc_"..dir)
        assert(close(p.sx,scale) and close(p.sy,scale))
        local px,py=electric.project(p.x,p.y,p.z,math.rad(heading),math.rad(pitch))
        local t=(i-1.5)/count
        assert(close(px,sx+(tx-sx)*t) and close(py,sy+(ty-sy)*t),"short pieces follow true projected 3D span")
    end
    arc.events.nw_arcdirty();assert(#entities==count+1)
    arc.tick();assert(#entities==count+1,"camera refresh reuses local pieces")
    arc:Remove();for _,p in ipairs(entities) do assert(not p.valid) end
    assert(arc.cancelled)
end
end
end
entities={}
TheCamera.heading,TheCamera.pitch=0,35
local target={entity={},Transform={GetScale=function() return 2,2,2 end},IsValid=function() return true end}
local arc=factories.nw_arc_fx()
arc._dz.v=1;arc._contact.v=target;arc._shockanim.v="shock_large"
arc.events.nw_arcdirty()
assert(#entities==3 and entities[2].anim=="arc_0" and entities[3].anim=="shock_large")
assert(entities[3].scalex==.5,"native shock keeps its intended size on scaled targets")
TheCamera.heading=90;arc.tick()
assert(entities[2].anim=="arc_64" and #entities==3,"camera turning updates existing segment")
arc:Remove();assert(not entities[2].valid and not entities[3].valid)
TheNet.IsDedicated=function() return true end
entities={};local dedicated=factories.nw_arc_fx()
assert(#entities==1 and dedicated.tick==nil,"dedicated server never creates visual pieces")
TheNet.IsDedicated=function() return false end
local blast=factories.nw_blast_fx()
assert(blast.hidden=="blast_burst","all spell explosions must hide the radius guide")
blast._radius.v=3;blast.events.nw_blastradiusdirty()
assert(blast.sx==blast.sy and close(blast.sx*layout.blast_pixels/layout.pixels_per_unit,6))
local lighter=factories.nw_lighter_burst_fx()
assert(lighter.hidden=="blast_burst","lighter burst must not draw a range ring")
local crystal=factories.nw_crystal_burst_fx()
assert(crystal.hidden=="blast_burst" and crystal.anim=="blast","crystals retain burst but hide range ring on clients")
for _,r in ipairs({3,7.5,15}) do
    lighter._radius.v=r;lighter.events.nw_blastradiusdirty()
    assert(close(lighter.sx*layout.blast_pixels/layout.pixels_per_unit,2*r),"replicated burst diameter matches cooking radius")
    crystal._radius.v=r;crystal.events.nw_blastradiusdirty()
    assert(close(crystal.sx*layout.blast_pixels/layout.pixels_per_unit,2*r),"crystal burst still scales with radius")
end
print("effect layout: 3D electric endpoints, cloud lift at all camera angles, local cleanup and blast diameter")
