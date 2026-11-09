local Live=require("nw/entity_limits")
local E=require("nw/executor")
DEGREES=math.pi/180
local all,launched={},0
local function entity()
    local e={valid=true,events={}}
    function e:IsValid() return self.valid end
    function e:ListenForEvent(name,fn)
        self.events[name]=self.events[name] or {};table.insert(self.events[name],fn)
    end
    function e:Remove()
        assert(self.valid,"never remove an already removed native")
        self.valid=false
        for _,fn in ipairs(self.events.onremove or {}) do fn(self) end
    end
    function e:Launch(_,p,_,_,_,_,cleanup)
        assert(self.valid,"never launch a placement evicted earlier in the same batch")
        launched=launched+1;cleanup()
    end
    all[#all+1]=e;return e
end
local owner={userid="KU_a",GUID=1,Transform={GetWorldPosition=function() return 0,0,0 end}}
local other={userid="KU_b",GUID=2}
local function place(who,kind,order)
    local e=entity()
    if order then Live.restore_field(e,who,kind,order)
    else Live.bind(e,assert(Live.acquire(who,kind))) end
    return e
end
local function clear()
    for _,e in ipairs(all) do if e.valid then e:Remove() end end
    all={}
    for _,kind in ipairs({"fields","permanent_fields","projectiles"}) do
        assert(Live.stats(kind)==0);Live.configure(kind,0)
    end
end
for _,id in ipairs({"crystal_mine","sleep_crystal","payload_egg"}) do
    assert(Live.category({id=id,kind="field"})=="permanent_fields")
end
assert(Live.category({id="spore_sentry",kind="field"})=="fields")
assert(Live.category({id="spark",kind="projectile"})=="projectiles")
-- Separate owner and timed pools; holes from natural removal do not disturb age.
Live.configure("permanent_fields",25);Live.configure("fields",25)
local originals={}
for i=1,25 do originals[i]=place(owner,"permanent_fields") end
local foreign=place(other,"permanent_fields")
for i=1,25 do place(owner,"fields") end
assert(not Live.acquire(owner,"fields"))
originals[10]:Remove();place(owner,"permanent_fields")
assert(originals[1].valid)
place({userid=owner.userid,GUID=99},"permanent_fields")
assert(not originals[1].valid and originals[2].valid and foreign.valid)
assert(Live.owner_used(owner,"permanent_fields")==25 and Live.stats("fields")==25)
clear()
-- Lowering a limit does not immediately delete; the next placement trims oldest.
Live.configure("permanent_fields",50)
for i=1,40 do originals[i]=place(owner,"permanent_fields") end
Live.configure("permanent_fields",25)
assert(Live.stats("permanent_fields")==40)
place(owner,"permanent_fields")
for i=1,40 do assert(originals[i].valid==(i>16)) end
assert(Live.stats("permanent_fields")==25)
clear()
-- Saved order, not load order, determines replacement; load alone never evicts.
Live.configure("permanent_fields",25)
for i=27,1,-1 do originals[i]=place(owner,"permanent_fields",i) end
assert(Live.stats("permanent_fields")==27)
place(owner,"permanent_fields")
for i=1,27 do assert(originals[i].valid==(i>3)) end
clear()
-- The executor allocates a batch before launching: only surviving entities launch.
Live.configure("permanent_fields",25);SpawnPrefab=function() return entity() end
local plan={projectile_count=27,next_state={rng_state=1},blocks={{copies=27,projectiles={
    {id="sleep_crystal",kind="field",flags={},spread=0}}}}}
assert(E.execute(plan,owner,0,0,1,0))
assert(#all==27 and launched==25 and Live.stats("permanent_fields")==25)
assert(not all[1].valid and not all[2].valid and all[3].valid)
clear()
-- Failure after a previous eviction rolls back remaining allocations safely.
Live.configure("permanent_fields",25)
SpawnPrefab=function() if #all==26 then return nil end;return entity() end
local ok,reason=E.execute(plan,owner,0,0,1,0)
assert(not ok and reason=="SPAWN_FAILED" and Live.stats("permanent_fields")==0)
clear()
print("permanent field limits: independent pools, owner isolation, oldest replacement, removal holes, lowering cap, saved order, same-batch eviction and spawn-failure cleanup")
