local B=require("nw/balance");B.configure("balanced")
local sequence=0
GetTime=function() return 0 end
TheWorld={components={nw_identity={Next=function() sequence=sequence+1;return "persist-root:"..sequence end}},events={}}
AllPlayers={};DEGREES=math.pi/180
package.loaded["nw/field_motion"]={start=function() return true end}
package.loaded["nw/field_stages"]={start=function() end,finish=function() end}
package.loaded["nw/projectile_size"]={field=function() end}
local Stored=require("nw/persistent_fields")
local E=require("nw/executor")
local U=require("nw/util")
local guid=0
local function entity(userid)
    guid=guid+1
    local e={GUID=guid,userid=userid,valid=true,events={},components={combat={}},x=0,z=0}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return false end
    function e:HasTag() return false end
    function e:IsAsleep() return false end
    function e:ListenForEvent(name,fn,source)
        source=source or self;source.events[name]=source.events[name] or {}
        source.events[name][#source.events[name]+1]={self,fn}
    end
    function e:Remove()
        if not self.valid then return end
        self.valid=false
        for _,row in ipairs(self.events.onremove or {}) do row[2](row[1]) end
    end
    function e:DoPeriodicTask() end
    function e:DoTaskInTime() end
    function e:GetDistanceSqToPoint(x,y,z) return (self.x-x)^2+(self.z-z)^2 end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end}
    return e
end
local a,b=entity("placer"),entity("breaker");AllPlayers={a,b}
local placed,shots={},{}
SpawnPrefab=function()
    local e=entity()
    function e:Launch(owner,p,x,z,dx,dz,cleanup,h,fire,payload)
        if Stored.is(p.id) then
            Stored.install(self);Stored.launch(self,owner,p,dx,dz,h,payload);placed[#placed+1]=self
        else self.p,self.owner=p,owner;shots[#shots+1]=self end
        cleanup()
    end
    return e
end
local function spell(id,payload)
    return {id=id,kind=Stored.is(id) and "field" or "projectile",damage=22,radius=1.8,
        speed=0,flags={},spread=0,payload=payload}
end
local function execute(blocks)
    return assert(E.execute({blocks=blocks,projectile_count=1,next_state={rng_state=1}},a,0,0,1,0,1))
end
execute({{copies=2,projectiles={spell("sleep_crystal")}}})
local first,second=placed[1],placed[2]
local root=first._nw_stored.p._nw_root
assert(root and second._nw_stored.p._nw_root==root)
execute({{projectiles={spell("sleep_crystal")}}})
local third=placed[3];assert(third._nw_stored.p._nw_root~=root)
local function save(e)
    local data={};e.OnSave(e,data);e:Remove();return data
end
local function load(data)
    local e=entity();Stored.install(e);e.OnLoad(e,U.copy(data));return e
end
local saved=save(second)
assert(saved.placement.p._nw_root==root and not saved.placement._nw_balance_hits)
second=load(saved);assert(second._nw_stored.p._nw_root==root)
local blasts={}
require("nw/spell_effects").blast=function(owner,x,z,p) blasts[#blasts+1]={root=p._nw_root,owner=owner} end
-- One detonation command must not merge pre-existing roots, including reloads.
local command=entity()
TheSim={FindEntities=function() return {first,second,third} end}
require("nw/field_stages").pulse=function() end
require("nw/expanded_fields").actions.detonate(command,a,{radius=4,aim_range=20},0,0)
assert(#blasts==3)
local same,different=0,0
for _,hit in ipairs(blasts) do if hit.root==root then same=same+1 else different=different+1 end end
assert(same==2 and different==1)
-- A nested payload survives save/load and changes attacker without changing root.
execute({{projectiles={spell("payload_egg",2)}},{projectiles={spell("payload_egg",3)}},{projectiles={spell("arrow")}}})
local egg=placed[#placed];root=egg._nw_stored.p._nw_root
egg=load(save(egg));AllPlayers={b};a.valid=false
egg._nw_break(b)
local child=placed[#placed]
assert(child._nw_stored.userid==b.userid and child._nw_stored.p._nw_root==root)
child=load(save(child));child._nw_break(b)
assert(#shots==1 and shots[1].owner==b and shots[1].p._nw_root==root)
-- Existing legacy placements receive stable per-entity identities on upgrade.
saved.placement.p._nw_root=nil
local legacy=load(saved);local legacyroot=legacy._nw_stored.p._nw_root
assert(legacyroot and legacyroot~=root)
legacy=load(save(legacy));assert(legacy._nw_stored.p._nw_root==legacyroot)
print("balance persistence: saved shared roots, distinct casts/detonation, nested egg ownership, legacy migration")
