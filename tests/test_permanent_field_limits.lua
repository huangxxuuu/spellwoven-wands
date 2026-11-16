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
    function e:Launch(_,p,_,_,_,_,cleanup,_,fire)
        assert(self.valid,"never launch a placement evicted earlier in the same batch")
        launched=launched+1;self.p=p;self.fire=fire;self._shot={}
        if p.kind=="field" then cleanup() end
    end
    all[#all+1]=e;return e
end
local owner={userid="KU_a",GUID=1,IsValid=function() return true end,components={},Transform={GetWorldPosition=function() return 0,0,0 end}}
local other={userid="KU_b",GUID=2,Transform=owner.Transform}
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
-- All owners share permanent capacity; timed pools remain per owner.
Live.configure("permanent_fields",25);Live.configure("fields",25)
local originals={}
for i=1,24 do originals[i]=place(owner,"permanent_fields") end
local foreign=place(other,"permanent_fields")
for i=1,25 do place(owner,"fields") end
assert(not Live.acquire(owner,"fields"))
originals[10]:Remove();place(owner,"permanent_fields")
assert(originals[1].valid)
place({userid=owner.userid,GUID=99},"permanent_fields")
assert(not originals[1].valid and originals[2].valid and foreign.valid)
assert(Live.owner_used(owner,"permanent_fields")==24 and Live.owner_used(other,"permanent_fields")==1)
assert(Live.stats("permanent_fields")==25 and Live.stats("fields")==25)
place(other,"fields");assert(Live.stats("fields")==26,"timed capacity stays per player")
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
for i=27,1,-1 do originals[i]=place(i%2==0 and owner or other,"permanent_fields",i) end
assert(Live.stats("permanent_fields")==27)
place(owner,"permanent_fields")
for i=1,27 do assert(originals[i].valid==(i>3)) end
clear()
-- A huge cast creates at most N permanent entities, never evicting its excess.
Live.configure("permanent_fields",25);SpawnPrefab=function() return entity() end
local plan={projectile_count=1e12,next_state={rng_state=1},blocks={{copies=1e12,projectiles={
    {id="sleep_crystal",kind="field",flags={},spread=0}}}}}
assert(E.execute(plan,owner,0,0,1,0))
assert(#all==25 and launched==25 and Live.stats("permanent_fields")==25)
assert(all[1].valid and all[25].valid)
-- A genuinely new cast gets N again and replaces the world's oldest, any owner.
assert(E.execute(plan,other,0,0,1,0))
assert(#all==50 and not all[1].valid and all[26].valid and all[50].valid)
assert(Live.owner_used(owner,"permanent_fields")==0 and Live.owner_used(other,"permanent_fields")==25)
clear()
-- Failure after a previous eviction rolls back remaining allocations safely.
Live.configure("permanent_fields",25)
for i=1,25 do originals[i]=place(other,"permanent_fields") end
SpawnPrefab=function() if #all==26 then return nil end;return entity() end
local context=require("nw/cast_emissions").new()
local ok,reason=E.execute(plan,owner,0,0,1,0,nil,nil,nil,context)
assert(not ok and reason=="SPAWN_FAILED" and Live.stats("permanent_fields")==23)
assert(context.permanent_spawned==1,"only successful creation counts, rollback does not refund it")
clear()
SpawnPrefab=function() return entity() end
Live.configure("permanent_fields",25)
-- Deferred hit payloads share the root's cumulative allowance, even after removal.
local nested={projectile_count=42,next_state={rng_state=1},blocks={
    {projectiles={{id="spark_hit",kind="projectile",count=2,flags={},event="hit",payload=2}}},
    {copies=20,projectiles={{id="sleep_crystal",kind="field",flags={}}}},
}}
assert(E.execute(nested,owner,0,0,1,0))
local first,second=all[1],all[2]
assert(first._shot.fire(0,0,1,0) and #all==22)
for i=3,22 do all[i]:Remove() end
assert(second._shot.fire(0,0,1,0) and #all==27 and Live.stats("permanent_fields")==5)
assert(first._shot.fire(0,0,1,0) and #all==27,"removed or expired placements do not refund this cast")
clear()
Live.configure("permanent_fields",25)
-- Immediate payload callbacks and later copies also share one context.
local Effects=require("nw/spell_effects")
local oldchain,oldblast=Effects.chain,Effects.blast
Effects.chain=function(_,_,x,z,_,dx,dz,_,fire,cleanup) fire(x,z,dx,dz);cleanup() end
nested.blocks[1].projectiles[1]={id="chain",kind="instant",count=2,flags={},payload=2}
assert(E.execute(nested,owner,0,0,1,0) and #all==25 and Live.stats("permanent_fields")==25)
clear();Live.configure("permanent_fields",25)
-- Exhausting the permanent quota must not skip other spells in mixed copies.
local blasts=0;Effects.blast=function() blasts=blasts+1 end
local mixed={projectile_count=60,next_state={rng_state=1},blocks={{copies=30,projectiles={
    {id="sleep_crystal",kind="field",flags={}},
    {id="explosion",kind="instant",flags={}},
}}}}
assert(E.execute(mixed,owner,0,0,1,0) and #all==25 and blasts==30)
Effects.chain,Effects.blast=oldchain,oldblast
clear()
print("permanent field limits: shard capacity, actual owner counts, timed isolation, global saved order, bounded casts, shared immediate/deferred payloads, no refunds, mixed spells and failure cleanup")
