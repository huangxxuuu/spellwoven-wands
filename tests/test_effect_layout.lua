-- Exercise the replica's dirty handler. Each arc piece is local to the one
-- networked parent, and its image-space endpoints must land on the span.
local layout=require("nw/fx_layout")
local factories,entities={},{}
Prefab=function(name,fn) factories[name]=fn;return name end
Asset=function() end
ANIM_ORIENTATION={OnGround=1}
TheWorld={ismastersim=false};TheNet={IsDedicated=function() return false end}
net_float=function() return {v=0,value=function(t) return t.v end} end
net_entity=function() return {value=function(self) return self.v end} end
net_string=function() return {v="",value=function(self) return self.v end} end
CreateEntity=function()
    local e={events={},entity={},valid=true,Transform={},AnimState={}}
    entities[#entities+1]=e
    for _,name in ipairs({"AddNetwork","AddTransform","AddAnimState","SetPristine","SetParent"}) do e.entity[name]=function() end end
    for _,name in ipairs({"SetBank","SetBuild","SetOrientation","SetLightOverride","SetFinalOffset","SetBloomEffectHandle","PlayAnimation","SetMultColour"}) do e.AnimState[name]=function() end end
    e.AnimState.SetAddColour=function() end
    e.AnimState.Hide=function(_,layer) e.hidden=layer end
    e.AnimState.SetOrientation=function(_,value) e.orientation=value end
    e.AnimState.PlayAnimation=function(_,anim) e.anim=anim end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.z=x,z end
    e.Transform.SetRotation=function(_,r) e.rotation=r end
    e.AnimState.SetScale=function(_,a,b) e.sx,e.sy=a,b end
    function e:AddTag() end
    function e:ListenForEvent(event,fn) self.events[event]=fn end
    function e:DoTaskInTime(_,fn) fn(self) end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false;if self.events.onremove then self.events.onremove() end end
    return e
end
require("prefabs/nw_spell_fx")
local function close(a,b) return math.abs(a-b)<1e-8 end
for _,v in ipairs({{0,0},{.3,0},{0,-2.1},{-3,4},{6,0}}) do
    entities={}
    local dx,dz=v[1],v[2]
    local arc=factories.nw_arc_fx()
    arc._dx.v=dx;arc._dz.v=dz;arc.events.nw_arcdirty()
    local count=layout.arc(dx,dz)
    assert(#entities==count+1)
    local ex,ez=0,0
    for i=2,#entities do
        local p=entities[i]
        assert(p.orientation==ANIM_ORIENTATION.OnGround,"beam yaw must affect its rendered plane")
        assert(math.abs(p.sy)==1)
        local half=p.sx*layout.arc_pixels/layout.pixels_per_unit/2
        local ax,az=math.cos(math.rad(p.rotation))*half,-math.sin(math.rad(p.rotation))*half
        assert(close(p.x-ax,ex) and close(p.z-az,ez))
        ex,ez=p.x+ax,p.z+az
    end
    assert(close(ex,dx) and close(ez,dz))
    arc.events.nw_arcdirty();assert(#entities==count+1)
    arc:Remove();for _,p in ipairs(entities) do assert(not p.valid) end
end
entities={}
local target={entity={},IsValid=function() return true end}
local arc=factories.nw_arc_fx()
arc._dx.v=1;arc._contact.v=target;arc._shockanim.v="shock_large"
arc.events.nw_arcdirty()
assert(#entities==3 and entities[2].anim=="beam" and entities[3].anim=="shock_large")
arc:Remove();assert(not entities[2].valid and not entities[3].valid)
local blast=factories.nw_blast_fx()
blast._radius.v=3;blast.events.nw_blastradiusdirty()
assert(blast.sx==blast.sy and close(blast.sx*layout.blast_pixels/layout.pixels_per_unit,6))
local lighter=factories.nw_lighter_burst_fx()
assert(lighter.hidden=="blast_extent","lighter burst must not draw a range ring")
for _,r in ipairs({3,7.5,15}) do
    lighter._radius.v=r;lighter.events.nw_blastradiusdirty()
    assert(close(lighter.sx*layout.blast_pixels/layout.pixels_per_unit,2*r),"replicated burst diameter matches cooking radius")
end
print("effect layout: replicated arc endpoints, local segment cleanup and blast diameter")
