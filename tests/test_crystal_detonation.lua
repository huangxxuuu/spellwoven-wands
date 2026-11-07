-- Regression for expanded_fields.lua detonate: a synchronous blast removes
-- several entries from the persistent ownership list while it is traversed.
GetTime=function() return 0 end
TheWorld={events={}}
AllPlayers={}
package.loaded["nw/field_motion"]={start=function() return true end}
local Stored=require("nw/persistent_fields")
local Fields=require("nw/expanded_fields")
local Effects=require("nw/spell_effects")
local guid=0
local all,bursts,ends={},{},{}
local function entity(x,z,crystal)
    guid=guid+1
    local e={GUID=guid,valid=true,x=x or 0,z=z or 0,events={},components={},crystal=crystal}
    function e:IsValid() return self.valid end
    function e:IsInLimbo() return false end
    function e:HasTag(tag) return tag=="nw_breakable" and self.crystal or false end
    function e:IsAsleep() return false end
    function e:GetDistanceSqToPoint(x,y,z) return (self.x-x)^2+(self.z-z)^2 end
    function e:ListenForEvent(name,fn,source)
        source=source or self;source.events[name]=source.events[name] or {}
        source.events[name][#source.events[name]+1]=fn
    end
    function e:Remove()
        assert(self.valid,"crystal removed more than once")
        self.valid=false
        for _,fn in ipairs(self.events.onremove or {}) do fn(self) end
    end
    function e:DoTaskInTime(delay,fn) self.expiry={delay=delay,fn=fn} end
    function e:DoPeriodicTask() return {Cancel=function() end} end
    e.Transform={GetWorldPosition=function() return e.x,0,e.z end,
        SetPosition=function(_,x,y,z) e.x,e.z=x,z end}
    e.AnimState={PlayAnimation=function() end,PushAnimation=function() end}
    return e
end
SpawnPrefab=function(name)
    local e=entity()
    function e:SetRadius(radius) bursts[#bursts+1]={x=self.x,z=self.z,radius=radius} end
    function e:SetStage(id,phase) ends[#ends+1]={id=id,phase=phase,x=self.x,z=self.z} end
    return e
end
-- Each blast sees its own stable engine scan, including entries removed by a
-- deeper explosion before that outer scan resumes. Use the real blast code.
Effects.scan=function()
    local snapshot={}
    for _,e in ipairs(all) do if e.valid then snapshot[#snapshot+1]=e end end
    return snapshot
end
local owner,other=entity(),entity()
local function crystal(caster,id,x,z)
    local e=entity(x,z,true);all[#all+1]=e
    Stored.launch(e,caster,{id=id,kind="field",radius=1.1,damage=20,flags={}},1,0,0)
    return e
end
local separate=crystal(owner,"crystal_mine",6,0)
local chain={}
-- Adjacent crystals form a real domino chain: the command starts with the
-- newest at z=0, and each explosion reaches the next one 0.9 units behind it.
for i=1,8 do chain[i]=crystal(owner,"sleep_crystal",0,(8-i)*.9) end
local outside_radius=crystal(owner,"crystal_mine",-6,0)
local outside_aim=crystal(owner,"crystal_mine",8,0)
local foreign=crystal(other,"crystal_mine",0,-5)
local command=entity()
Fields.actions.detonate(command,owner,{radius=7,aim_range=7},3,0)
assert(not separate.valid,"chain removal must not skip a still-eligible independent mine")
for _,e in ipairs(chain) do assert(not e.valid and e._nw_spent,"every domino detonates once") end
assert(outside_radius.valid and outside_aim.valid and foreign.valid,"command range/ownership remain unchanged")
assert(#bursts==9 and #ends==9,"one gameplay blast and ending per crystal")
assert(#Stored.crystals(owner)==2 and #Stored.crystals(other)==1,"real onremove callbacks prune ownership lists")
assert(command.expiry and command.expiry.delay==.22,"successful command still schedules cleanup")
-- Repeated commands and stale callbacks cannot re-explode spent crystals.
Fields.actions.detonate(entity(),owner,{radius=7,aim_range=7},3,0)
for _,e in ipairs(chain) do e._nw_break(owner) end
assert(#bursts==9 and #ends==9)
-- An entire owned list may disappear before the next outer loop iteration.
local empty_owner=entity()
for i=1,4 do crystal(empty_owner,"sleep_crystal",30,.2*i) end
empty_owner.x=30
Fields.actions.detonate(entity(),empty_owner,{radius=2,aim_range=2},30,0)
assert(#Stored.crystals(empty_owner)==0 and #bursts==13 and #ends==13)
print("crystal detonation: synchronous domino removal, stable candidates, range/ownership and exactly-once effects")
