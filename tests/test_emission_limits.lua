local E=require("nw/executor")
local C=require("nw/compiler")
local Live=require("nw/entity_limits")
local Limits=require("nw/spell_limits")
DEGREES=math.pi/180;FRAMES=1/30
GetTime=function() return 0 end
local shots={}
local owner={userid="KU_owner",GUID=1,IsValid=function() return true end,components={},
    Transform={GetWorldPosition=function() return 0,0,0 end}}
SpawnPrefab=function(name)
    local e={valid=true,events={},prefab=name}
    function e:IsValid() return self.valid end
    function e:ListenForEvent(event,fn) self.events[event]=self.events[event] or {};table.insert(self.events[event],fn) end
    function e:Remove()
        if not self.valid then return end
        self.valid=false
        for _,fn in ipairs(self.events.onremove or {}) do fn(self) end
    end
    function e:Launch(_,p,_,_,_,_,cleanup)
        self.p=p;self._shot={};self:ListenForEvent("onremove",cleanup)
        if p.kind=="field" then cleanup() end -- saved placements release old projectile bookkeeping immediately
    end
    shots[#shots+1]=e;return e
end
local function wand(ids)
    local w=require("nw/generator").starter();w.cards={};w.stats.mana_max=10000
    for i,id in ipairs(ids) do w.cards[i]={card_uid=tostring(i),spell_id=id} end
    w.runtime=C.initial(w.cards,w.stats,71);return w
end
local function cast(ids)
    local p=assert(C.compile(wand(ids)))
    assert(E.execute(p,owner,0,0,1,0,1.4));return p
end
local function clear()
    for _,e in ipairs(shots) do e:Remove() end
    shots={};assert(E.stats()==0 and Live.stats("fields")==0 and Live.stats("permanent_fields")==0)
end
for _,cap in ipairs({25,50,100,200,300,400,500,600,700,800}) do
    E.set_projectile_limit(cap)
    local p=cast({"repeat_3","repeat_3","repeat_3","repeat_3","repeat_3","repeat_3","repeat_3","spark_hit","arrow"})
    assert(p.projectile_count==4374 and #shots==cap and E.stats()==cap)
    assert(shots[1]._shot.fire(0,0,1,0) and #shots==cap,"full payload consumes trigger without allocating")
    shots[cap]:Remove()
    assert(shots[1]._shot.fire(0,0,1,0) and #shots==cap+1 and E.stats()==cap)
    clear()
end
-- Huge compact repeats saturate in O(cap) attempts, without expanding rejected copies.
E.set_projectile_limit(25)
local p={projectile_count=1e12,next_state={rng_state=1},blocks={{copies=1e12,projectiles={
    {id="spark",kind="projectile",flags={},spread=0}}}}}
assert(E.execute(p,owner,0,0,1,0) and #shots==25);clear()
-- A fresh identity for the same user cannot reset live ownership accounting.
cast({"repeat_3","repeat_3","repeat_3","spark"})
local other={userid="KU_owner",GUID=2}
assert(E.execute(assert(C.compile(wand({"spark"}))),other,0,0,1,0) and #shots==25)
local Effects=require("nw/spell_effects")
local oldblast,blasts=Effects.blast,0
Effects.blast=function() blasts=blasts+1 end
assert(E.execute({projectile_count=1,next_state={rng_state=1},blocks={{projectiles={
    {id="explosion",kind="instant",flags={},spread=0}}}}},owner,0,0,1,0))
assert(blasts==1 and #shots==25 and E.stats()==25,"instant actions and burst effects have no new projectile cap")
Effects.blast=oldblast
E.set_projectile_limit(0);clear()
-- Depth is checked when a child fires, including changes after the carrier launched.
Limits.depth=1
cast({"spark_hit","spark_hit","arrow"})
assert(#shots==1 and shots[1]._shot.fire(0,0,1,0) and #shots==2)
assert(shots[2]._shot.fire(0,0,1,0) and #shots==2)
Limits.depth=2;assert(shots[2]._shot.fire(0,0,1,0) and #shots==3)
clear();Limits.depth=0
-- Independent shared pools prevent stationary fields from starving projectiles.
Live.configure("fields",25);E.set_projectile_limit(25)
cast({"repeat_3","repeat_3","repeat_3","spore_sentry"})
assert(#shots==25 and Live.owner_used(owner,"fields")==25 and E.stats()==0)
local first=shots[1]
cast({"spore_sentry"});assert(#shots==25 and first.valid)
cast({"spark"});assert(#shots==26 and E.stats()==1)
first:Remove();cast({"storm_cloud"});assert(#shots==27 and Live.stats("fields")==25)
local oldfx=Effects.fx
Effects.fx=function() error("full field pool must skip before creating a lingering light") end
Effects.afterlight(owner,0,0)
shots[2]:Remove();Effects.fx=function() return SpawnPrefab("nw_afterlight") end
Effects.afterlight(owner,0,0)
assert(#shots==28 and Live.stats("fields")==25,"lingering lights share the field quota")
Effects.fx=oldfx
clear();Live.configure("fields",0);E.set_projectile_limit(0)
-- The actual wand component commits costs even if all its emissions are skipped.
Class=function(ctor) local t={};t.__index=t;return setmetatable(t,{__call=function(_,...) local o=setmetatable({},t);ctor(o,...);return o end}) end
EQUIPSLOTS={HANDS="hands"}
local function net() return {set=function(self,v) self.v=v end,value=function(self) return self.v end} end
local inst={_nw_capacity=net(),_nw_mana=net(),_nw_ready=net(),components={},AddTag=function() end,RemoveTag=function() end}
local component=require("components/nw_wand")(inst);inst.components.nw_wand=component;component:InitializePrototype()
owner.components.inventory={GetEquippedItem=function() return inst end}
owner.components.health={IsDead=function() return false end}
package.loaded["nw/muzzle"]={origin=function() return 0,1.4,0 end}
E.set_projectile_limit(25);cast({"repeat_3","repeat_3","repeat_3","spark"})
component.data=wand({"spark"});component.data.config_revision=1
local mana=component.data.runtime.mana
local ready,_,prepared=component:CanCast(owner);assert(ready)
assert(component:Cast(owner,{x=5,z=0},prepared))
assert(#shots==25 and component.data.runtime.mana==mana-prepared.mana_spent)
assert(component.data.runtime.remaining_cast>0 and component.data.runtime==prepared.next_state)
clear();E.set_projectile_limit(0)
print("emission limits: every numeric tier, partial/full suppression, live payload replay, trillion-copy bounded work, stable owners, runtime depth, shared fields and real wand cost commit")
