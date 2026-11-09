FRAMES=1/30;DEGREES=math.pi/180
local Budget=require("nw/trail_budget")
local function events(e)
    e.events={}
    function e:ListenForEvent(name,fn)
        self.events[name]=self.events[name] or {};self.events[name][fn]=true
    end
    function e:RemoveEventCallback(name,fn) if self.events[name] then self.events[name][fn]=nil end end
    function e:PushEvent(name)
        local list={};for fn in pairs(self.events[name] or {}) do list[#list+1]=fn end
        for _,fn in ipairs(list) do fn(self) end
    end
    return e
end
TheWorld=events({})
local function dispose(p) assert(not p.removed);p.removed=true end
local mine={_nw_trail_userid={value=function() return "KU_me" end}}
local other={_nw_trail_userid={value=function() return "KU_other" end}}
local function add(born,source,part)
    if not Budget.can_emit(source) then return nil end
    part=part or {};Budget.track(part,born,dispose);return part
end
local function clear()
    TheWorld:PushEvent("onremove")
    assert(not TheWorld._nw_trail_budget)
    assert(not next(TheWorld.events.onremove or {}))
end

assert(Budget.limit==0)
local all={}
for i=1,1300 do all[i]=add(i) end
assert(TheWorld._nw_trail_budget.count==1300)
Budget.configure(500)
assert(TheWorld._nw_trail_budget.count==1300,"lowering cap must not delete existing tails")
for _,p in ipairs(all) do assert(not p.removed) end
ThePlayer={userid="KU_me"}
assert(not add(1301,mine) and not add(1301,other))
clear()

for _,limit in ipairs({100,500,900,1300,1700,2100,2500,2900,3300}) do
    Budget.configure(limit)
    local remote,localparts={},{}
    for i=1,limit*.75 do remote[i]=assert(add(i,other)) end
    assert(not add(2000,other) and not add(2000,nil))
    for i=1,limit*.25 do localparts[i]=assert(add(i,mine)) end
    assert(TheWorld._nw_trail_budget.count==limit)
    assert(not add(2001,mine) and not add(2001,other))
    -- A renewal is also an emission: leave its old age untouched when blocked.
    local old=localparts[1]._trail_record.born
    assert(not add(2002,mine,localparts[1]))
    assert(localparts[1]._trail_record.born==old and not localparts[1].removed)
    Budget.remove(remote[1]);Budget.remove(remote[1])
    assert(TheWorld._nw_trail_budget.count==limit-1)
    assert(not add(2003,other),"remote threshold uses total, including local tails")
    assert(add(2003,mine))
    for i=2,#remote do assert(not remote[i].removed) end
    clear()
    -- Own tails also consume the 75% threshold, rather than a separate pool.
    for i=1,limit*.75 do assert(add(i,mine)) end
    assert(not add(2004,other))
    assert(add(2004,mine))
    clear()
end

Budget.configure(500)
for i=1,375 do assert(add(i,other)) end
local id=""
local delayed={_nw_trail_userid={value=function() return id end}}
assert(not add(151,delayed))
id="KU_me";assert(add(151,delayed),"next attempt sees late ownership replication")
ThePlayer=nil;assert(not add(152,mine))
ThePlayer={userid="KU_me"};assert(add(152,mine),"next attempt sees player activation")
ThePlayer={userid="KU_other"}
assert(not add(153,mine) and add(153,other),"each client uses its own identity")
clear();ThePlayer=nil
for _,limit in ipairs({0,100,500,900,1300,1700,2100,2500,2900,3300}) do
    Budget.configure(limit);assert(Budget.limit==limit)
end
Budget.configure(96);assert(Budget.limit==0)
TheSim={GetPersistentString=function(_,_,cb) cb(false,"") end}
local reads=0
local env={GetModConfigData=function(key,local_only)
    assert(key=="client_trail_limit" and local_only);reads=reads+1;return 500
end}
Budget.install(env,{TheNet={IsDedicated=function() return false end}})
assert(Budget.limit==500 and reads==1)
Budget.install(env,{TheNet={IsDedicated=function() return true end}});assert(reads==1)
Budget.configure(0)

-- Run the real spark, elemental (timed + spatial) and tool renderers together.
-- All share one counter; rejected births must never allocate or renew a sprite.
local now,created,removed=0,0,0
local tasks,heads={},{}
ANIM_ORIENTATION={OnGround=1,BillBoard=2}
TheCamera={heading=0,pitch=35};TheNet={IsDedicated=function() return false end}
GetTime=function() return now end
function TheWorld:DoPeriodicTask(_,fn)
    local t={fn=fn,Cancel=function(self) self.cancelled=true end};tasks[#tasks+1]=t;return t
end
local noop=function() end
local function entity()
    local e=events({valid=true,x=0,y=0,z=0,entity={},Transform={},AnimState={}})
    for _,key in ipairs({"AddTransform","AddAnimState","SetCanSleep"}) do e.entity[key]=noop end
    e.entity.IsVisible=function() return true end;e.entity.GetParent=function() return nil end
    e.Transform.GetWorldPosition=function() return e.x,e.y,e.z end
    e.Transform.SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end
    e.Transform.GetRotation=function() return 0 end;e.Transform.SetScale=noop
    for _,key in ipairs({"SetBank","SetBuild","SetOrientation","SetLightOverride","SetDeltaTimeMultiplier","SetTime","PlayAnimation"}) do e.AnimState[key]=noop end
    e.AddTag=noop;e.ForceFacePoint=noop
    function e:IsValid() return self.valid end
    function e:Remove() assert(self.valid);self.valid=false;self:PushEvent("onremove");removed=removed+1 end
    return e
end
CreateEntity=function() created=created+1;return entity() end
local Spark=require("nw/spark_trail")
local Element=require("nw/elemental_flight")
local Tool=require("nw/tool_flight")
local function shot(id)
    local e=entity();e.GUID=#heads+1;e._visual=entity()
    e._height={value=function() return 1.4 end};e._size={value=function() return 1 end}
    e.Physics={GetVelocity=function() return 25,0,0 end}
    heads[#heads+1]=e
    if id=="spark" then Spark.attach(e)
    elseif id=="orange_bolt" then Tool.attach(e,id)
    else Element.attach(e,id) end
    return e
end
local function advance()
    now=now+FRAMES
    for _,e in ipairs(heads) do if e.valid then e.x=e.x+25*FRAMES end end
    for _,t in ipairs(tasks) do if not t.cancelled then t.fn(TheWorld) end end
    local pool=TheWorld._nw_trail_budget
    local expected=0
    for _,name in ipairs({"_nw_spark_trails","_nw_elemental_flights","_nw_tool_flights"}) do
        local localpool=TheWorld[name]
        if localpool then
            local count=0
            for _,s in ipairs(localpool.shots) do
                for slot,p in pairs(s.parts) do
                    count=count+1;assert(p.fx:IsValid() and p._trail_record)
                    assert(p.owner==s and p.slot==slot and p.pool==localpool)
                end
            end
            assert(localpool.count==count);expected=expected+count
        end
    end
    assert(expected==created-removed and expected==(pool and pool.count or 0))
    
end
for i=1,27 do shot("spark") end
for i=1,10 do shot("fire");shot("arrow");shot("orange_bolt") end
for i=1,20 do advance() end
assert(TheWorld._nw_spark_trails.count==243)
assert(TheWorld._nw_elemental_flights.arrow_count>256)
assert(TheWorld._nw_tool_flights.count>384)
assert(TheWorld._nw_trail_budget.count>1000,"unlimited must remove every old renderer-wide cap")
for _,limit in ipairs({3300,2900,2500,2100,1700,1300,900,500,100}) do
    local before=TheWorld._nw_trail_budget.count
    Budget.configure(limit)
    assert(TheWorld._nw_trail_budget.count==before,"config changes must not evict")
    for i=1,35 do advance() end
    assert(TheWorld._nw_trail_budget.count<=limit*.75)
end
Budget.configure(0)
for i=1,20 do advance() end
assert(TheWorld._nw_trail_budget.count>1000)
for _,e in ipairs(heads) do e.valid=false;e:PushEvent("onremove") end
for i=1,35 do advance() end
assert(created==removed and not TheWorld._nw_trail_budget)
assert(not TheWorld._nw_spark_trails and not TheWorld._nw_elemental_flights and not TheWorld._nw_tool_flights)
assert(not next(TheWorld.events.onremove or {}))
-- Hold the pool at the threshold while actual renderers attempt births.
-- No allocations, removals, or slot renewal are allowed during rejection.
heads={};tasks={};ThePlayer={userid="KU_me"};Budget.configure(500)
local blockers={}
for i=1,375 do blockers[i]=assert(add(i,other)) end
local baseline_created,baseline_removed=created,removed
for _,kind in ipairs({"spark","fire","arrow","flint_lance","orange_bolt"}) do shot(kind) end
for i=1,15 do
    now=now+FRAMES
    for _,e in ipairs(heads) do e.x=e.x+25*FRAMES end
    for _,t in ipairs(tasks) do if not t.cancelled then t.fn(TheWorld) end end
end
assert(created==baseline_created and removed==baseline_removed,
    "remote rejection must happen before CreateEntity, without deleting existing tails")
for _,p in ipairs(blockers) do assert(not p.removed) end
for _,e in ipairs(heads) do e._nw_trail_userid=mine._nw_trail_userid end
for i=1,3 do
    now=now+FRAMES
    for _,e in ipairs(heads) do e.x=e.x+25*FRAMES end
    for _,t in ipairs(tasks) do if not t.cancelled then t.fn(TheWorld) end end
end
assert(created>baseline_created,"local tails may use the remaining capacity")
while Budget.can_emit(mine) do blockers[#blockers+1]=assert(add(now,mine)) end
local ages={}
for part in pairs(TheWorld._nw_trail_budget.parts) do if part.fx then ages[part]=part.born end end
baseline_created,baseline_removed=created,removed
now=now+FRAMES
for _,e in ipairs(heads) do e.x=e.x+25*FRAMES end
for _,t in ipairs(tasks) do if not t.cancelled then t.fn(TheWorld) end end
assert(created==baseline_created and removed==baseline_removed,"full pool skips local births too")
for part,born in pairs(ages) do assert(part.born==born,"rejection must not renew a reused slot") end
for _,p in ipairs(blockers) do Budget.remove(p) end
for i=1,15 do advance() end
assert(TheWorld._nw_trail_budget.count<=500)
for _,e in ipairs(heads) do e.valid=false;e:PushEvent("onremove") end
for i=1,35 do advance() end
assert(created==removed and not TheWorld._nw_trail_budget)
print("trail budget: unlimited, nine caps, 75% shared-total threshold, no eviction or rejected allocation, late ownership, mixed renderers and cleanup")
