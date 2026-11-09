local C=require("nw/compiler")
local U=require("nw/util")
local E=require("nw/executor")
local function equal(a,b)
    assert(type(a)==type(b),"type changed")
    if type(a)~="table" then assert(a==b,tostring(a).." ~= "..tostring(b));return end
    for k,v in pairs(a) do equal(v,b[k]) end
    for k in pairs(b) do assert(a[k]~=nil,"extra field: "..tostring(k)) end
end
local function plan(ids)
    local w=require("nw/generator").starter()
    w.stats.mana_max=10000;w.cards={}
    for i,id in ipairs(ids) do
        assert(require("nw/definitions").spells[id],"unknown test card: "..id)
        w.cards[i]={spell_id=id,card_uid=tostring(i)}
    end
    w.runtime=C.initial(w.cards,w.stats,71)
    return assert(C.compile(w))
end
-- Frozen pre-optimization expansion: compare every value, including nested
-- payload IDs and secondary-copy exclusions, without relying on table identity.
local function reference(outputs)
    local out={}
    local function visit(id,scale,secondary)
        local src=outputs[id]
        local b={id=#out+1,source_id=id,depth=src.depth,modifiers=src.modifiers,delay=src.delay,projectiles={}}
        out[b.id]=b
        for copy=1,src.copies or 1 do
            for _,original in ipairs(src.projectiles) do
                local p=U.copy(original)
                local fraction=scale*(src.copy_damage or 1)
                local limited=secondary or (src.copy_damage and copy>1)
                if fraction~=1 then
                    p.effect_scale=fraction
                    for _,key in ipairs({"damage","jump_damage","burn_damage","end_damage","planar","heal"}) do
                        if p[key] then p[key]=p[key]*fraction end
                    end
                end
                if limited then
                    p.flags.melee_mark=nil
                    p.freeze,p.flags.heal_ally,p.flags.leech,p.flags.knockback=nil,nil,nil,nil
                    p.secondary=true
                    p.suppress_support=p.kind=="note" or p.id=="vital_ring" or p.id=="vortex"
                        or p.id=="rain_cloud" or p.id=="guard_ring" or p.id=="detonate"
                end
                if p.payload then p.payload=visit(p.payload,fraction,limited) end
                b.projectiles[#b.projectiles+1]=p
            end
        end
        return b.id
    end
    visit(1,1,false);return out
end
local T=require("nw/cast_templates")
-- Materialize only in the test oracle to compare all old static semantics.
local function materialize(outputs)
    local out,resolve={},T.resolver()
    local function visit(id,scale,secondary)
        local src=outputs[id]
        local b={id=#out+1,source_id=id,depth=src.depth,modifiers=src.modifiers,delay=src.delay,projectiles={}}
        out[b.id]=b
        for copy=1,src.copies or 1 do
            for _,original in ipairs(src.projectiles) do
                local fraction=scale*(src.copy_damage or 1)
                local limited=secondary or (src.copy_damage and copy>1)
                local p=U.copy(resolve(original,fraction,limited))
                if p.payload then p.payload=visit(p.payload,fraction,limited) end
                b.projectiles[#b.projectiles+1]=p
            end
        end
        return b.id
    end
    visit(1,1,false);return out
end
for _,id in ipairs(require("nw/definitions").order) do
    local p=plan({"repeat_4","heal_ally","leech",id,"spark"})
    local before=U.copy(p.blocks)
    equal(materialize(p.blocks),reference(p.blocks))
    equal(p.blocks,before)
end
for _,id in ipairs({"spark_hit","scatter_timer","payload_egg"}) do
    local p=plan({"repeat_4",id,"repeat_4","frost"})
    equal(materialize(p.blocks),reference(p.blocks))
end

DEGREES=math.pi/180
local owner={GUID=77,IsValid=function() return true end,components={}}
local shots={}
local fail_after
SpawnPrefab=function()
    if fail_after and #shots==fail_after then return nil end
    local obj={valid=true}
    function obj:IsValid() return self.valid end
    function obj:Remove()
        if self.valid then self.valid=false;if self.cleanup then self.cleanup() end end
    end
    function obj:Launch(_,desc,x,z,dx,dz,cleanup,_,_,payload)
        self.p,self.x,self.z,self.dx,self.dz,self.cleanup=desc,x,z,dx,dz,cleanup
        self.payload=payload
        self._shot={p=desc,hit={},remaining=desc.lifetime}
    end
    shots[#shots+1]=obj;return obj
end
local function clear()
    for _,s in ipairs(shots) do s:Remove() end
    assert(E.stats()==0,"live or untriggered subtree budget leaked")
    shots={}
end
local function execute(ids)
    local p=plan(ids)
    assert(E.execute(p,owner,0,0,1,0,1.75))
    return p
end

-- 729 carriers retain two templates; no untriggered arrow is instantiated.
local ids={"repeat_3","repeat_3","repeat_3","repeat_3","repeat_3","repeat_3","spark_hit","arrow"}
local p=execute(ids)
assert(#p.blocks==2 and #p.blocks[1].projectiles==1 and p.blocks[1].copies==729)
assert(#shots==729 and E.stats()==729 and not p.angles and not p.expand_on_launch)
for i=2,729 do
    assert(shots[i].p==shots[1].p,"carriers share their immutable descriptor")
    assert(shots[i]._shot.group~=shots[1]._shot.group and shots[i]._shot.hit~=shots[1]._shot.hit)
end
local before,seed=U.copy(p.blocks),p.next_state.rng_state
assert(shots[1]._shot.fire(1,2,1,0));assert(#shots==730)
local first_angle=shots[730].dz
assert(shots[1]._shot.fire(1,2,1,0));assert(#shots==731)
assert(first_angle~=shots[731].dz,"a repeated hit must reroll spread")
assert(shots[2]._shot.fire(3,4,1,0));assert(#shots==732)
assert(shots[730].p==shots[731].p and shots[730].p==shots[732].p)
assert(shots[730]._shot.group~=shots[731]._shot.group)
assert(p.next_state.rng_state==seed,"delayed release mutated the wand's committed RNG")
equal(p.blocks,before)
local root_angle=shots[1].dz
clear()
p=execute(ids)
assert(shots[1].dz==root_angle)
assert(shots[1]._shot.fire(1,2,1,0) and shots[730].dz==first_angle,"same seed and event order must reproduce spread")
clear()

-- Unfired payload size cannot consume scatter RNG or create parameter copies.
local small=execute({"arrow_hit","spark"});local small_angle=shots[1].dz
clear()
local big=execute({"arrow_hit","repeat_3","repeat_3","repeat_3","spark"})
assert(#shots==1 and #big.blocks==2 and small.next_state.rng_state==big.next_state.rng_state)
assert(shots[1].dz==small_angle)
clear()

-- Copy attenuation and secondary exclusions propagate through shared children.
p=execute({"repeat_4","spark_hit","repeat_4","frost"})
assert(#shots==4 and p.projectile_count==20)
for i=1,4 do assert(shots[i]._shot.fire(0,0,1,0)) end
assert(#shots==20 and #p.blocks==2)
for i=5,20 do
    assert(math.abs(shots[i].p.damage-9*.45*.45)<1e-9)
    assert((shots[i].p.freeze~=nil)==(i==5))
end
assert(shots[6].p==shots[9].p and shots[2].p==shots[3].p)
assert(shots[1].p~=shots[2].p)
clear()

-- Failed repeated spawning releases the whole reserved tree, including children.
fail_after=2
local failed=plan({"repeat_4","spark_hit","repeat_4","frost"})
local failed_seed=failed.next_state.rng_state
local ok,why=E.execute(failed,owner,0,0,1,0,1.75)
assert(not ok and why=="SPAWN_FAILED" and E.stats()==0)
assert(#shots==2 and not shots[1].valid and not shots[2].valid)
assert(failed.next_state.rng_state==failed_seed)
fail_after=nil;clear()

-- Each actual payload emission checks live slots; skipped copies do not reject the trigger.
E.set_projectile_limit(25)
p=execute({"repeat_4","spark_hit","repeat_4","frost"})
assert(E.stats()==4)
for i=1,5 do assert(shots[1]._shot.fire(0,0,1,0)) end
assert(E.stats()==24 and #shots==24)
assert(shots[2]._shot.fire(0,0,1,0) and #shots==25 and E.stats()==25)
assert(shots[2]._shot.fire(0,0,1,0) and #shots==25,"full budget consumes trigger without spawning")
shots[5]:Remove()
assert(shots[2]._shot.fire(0,0,1,0) and #shots==26 and E.stats()==25)
clear();E.set_projectile_limit(0)

-- Save compact nested payloads with inherited variants; never copy live state.
local nested=plan({"repeat_4","payload_egg","repeat_4","spark_hit","frost"})
local child=nested.blocks[1].projectiles[1].payload
local stored=E.store_payload(nested.blocks,child,.45,true,19)
assert(#stored.blocks==2 and stored.blocks[1].copies==4 and stored.projectile_count==8)
assert(not stored.angles and stored.payload_scale==.45 and stored.payload_secondary)
local frozen=U.copy(stored)
assert(E.execute(stored,owner,0,0,1,0,1.75))
assert(#shots==4 and shots[1].p.secondary and math.abs(shots[1].p.damage-18*.45*.45)<1e-9)
assert(shots[1]._shot.fire(0,0,1,0))
assert(#shots==5 and not shots[5].p.freeze and math.abs(shots[5].p.damage-9*.45*.45)<1e-9)
equal(stored.blocks,frozen.blocks)
stored.blocks[1].projectiles[1].damage=-1
assert(nested.blocks[child].projectiles[1].damage==18)
clear()

-- Legacy saves remain readable, but their old frozen angles no longer dictate spread.
local legacy=plan({"arrow_hit","spark"})
legacy.blocks=reference(legacy.blocks)
legacy.angles={{{100}},{{100}}}
assert(E.execute(legacy,owner,0,0,1,0,1.75))
assert(math.abs(shots[1].dz)<.1)
shots[1]._shot.fire(0,0,1,0);local a=shots[2].dz
shots[1]._shot.fire(0,0,1,0);assert(shots[3].dz~=a)
clear()

-- Fixed formations survive, including zero-spread repeated payloads.
p=execute({"arrow_hit","precision","precision","trident_cast","spark","spark","spark"})
shots[1]._shot.fire(0,0,1,0);shots[1]._shot.fire(0,0,1,0)
for i=1,3 do
    assert(math.abs(shots[i+1].dz-math.sin((i-2)*20*DEGREES))<1e-9)
    assert(shots[i+1].dz==shots[i+4].dz)
end
clear()

-- Size accounting is memoized for shared DAGs and rejects cycles before reserve.
local shared={{copies=3,projectiles={{payload=2},{payload=3}}},
    {projectiles={{payload=3}}},{copies=2,projectiles={{}}}}
local sizes=assert(T.sizes(shared));assert(sizes[1]==21 and sizes[2]==3 and sizes[3]==2)
local cycle={projectile_count=1,next_state={rng_state=1},blocks={{projectiles={{payload=1}}}}}
local ok,why=E.execute(cycle,owner,0,0,1,0)
assert(not ok and why=="INVALID_PLAN" and E.stats()==0)
print("compact templates: legacy static equivalence, 729 shared carriers, fresh scatter, RNG isolation, saved variants, legacy payloads, formations and DAG budgets")
