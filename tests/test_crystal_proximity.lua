-- Real compiler, persistence, scan, targeting and blast dispatch; only engine
-- entities, field visuals/motion and final damage application are simulated.
local now,guid=0,0
GetTime=function() return now end
TheWorld={events={}}
AllPlayers={}
package.loaded["nw/field_motion"]={start=function() return true end}
package.loaded["nw/field_stages"]={start=function() end,finish=function() end}
local Stored=require("nw/persistent_fields")
local Fields=require("nw/expanded_fields")
local Effects=require("nw/spell_effects")
local Target=require("nw/targeting")
local Copy=require("nw/util").copy
local candidates,hits,bursts={}, {},0
local function entity(tags,x)
    guid=guid+1
    local e={GUID=guid,valid=true,tags=tags or {},x=x or 0,z=0,components={},events={}}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return self.tags.INLIMBO or false end
    function e:IsAsleep() return self.asleep or false end
    function e:HasTag(tag) return self.tags[tag] or false end
    function e:GetDistanceSqToPoint(x,y,z) return (self.x-x)^2+(self.z-z)^2 end
    function e:ListenForEvent(name,fn,source)
        source=source or self;source.events[name]=source.events[name] or {}
        table.insert(source.events[name],fn)
    end
    function e:Remove()
        assert(self.valid,"only one removal per crystal")
        self.valid=false
        for _,fn in ipairs(self.events.onremove or {}) do fn(self) end
    end
    function e:DoPeriodicTask(period,fn,delay)
        assert(period==.15 and delay==0,"proximity starts immediately")
        self.sense=fn;return {Cancel=function() end}
    end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end}
    return e
end
local function creature(tags,x)
    tags._combat=true
    local e=entity(tags,x)
    e.components.health={IsDead=function() return e.dead or false end}
    e.components.combat={CanTarget=function() return true end,IsAlly=function() return false end}
    return e
end
-- Honor FindEntities tag and radius filters, rather than bypassing the real
-- scan: ordinary trees/rocks are discoverable only with an object selection.
TheSim={FindEntities=function(_,x,y,z,r,must,exclude,oneof)
    local found={}
    for _,e in ipairs(candidates) do
        local allowed=e.valid and e:GetDistanceSqToPoint(x,y,z)<=r*r
        for _,tag in ipairs(exclude or {}) do if e:HasTag(tag) then allowed=false end end
        local matches=not oneof
        for _,tag in ipairs(oneof or {}) do if e:HasTag(tag) then matches=true end end
        if allowed and matches then found[#found+1]=e end
    end
    return found
end}
Effects.fx=function(name)
    assert(name=="nw_crystal_burst_fx")
    bursts=bursts+1
    return {SetRadius=function() end}
end
require("nw/expanded_hits").impact=function(s,e) hits[#hits+1]=e end
local owner=creature({player=true},8);owner.userid="KU_placer";AllPlayers={owner}
local function compile(selectors)
    local wand=require("nw/generator").starter()
    wand.stats.mana_max=600;wand.cards={}
    for _,id in ipairs(selectors) do table.insert(wand.cards,{spell_id=id,card_uid=tostring(#wand.cards+1)}) end
    table.insert(wand.cards,{spell_id="crystal_mine",card_uid="mine"})
    local Compiler=require("nw/compiler")
    wand.runtime=Compiler.initial(wand.cards,wand.stats,4)
    return assert(Compiler.compile(wand)).blocks[1].projectiles[1]
end
local function place(selectors)
    local e=entity({nw_breakable=true,_combat=true})
    Stored.install(e);Stored.launch(e,owner,compile(selectors),1,0,0)
    return e
end
local function sense(e,list)
    now=now+.15;candidates=list;hits={}
    local before=bursts;e.sense()
    return bursts-before
end
local tree=entity({tree=true,CHOP_workable=true},1)
local rock=entity({MINE_workable=true},1)
rock.components.workable={GetWorkAction=function() return {id="MINE"} end}
local alone=place({"target_building"})
alone.tags.nw_spell_placement=true
assert(sense(alone,{alone})==0 and alone.valid,"a placement is never its own proximity target")
local neighbour=entity({nw_spell_placement=true},1)
neighbour._nw_stored={p={id="crystal_mine"}}
assert(sense(alone,{alone,neighbour})==1 and not alone.valid,"another building placement is discoverable without combat tags")
assert(Target.allowed(owner,tree,{targets={nature=true}}))
assert(Target.selected_object(owner,tree,{targets={nature=true}}))
for _,target in ipairs({tree,rock}) do
    local mine=place({"target_nature"})
    assert(sense(mine,{target})==1 and not mine.valid,"nature-only mine must sense a nearby tree/rock without health or combat")
    assert(hits[1]==target and #hits==1,"detonation dispatch reaches the selected natural object")
    mine._nw_break();assert(sense(mine,{target})==0,"stale callbacks cannot detonate twice")
end
local monster=creature({hostile=true},1)
local neutral=creature({},1)
local pet=creature({},1);pet.components.follower={leader=owner}
local wall=entity({structure=true},1)
local other=creature({player=true},1)
local function check(selectors,target,expected)
    local mine=place(selectors)
    assert(sense(mine,{target})==expected,"target-selection regression")
    if mine.valid then mine:Remove() end
end
check({"target_nature"},monster,0)
check({"target_nature"},wall,0)
check({"target_nature","target_hostile"},monster,1)
check({"target_nature","target_hostile"},tree,1)
check({},monster,1);check({},neutral,1)
check({},tree,0);check({},pet,0);check({},other,0)
check({"target_hostile"},tree,0);check({"target_hostile"},neutral,0)
check({"target_building"},wall,1);check({"target_building"},tree,0)
check({"target_neutral"},neutral,1);check({"target_friendly"},pet,1)
check({"target_players_other"},other,1)
owner.x=1;check({"target_self"},owner,1);owner.x=8
-- Broad-phase cells include things outside the exact crystal radius.
local mine=place({"target_nature"})
tree.x=mine._nw_stored.p.radius+.01;assert(sense(mine,{tree})==0)
tree.x=mine._nw_stored.p.radius;assert(sense(mine,{tree})==1);tree.x=1
for _,tag in ipairs({"INLIMBO","FX","nw_decoy","playerghost"}) do
    tree.tags[tag]=true;check({"target_nature"},tree,0);tree.tags[tag]=nil
end
tree.components.health={IsDead=function() return true end}
check({"target_nature"},tree,0);tree.components.health=nil
-- Owner availability and sleeping still pause autonomous activation; saved
-- selections resume against the reconnected player without a schema change.
mine=place({"target_nature"})
mine.asleep=true;assert(sense(mine,{tree})==0);mine.asleep=false
owner.tags.playerghost=true;assert(sense(mine,{tree})==0);owner.tags.playerghost=nil
owner.dead=true;assert(sense(mine,{tree})==0);owner.dead=false
AllPlayers={};assert(sense(mine,{tree})==0)
local save={};mine.OnSave(mine,save);mine:Remove();owner.valid=false
owner=creature({player=true},8);owner.userid="KU_placer";AllPlayers={owner}
local restored=entity({nw_breakable=true,_combat=true})
Stored.install(restored);restored.OnLoad(restored,Copy(save))
assert(restored._nw_owner==owner and restored._nw_stored.p.flags.targets.nature)
assert(sense(restored,{tree})==1 and not restored.valid,"restored nature selection resumes after reconnect")
print("crystal proximity: natural objects, selector union/defaults, exact radius, validity, owner pause and save/load")
