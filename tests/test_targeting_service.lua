local Target=require("nw/targeting")
local guid=0
local function entity(tags)
    guid=guid+1
    local e={GUID=guid,tags=tags or {},components={},valid=true,x=0,z=0}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return self.limbo or false end
    function e:HasTag(tag) return self.tags[tag] or false end
    function e:GetDistanceSqToPoint(x,y,z) return (self.x-x)^2+(self.z-z)^2 end
    return e
end
local function creature(tags)
    local e=entity(tags)
    e.components.health={IsDead=function() return e.dead or false end}
    e.components.combat={IsAlly=function(_,other) return other.ally end,
        CanTarget=function(_,other) return not other.untargetable end}
    return e
end
local owner=creature({player=true})
local other=creature({player=true})
local hostile=creature({hostile=true})
local neutral=creature({})
local pet=creature({});pet.components.follower={leader=owner}
local ally=creature({});ally.ally=true
local tree=entity({tree=true})
local rock=entity({MINE_workable=true})
rock.components.workable={GetWorkAction=function() return {id="MINE"} end}
local wall=entity({wall=true})
local boat=entity({boat=true,walkableplatform=true})
boat.components.health={IsDead=function() return false end}
boat.components.hullhealth={};boat.components.boatphysics={};boat.components.walkableplatform={}
assert(Target.selected(owner,boat,{targets={building=true}}) and not boat.components.combat)
assert(not Target.selected(owner,boat,{targets={nature=true}}))
for _,component in ipairs({"hullhealth","boatphysics","walkableplatform"}) do
    local platform=entity({});platform.components[component]={}
    assert(Target.object(platform)=="building")
end
local categories={self=owner,players_other=other,hostile=hostile,neutral=neutral,friendly=pet,nature=tree,building=wall}
-- Every selector replaces the default set and rejects the other six classes.
for category,target in pairs(categories) do
    local flags={targets={[category]=true}}
    for other_category,other_target in pairs(categories) do
        assert((Target.selected(owner,other_target,flags) and true or false)==(category==other_category),category.." vs "..other_category)
    end
    assert(Target.accepts(owner,target,flags))
end
assert(Target.selected(owner,ally,{targets={friendly=true}}))
assert(Target.selected(owner,rock,{targets={nature=true}}))
assert(Target.selected(owner,hostile,{}) and Target.selected(owner,neutral,{}))
for _,e in ipairs({owner,other,pet,ally,tree,wall}) do assert(not Target.selected(owner,e,{})) end
local union={targets={nature=true,hostile=true}}
assert(Target.selected(owner,tree,union) and Target.selected(owner,hostile,union))
assert(not Target.selected(owner,neutral,union) and not Target.selected(owner,tree,{targets={}}))
assert(Target.scope_key(union)==Target.scope_key({targets={hostile=true,nature=true}}))
assert(Target.scope_key({})=="default" and Target.scope_key({targets={}})~="default")
assert(Target.allows_category({},"nature") and not Target.allows_category(union,"building"))
-- Explicit categories do not inherit the caster's ordinary combat eligibility.
hostile.untargetable=true
assert(Target.selected(owner,hostile,{targets={hostile=true}}))
assert(not Target.selected(owner,hostile,{}))
assert(Target.accepts(owner,hostile,{targets={hostile=true}},{default=true}))
hostile.untargetable=nil
assert(Target.allowed(owner,tree,union) and Target.hittable(owner,tree,union))
assert(not Target.accepts(owner,tree,union,{components={"combat","health"}}))
assert(Target.accepts(owner,rock,{}, {default=true,components={"workable"}}))
assert(Target.accepts(owner,rock,{targets={nature=true}}, {default=true,components={"workable"}}))
assert(not Target.accepts(owner,rock,{targets={hostile=true}}, {default=true,components={"workable"}}))
assert(not Target.accepts(owner,tree,union,{predicate=function(caster,e) assert(caster==owner and e==tree);return false end}))
for _,tag in ipairs({"FX","playerghost","nw_decoy"}) do
    tree.tags[tag]=true;assert(not Target.selected(owner,tree,union));tree.tags[tag]=nil
end
tree.limbo=true;assert(not Target.selected(owner,tree,union));tree.limbo=false
tree.valid=false;assert(not Target.selected(owner,tree,union));tree.valid=true
hostile.dead=true;assert(not Target.selected(owner,hostile,union));hostile.dead=false
owner.dead=true;assert(not Target.selected(owner,tree,union));owner.dead=false
-- The public physical-prop policy is shared by contact/beam/melee consumers.
local breaks=0
local function prop(id,placer)
    local e=entity({nw_breakable=true})
    e._nw_break=function() breaks=breaks+1 end
    e._nw_stored={p={id=id}};e._nw_owner=placer
    return e
