-- Region coverage, trail geometry and lifetime are exercised separately from AI.
local time=0
GetTime=function() return time end
local calls={}
package.loaded["nw/dark_fog_control"]={
    classify=function(e) return not e:HasTag("player") and e.creature and "normal" or nil end,
    update=function(e,_,inside) e.covered=inside;calls[#calls+1]={e,inside} end,
    leave=function(e) if e.covered then e.exits=(e.exits or 0)+1 end;e.covered=false end,
}
local all,tasks={},{}
local function entity(x,z)
    local e={x=x or 0,z=z or 0,events={},tags={},components={}}
    function e:IsValid() return not self.removed end
    function e:HasTag(t) return self.tags[t] or false end
    function e:IsInLimbo() return self.tags.INLIMBO end
    function e:IsAsleep() return self.sleeping or false end
    function e:ListenForEvent(event,fn) local a=self.events[event] or {};self.events[event]=a;a[#a+1]=fn end
    function e:RemoveEventCallback(event,fn) for i,f in ipairs(self.events[event] or {}) do if f==fn then table.remove(self.events[event],i);break end end end
    function e:PushEvent(event) local a={};for _,fn in ipairs(self.events[event] or {}) do a[#a+1]=fn end;for _,fn in ipairs(a) do fn(self) end end
    function e:Remove() if self.removed then return end;self.removed=true;self:PushEvent("onremove") end
    function e:DoTaskInTime(delay,fn)
        local task={at=time+delay,fn=function() if self:IsValid() then fn(self) end end}
        function task:Cancel() self.cancelled=true end
        tasks[#tasks+1]=task;return task
    end
    function e:DoPeriodicTask(_,fn) return {fn=fn,Cancel=function(self) self.cancelled=true end} end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,SetPosition=function(_,x,_,z) e.x,e.z=x,z end}
    e._nw_dark_dissipating={set=function(_,v) e.fade=v end}
    e._nw_dark_radius={set=function(_,v) e.fog_radius=v end}
    all[#all+1]=e;return e
end
local function advance(t)
    time=t
    local due={};for _,task in ipairs(tasks) do if not task.cancelled and task.at<=time then task.cancelled=true;due[#due+1]=task end end
    for _,task in ipairs(due) do task.fn() end
end
TheWorld=entity();TheWorld.ismastersim=true
TheSim={FindEntities=function(_,x,_,z,radius)
    local found={};for _,e in ipairs(all) do if e:IsValid() and (e.x-x)^2+(e.z-z)^2<=radius^2 then found[#found+1]=e end end;return found
end}
SpawnPrefab=function(name) assert(name=="nw_dark_fog");return entity() end
local Fog=require("nw/dark_fog")
local owner={userid="caster"}
-- Compatibility mode retains networked, scaled visual trails and expiry,
-- without scanning creatures, applying control or installing shared boss hooks.
local original_boss=package.loaded["nw/dark_fog_boss"]
local hook_installs=0
package.loaded["nw/dark_fog_boss"]={install=function() hook_installs=hook_installs+1 end}
local disabled=true
local settings={GetModConfigData=function(name) assert(name=="disable_dark_fog");return disabled end}
Fog.install(settings)
local untouched=entity()
local fog_count=#all
local dark={flags={dark=true},size_mult=2}
local visual=assert(Fog.leave(owner,0,0,dark))
Fog.attach(untouched,owner,dark)
Fog.trail(untouched,{owner=owner,p=dark},0,0,8,0,true)
local direct=entity(30,0)
assert(Fog.register(direct,owner,3,dark)==direct)
assert(#all>fog_count and TheWorld._nw_dark_fog and untouched._nw_dark_trail and hook_installs==0)
assert(visual.fog_radius==4 and direct.fog_radius==4 and not TheWorld._nw_dark_fog.task)
local find=TheSim.FindEntities
TheSim.FindEntities=function() error("visual-only fog must not scan creatures") end
Fog.refresh(TheWorld)
assert(#calls==0 and not Fog.contains(TheWorld,untouched))
assert(require("nw/entity_limits").stats("fields")>0,"visual entities keep their normal budget")
advance(5.01)
assert(visual.fade and direct.fade and not TheWorld._nw_dark_fog and #calls==0)
advance(5.7)
assert(visual.removed and direct.removed and require("nw/entity_limits").stats("fields")==0)
TheSim.FindEntities=find;time=0
disabled=false;Fog.install(settings)
assert(hook_installs==1 and not Fog.effects_disabled,"default retains fog and native boss support")
package.loaded["nw/dark_fog_boss"]=original_boss
local mob=entity(1,0);mob.creature=true
local player=entity(1,0);player.tags.player=true;player.creature=true
local a=Fog.leave(owner,0,0);local b=Fog.leave(owner,2,0)
assert(a and b and a~=b)
Fog.refresh(TheWorld)
assert(mob.covered and not player.covered and not Fog.contains(TheWorld,player))
assert(Fog.contains(TheWorld,mob))
local rec=TheWorld._nw_dark_fog.sources[a]
assert(rec.expires>=3 and rec.expires<=5)
assert(rec.radius==2 and a.fog_radius==2,"old callers retain the default radius")
Fog.dissipate(a)
assert(a.fade and not a.removed and mob.covered and not mob.exits)
assert(not Fog.dissipate(a),"fade begins once")
Fog.dissipate(b)
assert(not mob.covered and mob.exits==1 and TheWorld._nw_dark_fog==nil)
assert(#TheWorld.events.onremove==0,"finished pools must release world callbacks")
advance(.7);assert(a.removed and b.removed)
-- Annulus intersection excludes clouds wholly inside its inner hole.
local centre=Fog.leave(owner,0,0);local edge=Fog.leave(owner,5,0)
assert(Fog.disperse_circle(TheWorld,0,0,6,3)==1 and edge.fade and not centre.fade)
Fog.dissipate(centre)
-- Same owner/cell merges without extending an existing lifetime.
local c=Fog.leave(owner,20,20);local expiry=TheWorld._nw_dark_fog.sources[c].expires
assert(Fog.leave(owner,20.1,20.1)==c and TheWorld._nw_dark_fog.sources[c].expires==expiry)
advance(expiry+.001);assert(c.fade and not TheWorld._nw_dark_fog)
advance(expiry+1);assert(c.removed)
-- Sleep removes coverage; waking inside an active cloud reacquires it.
local cloud=Fog.leave(owner,0,0);Fog.refresh(TheWorld);assert(mob.covered)
mob.sleeping=true;Fog.refresh(TheWorld);assert(not mob.covered)
mob.sleeping=false;Fog.refresh(TheWorld);assert(mob.covered)
cloud:Remove();assert(not mob.covered and not TheWorld._nw_dark_fog)
-- Actual radii drive coverage, broad-phase scans, networking and cleanup.
local giant={size_mult=5,flags={dark=true}}
local tiny={size_mult=.1,flags={dark=true}}
local large=Fog.register(entity(-.1,-.1),owner,4,giant)
local small=Fog.register(entity(-.1,-.1),owner,4,tiny)
local far=entity(9.8,-.1);far.creature=true -- more than one centre cell away
local outside=entity(10,-.1);outside.creature=true
local near=entity(-.1,.09);near.creature=true
local past_small=entity(-.1,.11);past_small.creature=true
local pool=TheWorld._nw_dark_fog
assert(pool.sources[large].radius==10 and large.fog_radius==10 and small.fog_radius==.2)
assert(pool.large[large] and not pool.large[small] and pool.cells["-1:-1"].radius==10)
local cell_count=0;for _ in pairs(pool.cells) do cell_count=cell_count+1 end
assert(cell_count==1,"giant clouds do not allocate grid cells for their entire area")
Fog.refresh(TheWorld)
assert(far.covered and Fog.contains(TheWorld,far) and not outside.covered and not Fog.contains(TheWorld,outside))
Fog.dissipate(large)
assert(not pool.large[large] and pool.cells["-1:-1"].radius==.2)
assert(not far.covered and not Fog.contains(TheWorld,far) and near.covered and not past_small.covered)
assert(Fog.contains(TheWorld,near) and not Fog.contains(TheWorld,past_small))
small:Remove();assert(not TheWorld._nw_dark_fog and not near.covered)
-- Large/small disks intersect a boss annulus using their own radii.
large=Fog.register(entity(0,0),owner,4,giant)
small=Fog.register(entity(0,0),owner,4,tiny)
local outer_small=Fog.register(entity(6.3,0),owner,4,tiny)
local outer_large=Fog.register(entity(15.9,0),owner,4,giant)
assert(Fog.disperse_circle(TheWorld,0,0,6,3)==2 and large.fade and outer_large.fade)
assert(not small.fade and not outer_small.fade,"small clouds wholly in hole or beyond outer edge survive")
Fog.dissipate(small);Fog.dissipate(outer_small)
-- Same-position sizes never swallow one another; small buckets preserve samples.
-- A front attack is a sector, including cloud-disk overlap at each boundary.
local front=Fog.register(entity(3,0),owner,4,tiny)
local behind=Fog.register(entity(-1,0),owner,4,tiny)
local side=Fog.register(entity(-.1,2),owner,4,tiny)
local far_side=Fog.register(entity(-.3,2),owner,4,tiny)
local edge=Fog.register(entity(4.1,0),owner,4,tiny)
assert(Fog.disperse_sector(TheWorld,0,0,4,0,180)==3)
assert(front.fade and side.fade and edge.fade and not behind.fade and not far_side.fade)
Fog.dissipate(behind);Fog.dissipate(far_side)
local forward_z=Fog.register(entity(0,-3),owner,4,tiny)
local backward_z=Fog.register(entity(0,3),owner,4,tiny)
assert(Fog.disperse_sector(TheWorld,0,0,4,90,90)==1 and forward_z.fade and not backward_z.fade)
Fog.dissipate(backward_z)
-- Native 240-degree "arc" is a clipped disk, not an angular sector: it also
-- hits the near rear centre, but not the part behind the cutoff plane.
local rear_flank=Fog.register(entity(-.5,0),owner,4,tiny)
local rear_gap=Fog.register(entity(-2,0),owner,4,tiny)
local arc_edge=Fog.register(entity(-1.35,0),owner,4,tiny)
assert(Fog.disperse_arc(TheWorld,1,0,4.5,0,240)==2)
assert(rear_flank.fade and arc_edge.fade and not rear_gap.fade)
Fog.dissipate(rear_gap)
local rotated=Fog.register(entity(0,1.5),owner,4,tiny)
local rotated_gap=Fog.register(entity(0,3),owner,4,tiny)
assert(Fog.disperse_arc(TheWorld,0,0,4.5,90,240)==1 and rotated.fade and not rotated_gap.fade)
Fog.dissipate(rotated_gap)
-- Square fissure corners must survive a radius-2 circle approximation, while
-- points outside the square must not be cleared by its larger bounding circle.
local corner=Fog.register(entity(1.9,1.9),owner,4,tiny)
local outside=Fog.register(entity(2.5,0),owner,4,tiny)
local corner_edge=Fog.register(entity(2.1,2.1),owner,4,tiny)
assert(Fog.disperse_box(TheWorld,0,0,2,2)==2 and corner.fade and corner_edge.fade and not outside.fade)
Fog.dissipate(outside)
-- Body movement clears its swept capsule, not only the final disk, and each
-- cloud's scaled radius participates in the intersection.
local middle=Fog.register(entity(5,.6),owner,4,tiny)
local missed=Fog.register(entity(5,.8),owner,4,tiny)
local start=Fog.register(entity(-.6,0),owner,4,tiny)
local endcap=Fog.register(entity(10.6,0),owner,4,tiny)
assert(Fog.disperse_path(TheWorld,0,0,10,0,.5)==3)
assert(middle.fade and start.fade and endcap.fade and not missed.fade)
assert(Fog.disperse_path(TheWorld,5,.8,5,.8,0)==1 and missed.fade)
assert(not TheWorld._nw_dark_fog)
-- Same-position sizes never swallow one another; small buckets preserve samples.
local normal=Fog.leave(owner,20,20)
small=Fog.leave(owner,20,20,tiny);large=Fog.leave(owner,20,20,giant)
local adjacent=Fog.leave(owner,20.2,20,tiny)
assert(normal~=small and small~=large and normal~=large and adjacent~=small)
assert(Fog.leave(owner,20,20,tiny)==small and Fog.leave(owner,20,20,giant)==large)
Fog.dissipate(normal);Fog.dissipate(small);Fog.dissipate(large);Fog.dissipate(adjacent)
assert(not TheWorld._nw_dark_fog)
-- Trail sampling follows short segments, not the discarded forward endpoint.
local real_leave=Fog.leave;local points={}
Fog.leave=function(_,x,z,p) points[#points+1]={x,z,p};return true end
local projectile=entity();local shot={owner=owner,p={flags={dark=true}}}
Fog.attach(projectile,owner,shot.p)
Fog.trail(projectile,shot,0,0,.6,0)
Fog.trail(projectile,shot,.6,0,2.4,0)
Fog.trail(projectile,shot,2.4,0,2.4,1.6)
assert(#points==2)
assert(math.abs(points[2][1]-2.4)<1e-6 and math.abs(points[2][2]-.4)<1e-6)
Fog.trail(projectile,shot,2.4,1.6,100,100)
assert(#points==3 and points[3][1]==100,"teleports never paint intervening space")
assert(points[1][3]==shot.p and points[3][3]==shot.p,"attach and teleport preserve payload size")
points={};projectile=entity();shot.p=tiny
Fog.attach(projectile,owner,shot.p)
Fog.trail(projectile,shot,0,0,.35,0)
Fog.trail(projectile,shot,.35,0,1,0)
assert(#points==4 and math.abs(points[4][1]-.84)<1e-6)
for i=2,#points do assert(math.abs(points[i][1]-points[i-1][1]-.28)<1e-6 and points[i][3]==tiny) end
points={};projectile=entity();shot.p=giant
Fog.trail(projectile,shot,0,0,20,0,true)
assert(#points==2 and points[2][1]==14,"giant clouds retain 30% diameter overlap")
points={};projectile=entity()
Fog.leave=function(_,x,z,p) points[#points+1]={x,z,p};if #points<=5 then return true end end
Fog.trail(projectile,shot,0,0,100000000,0,true)
assert(#points==6,"long continuous paths stop sampling when the shared creation budget refuses")
Fog.leave=real_leave
-- Real tiny trail samples cannot be lost to spatial merging.
projectile=entity();shot.p=tiny
Fog.attach(projectile,owner,tiny);Fog.trail(projectile,shot,0,0,1,0)
pool=TheWorld._nw_dark_fog;assert(pool.count==4)
local probe=entity()
for i=0,100 do probe.x=i/100;assert(Fog.contains(TheWorld,probe),"tiny trail has a coverage gap") end
local pending={};for source in pairs(pool.sources) do pending[#pending+1]=source end
for _,source in ipairs(pending) do Fog.dissipate(source) end
assert(not TheWorld._nw_dark_fog)
-- Huge real paths still obey the existing per-window spawn cap and clean up.
projectile=entity();shot.p=giant
Fog.trail(projectile,shot,0,0,100000000,0,true)
pool=TheWorld._nw_dark_fog;assert(pool.count==16 and pool.spawn_owners.caster==16)
pending={};for source in pairs(pool.sources) do pending[#pending+1]=source end
for _,source in ipairs(pending) do Fog.dissipate(source) end
assert(not TheWorld._nw_dark_fog and require("nw/entity_limits").stats("fields")==0)
-- Per-owner caps retire oldest regions; retirement has no player side effects.
local cap=Fog.per_owner;Fog.per_owner=2
local first=Fog.register(entity(30,0),owner,3)
Fog.register(entity(33,0),owner,4);Fog.register(entity(36,0),owner,5)
assert(first.fade and TheWorld._nw_dark_fog.count==2)
Fog.per_owner=cap
TheWorld:PushEvent("onremove");assert(not TheWorld._nw_dark_fog)
-- Card identity and recipes remain compatible with existing decks/saves.
local D=require("nw/definitions");local Cards=require("nw/cards")
assert(D.spells.dark.radius==2 and D.spells.dark.duration_min==3 and D.spells.dark.duration==5 and Cards.codes.dark==224)
assert(require("nw/card_rarity").tiers.dark==2 and require("nw/acquisition").by_name.nw_inscribe_dark)
local w=require("nw/generator").starter();w.cards={{spell_id="dark",card_uid="d"},{spell_id="spark",card_uid="s"}}
w.runtime=require("nw/compiler").initial(w.cards,w.stats,1)
assert(require("nw/compiler").compile(w).blocks[1].projectiles[1].flags.dark)
-- Scope does not split or limit this environmental aftermath.
local caster=entity(100,100);caster.tags.player=true;caster.userid="scoped"
caster.components.combat={IsAlly=function() return false end,CanTarget=function() return true end}
local enemy=entity(100,100);enemy.creature=true;enemy.tags.hostile=true
enemy.components.health={IsDead=function() return false end};enemy.components.combat={}
local friend=entity(100,100);friend.creature=true
friend.components.health={IsDead=function() return false end};friend.components.combat={}
friend.components.follower={leader=caster}
local excluded=entity(100,100);excluded.creature=true;excluded.tags.player=true
excluded.components.health={IsDead=function() return false end};excluded.components.combat={}
local hostile_flags={targets={hostile=true},dark=true}
local hostile_fog=Fog.leave(caster,100,100,{flags=hostile_flags})
local friendly_fog=Fog.leave(caster,100,100,{flags={targets={friendly=true},dark=true}})
assert(hostile_fog==friendly_fog and TheWorld._nw_dark_fog.count==1)
assert(Fog.leave(caster,100,100,{flags={targets={hostile=true},dark=true}})==hostile_fog)
hostile_flags.targets.hostile=nil;hostile_flags.targets.neutral=true
Fog.refresh(TheWorld)
assert(enemy.covered and friend.covered and not excluded.covered)
assert(Fog.contains(TheWorld,enemy) and Fog.contains(TheWorld,friend))
Fog.dissipate(hostile_fog)
assert(not enemy.covered and not friend.covered and not TheWorld._nw_dark_fog)
local only_players=Fog.leave(caster,100,100,{flags={targets={self=true,players_other=true}}})
Fog.refresh(TheWorld)
assert(enemy.covered and friend.covered and not excluded.covered)
Fog.dissipate(only_players)
print("dark fog regions: scaled coverage/network radius, cross-cell queries, annuli, size-aware merge, tiny/long trails, budgets, cleanup and compatibility passed")
