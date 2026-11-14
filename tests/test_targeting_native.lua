local Target=require("nw/targeting")
local Native=require("nw/native_targeting")
local Giant=require("nw/giant_native")
local Fire=require("nw/engraved_fire")
local noop=function() end
FRAMES=1/30;DEGREES=math.pi/180
TUNING={TORNADO_DAMAGE=7,PVP_DAMAGE_MOD=.5,SKILLS={}}
TheNet={GetPVPEnabled=function() return false end}
math.clamp=function(n,a,b) return math.max(a,math.min(b,n)) end
local seq=0
function native_test_entity(category)
    seq=seq+1
    local e={GUID=seq,prefab=category,components={},tags={fire=true,burnable=true},hits=0,cold=0,ignited=0,extinguished=0,worked=0,x=.5}
    e.IsValid=function(self) return not self.removed end
    e.IsInLimbo=function() return false end
    e.HasTag=function(self,tag) return self.tags[tag]==true end
    e.HasAnyTag=function(self,...) for _,tag in ipairs({...}) do if self:HasTag(tag) then return true end end;return false end
    e.HasOneOfTags=function(self,tags) return self:HasAnyTag(unpack(tags)) end
    e.Remove=function(self) self.removed=true end
    e.Transform={GetWorldPosition=function() return e.x,0,0 end,SetPosition=noop,GetRotation=function() return 0 end}
    e.GetPosition=function() return {x=e.x,y=0,z=0} end
    e.GetPhysicsRadius=function() return .1 end
    e.GetDistanceSqToPoint=function(self,x,y,z) return (self.x-x)^2+z*z end
    e.entity={IsVisible=function() return true end}
    e.components.burnable={canlight=true,Ignite=function() e.ignited=e.ignited+1 end,Extinguish=function() e.extinguished=e.extinguished+1 end}
    if category=="nature" or category=="building" then
        e.tags[category=="nature" and "tree" or "structure"]=true
        e.tags[category=="nature" and "CHOP_workable" or "HAMMER_workable"]=true
        e.components.workable={CanBeWorked=function() return true end,GetWorkAction=function() return {id=category=="nature" and "CHOP" or "HAMMER"} end,
            WorkedBy=function() e.worked=e.worked+1 end}
    else
        e.tags._combat=true;e.tags._health=true
        e.components.health={IsDead=function() return false end,currenthealth=1000}
        local c={inst=e,IsAlly=function(_,other) return other==e or other.prefab=="friendly" end,
            CanTarget=function() return true end,CanBeAttacked=function() return true end,SuggestTarget=noop}
        c.GetAttacked=function(_,a,n,w,s,sp)
            e.hits=e.hits+1;e.components.health.currenthealth=e.components.health.currenthealth-(n or 0)-(sp and sp.planar or 0)
            return true
        end
        c.CalcDamage=function(_,other,w) return w.components.weapon.damage,{planar=3} end
        c.DoAttack=function(self,other,w)
            local damage=w.components.weapon.damage
            if type(damage)=="function" then damage=damage(w,e,other) end
            return other.components.combat:GetAttacked(e,damage,w)
        end
        e.components.combat=c
        e.components.freezable={AddColdness=function(_,n) e.cold=e.cold+n end}
        Native.wrap_combat(c)
    end
    if category=="self" or category=="players_other" then e.tags.player=true;e.isplayer=true end
    if category=="hostile" then e.tags.hostile=true end
    return e