end
TheWorld={};AllPlayers={}
for _,id in ipairs({"payload_egg","sleep_crystal"}) do
    local e=prop(id,other)
    assert(not Target.selectable_prop(owner,e,{targets={nature=true}}))
    assert(not Target.accepts(owner,e,{targets={nature=true}},{breakables=true,components={"health","combat"}}))
    assert(Target.selectable_prop(owner,e,{targets={building=true}}))
    assert(Target.accepts(owner,e,{targets={building=true}},{breakables=true}))
    assert(not Target.selected(owner,e,{}))
end
local mine=prop("crystal_mine",owner)
assert(Target.selectable_prop(owner,mine,{}) and Target.selectable_prop(owner,mine,{targets={building=true}}))
assert(Target.selectable_prop(other,mine,{}) and not Target.selectable_prop(owner,mine,union))
assert(breaks==0,"selection never performs the break action")
local function contains(tags,want) for _,tag in ipairs(tags) do if tag==want then return true end end return false end
assert(not contains(Target.scan_tags({}),"tree"))
assert(contains(Target.scan_tags(union),"tree") and contains(Target.scan_tags({},true),"MINE_workable"))
assert(contains(Target.scan_tags({targets={building=true}}),"boat"))
assert(contains(Target.scan_tags({targets={building=true}}),"walkableplatform"))
assert(Target.scan_exclude==Target.scan_exclude and contains(Target.scan_exclude,"FX"))
local fragile=entity({hostile=true})
fragile.components.freezable={}
assert(Target.accepts(owner,fragile,{targets={hostile=true}},{components={"freezable"}}))
assert(not Target.accepts(owner,fragile,{targets={hostile=true}},{components={"health"}}))
assert(not Target.accepts(owner,fragile,{targets={hostile=true}},{exclude=fragile}))
local item=entity({});item.components.inventoryitem={};item.components.cookable={}
assert(not Target.matches(owner,item,{neutral=true,nature=true,building=true}))
local original={flags={targets={hostile=true},freeze=1}}
local later=Target.flags(original,"aftermath")
assert(later._nw_target_bypass and not later.targets and original.flags.targets.hostile)
assert(Target.selected(nil,tree,later) and Target.selected(owner,other,later))
for _,key in ipairs({"farm_hoe","fishingrod","oceanfishingrod","voidcloth_scythe","shieldofterror"}) do
    local p={engraving=key,flags=original.flags}
    assert(not Target.flags(p).targets and not Target.flags(p)._nw_target_bypass)
end
assert(not Target.flags({id="detonate",flags=original.flags}).targets)
-- Query shares broad-phase caching but owns exact distance and policy filters.
local seen_flags,force
require("nw/spell_effects").scan=function(x,z,r,flags,objects) seen_flags=flags;force=objects;return {tree,rock,hostile,neutral} end
tree.x=1;rock.x=3;hostile.x=2;neutral.x=1
local found=Target.query(owner,0,0,2,union,{force_objects=true})
assert(#found==2 and found[1]==tree and found[2]==hostile and seen_flags==union and force)
tree.valid=false
tree.GetDistanceSqToPoint=function() error("removed cached entities must be rejected before reading their transform") end
found=Target.query(owner,0,0,2,union)
assert(#found==1 and found[1]==hostile)
-- Compilation continues to serialize only a category set, not runtime rules.
local Compiler=require("nw/compiler")
local function cast(ids)
    local w=require("nw/generator").starter();w.stats.mana_max=600;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=Compiler.initial(w.cards,w.stats,4)
    return assert(Compiler.compile(w))
end
local plan=cast({"target_nature","target_hostile","arrow_hit","spark"})
local parent=plan.blocks[1].projectiles[1]
assert(parent.flags.targets.nature and parent.flags.targets.hostile)
assert(not plan.blocks[parent.payload].projectiles[1].flags.targets)
local copy=require("nw/util").copy(parent.flags)
assert(Target.scope_key(copy)==Target.scope_key(parent.flags))
for key,value in pairs(copy.targets) do assert(type(key)=="string" and type(value)=="boolean") end
print("targeting service: seven selectors, defaults/unions, capabilities, props, scan/query, validity and serialized scopes")