end
local categories={"self","players_other","friendly","hostile","neutral","nature","building"}
native_test_targets={}
for _,category in ipairs(categories) do native_test_targets[#native_test_targets+1]=native_test_entity(category) end
native_test_owner=native_test_targets[1]
native_test_targets[3].components.follower={leader=native_test_owner}
TheSim={FindEntities=function(_,x,y,z,r,must,exclude,one)
    local found={}
    for _,e in ipairs(native_test_targets) do
        local ok=e:GetDistanceSqToPoint(x,y,z)<=r*r
        for _,tag in ipairs(must or {}) do if not e:HasTag(tag) then ok=false end end
        for _,tag in ipairs(exclude or {}) do if e:HasTag(tag) then ok=false end end
        if one and not e:HasOneOfTags(one) then ok=false end
        if ok then found[#found+1]=e end
    end
    return found
end}
SpawnPrefab=function() return {Transform={SetPosition=noop},SetRadius=noop,PushFlash=noop} end
local function reset()
    for _,e in ipairs(native_test_targets) do e.hits=0;e.cold=0;e.ignited=0;e.extinguished=0;e.worked=0 end
end
local function spell(category,key)
    return {id="test",engraving=key,flags={targets={[category]=true}},damage=17}
end
-- All seven explicit scopes constrain the same environmental entry points;
-- no combat component is needed to extinguish or ignite selected scenery.
for _,category in ipairs(categories) do
    reset()
    local p=spell(category,"lighter")
    Fire.absorb(native_test_owner,0,0,1,0,3,p)
    Fire.burst({},native_test_owner,0,0,3,nil,p)
    for _,e in ipairs(native_test_targets) do
        local selected=e.prefab==category
        assert(e.extinguished==(selected and 1 or 0),category.." extinguish "..e.prefab)
        assert(e.hits==(selected and e:HasTag("player") and 1 or 0),category.." fire hit "..e.prefab)
        assert(e.ignited==(selected and not e:HasTag("player") and 1 or 0),category.." ignite "..e.prefab)
    end
end
reset();Fire.absorb(native_test_owner,0,0,1,0,3)
for _,e in ipairs(native_test_targets) do assert(e.extinguished==1,"native default extinguish") end

-- Native area continuations share a scope even after the controller is gone.
for _,category in ipairs(categories) do
    reset()
    local wind={prefab="tornado",WINDSTAFF_CASTER=native_test_owner,WINDSTAFF_CASTER_ISPLAYER=true,
        Transform=native_test_owner.Transform,_nw_giant=1,IsValid=function() return true end}
    Native.tag(wind,native_test_owner,spell(category,"staff_tornado"))
    Giant.tornado(wind)
    for _,e in ipairs(native_test_targets) do
        assert(e.hits==(e.prefab==category and e.components.combat and 1 or 0),category.." tornado damage "..e.prefab)
        assert(e.worked==(e.prefab==category and e.components.workable and 1 or 0),category.." tornado work "..e.prefab)
    end
    reset()
    local bell={prefab="dumbbell_bluegem",components={weapon={damage=34,OnAttack=noop}},
        Transform=native_test_owner.Transform,isiceattack=true}
    Native.tag(bell,native_test_owner,spell(category,"dumbbell_bluegem"))
    Giant.bell(bell,native_test_owner,1)
    for _,e in ipairs(native_test_targets) do
        local expected=e.prefab==category and e.components.combat and 1 or 0
        assert(e.hits==expected,category.." bell damage "..e.prefab)
        assert(e.cold==2*expected,category.." bell cold "..e.prefab)
    end
end

-- Context is copied at native handoff; ordinary native weapons, unrelated
-- player attacks and the documented indiscriminate explosions stay untouched.
local p=spell("hostile","trident")
local staff={prefab="trident"};Native.tag(staff,native_test_owner,p)
p.flags.targets={self=true}
assert(Native.context(staff).flags.targets.hostile)
reset()
for _,e in ipairs(native_test_targets) do if e.components.combat then e.components.combat:GetAttacked(native_test_owner,10,staff) end end
for _,e in ipairs(native_test_targets) do assert(e.hits==(e.prefab=="hostile" and 1 or 0)) end
local powder={prefab="gunpowder"};Native.tag(powder,native_test_owner,p);assert(not Native.context(powder))
local ordinary={prefab="trident"}
native_test_targets[2].components.combat:GetAttacked(native_test_owner,10,ordinary)
assert(native_test_targets[2].hits==1)
assert(not Native.context(native_test_owner))
local base=require("nw/base_damage_native")
base.tag(staff,{engraving="trident",base_damage_multiplier=.5})
base.wrap_combat(native_test_targets[4].components.combat)
local before_health=native_test_targets[4].components.health.currenthealth
native_test_targets[4].components.combat:GetAttacked(native_test_owner,20,staff)
assert(before_health-native_test_targets[4].components.health.currenthealth==10,"native base multiplier still applies once")
local denied_before=native_test_targets[2].components.health.currenthealth
base.wrap_combat(native_test_targets[2].components.combat)
native_test_targets[2].components.combat:GetAttacked(native_test_owner,20,staff)
assert(native_test_targets[2].components.health.currenthealth==denied_before,"multiplier wrapper cannot bypass scope")

-- Synchronous native area adapters restore their function environment on errors.
local Size=require("nw/native_size")
local function query() return TheSim:FindEntities(0,0,0,2) end
local env=getfenv(query)
local found=Size.filtered(query,1,2,0,0,function(e) return e.prefab=="nature" end)
assert(#found==1 and found[1].prefab=="nature" and getfenv(query)==env)
local function broken() TheSim:FindEntities(0,0,0,2);error("deliberate") end
local before=getfenv(broken)
assert(not pcall(Size.filtered,broken,1,2,0,0,function() return false end))
assert(getfenv(broken)==before and #query()==7)

-- Four exempt tools use their own capability predicate even under enemy-only
-- selection; hoe completion must report actual Till success, never a scope skip.
for _,key in ipairs({"fishingrod","oceanfishingrod","voidcloth_scythe","farm_hoe"}) do
    assert(Native.accepts(native_test_owner,native_test_targets[6],spell("hostile",key),function(_,e) return e.prefab=="nature" end))
    assert(not Native.accepts(native_test_owner,native_test_targets[6],spell("hostile",key),function() return false end))
end
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
local Impact=require("nw/engraved_impact")
local tilled=0
local hoe={components={farmtiller={Till=function(_,pos,owner)
    tilled=tilled+1;assert(owner==native_test_owner and pos.x==3);return tilled>1
end}}}
local hs={inst=hoe,owner=native_test_owner,p=spell("hostile","farm_hoe")}
assert(Impact.finish(hs,3,4)==false and tilled==1)
assert(Impact.finish(hs,3,4)==true and tilled==2)

-- Selected ice effects can act on a freezable tree without health or combat.
local tree=native_test_targets[6]
tree.components.freezable={AddColdness=function(_,n) tree.cold=tree.cold+n end}
reset()
local bell={prefab="dumbbell_bluegem",components={weapon={damage=34,OnAttack=noop}},
    Transform=native_test_owner.Transform,isiceattack=true}
Native.tag(bell,native_test_owner,spell("nature","dumbbell_bluegem"))
Giant.bell(bell,native_test_owner,1)
assert(tree.cold==2 and tree.hits==0,"cold capability is independent of damage capability")
Native.tag(bell,native_test_owner,spell("hostile","dumbbell_bluegem"))
Giant.bell(bell,native_test_owner,1)
assert(tree.cold==2,"cold still requires category selection")
Native.tag(bell,native_test_owner,{engraving="dumbbell_bluegem",flags={}})
assert(not Native.context(bell),"a new default continuation clears old scope")
Giant.bell(bell,native_test_owner,2)
assert(tree.cold==2,"unselected native default must retain its original candidate set")
tree.components.freezable=nil

-- Fixed-target native children re-check relationships for each independent hit.
reset()
local tentacle=native_test_entity("neutral");tentacle.prefab="shadowtentacle"
Native.tag(tentacle,native_test_owner,{source_weapon="ruins_bat",flags={targets={hostile=true}}})
local enemy=native_test_targets[4]
local weapon={components={weapon={damage=10}}}
tentacle.components.combat:DoAttack(enemy,weapon)
enemy.tags.hostile=nil
tentacle.components.combat:DoAttack(enemy,weapon)
assert(enemy.hits==1,"second tentacle strike must re-check selection")
enemy.tags.hostile=true

-- A denied native contact never reaches its damage or onhit callback; homing
-- also drops a target whose category changes before it can be hit.
local shot={components={projectile={}},prefab="brilliance_projectile_fx"}
local cp=shot.components.projectile
local hits,misses,updates=0,0,0
cp.Hit=function() hits=hits+1 end;cp.Miss=function() misses=misses+1 end
cp.OnUpdate=function() updates=updates+1 end
Native.tag(shot,native_test_owner,spell("hostile","staff_lunarplant"));Native.projectile(shot)
cp:Hit(enemy);assert(hits==1 and misses==0)
enemy.tags.hostile=nil;cp:Hit(enemy)
cp.target=enemy;cp:OnUpdate(1/30)
assert(hits==1 and misses==2 and updates==0)
enemy.tags.hostile=true;cp:OnUpdate(1/30);assert(updates==1)

-- Selection permits the target; native damage immunity still decides damage.
reset()
local player=native_test_targets[2]
local canattack=player.components.combat.CanBeAttacked
player.components.combat.CanBeAttacked=function() return false end
Native.tag(bell,native_test_owner,spell("players_other","dumbbell_bluegem"))
Giant.bell(bell,native_test_owner,1)
assert(player.hits==0 and player.cold==2,"damage rejection must not reject independent cold")
player.components.combat.CanBeAttacked=canattack
print("native targeting: scopes, exemptions, component separation, repeated native hits and callback cleanup OK")
