local C=require("nw/compiler")
local Cards=require("nw/cards")
local D=require("nw/definitions")
local E=require("nw/executor")
local Kit=require("nw/spellkit")
local Flight=require("nw/flight")
local Melee=require("nw/melee")
local function compile(ids)
    local w=require("nw/generator").starter()
    w.stats.mana_max=600;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,42)
    return assert(C.compile(w))
end
local seen,n={},0
for _,page in ipairs(Kit.pages) do
    assert(#page[2]<=9)
    for _,id in ipairs(page[2]) do
        assert(not seen[id] and Cards.playable[id]);seen[id]=true;n=n+1
        local seq=D.spells[id].kind=="modifier" and {id,"spark","arrow"} or {id,"spark"}
        assert(compile(seq).projectile_count>0)
    end
end
assert(n==182 and #Cards.order==215 and Cards.codes.weak_homing==25)
assert(Cards.codes.frost_timer==45 and Cards.codes.mana_reduce==46 and Cards.codes.repeat_3==49)
for _,seq in ipairs({{"repeat_2","double","spark","arrow"},{"double","spark","repeat_2","arrow"}}) do
    local p=compile(seq)
    assert(p.projectile_count==4 and p.mana_spent==50)
    for i,id in ipairs({"spark","arrow","spark","arrow"}) do assert(p.blocks[1].projectiles[i].id==id) end
end
local outer=compile({"repeat_2","arrow_hit","slash"})
local inner=compile({"arrow_hit","repeat_2","slash"})
assert(outer.projectile_count==4 and inner.projectile_count==3 and outer.mana_spent==66 and inner.mana_spent==66)
assert(outer.blocks[1].projectiles[1].payload~=outer.blocks[1].projectiles[2].payload)
assert(#inner.blocks[2].projectiles==2)
local quad=compile({"repeat_4","arrow_hit","frost"})
assert(quad.projectile_count==8 and quad.mana_spent==92)
for i,p in ipairs(quad.blocks[1].projectiles) do
    local ice=quad.blocks[p.payload].projectiles[1]
    assert(math.abs(p.damage-9.9)<.001 and math.abs(ice.damage-4.05)<.001)
    assert((ice.freeze~=nil)==(i==1))
end
local fan=compile({"trident_cast","arrow_hit","slash","heavy","fire"})
local lanes=fan.blocks[1].projectiles
assert(#lanes==3 and lanes[1].formation==-20 and lanes[2].formation==0 and lanes[3].formation==20)
assert(fan.blocks[lanes[1].payload].projectiles[1].formation==nil)
local mod=compile({"heavy_shot","arrow"}).blocks[1].projectiles[1]
assert(mod.damage==34 and mod.speed==16.25 and mod.spread>=2)
local voices=compile({"repeat_4","chord_d"}).blocks[1].projectiles
assert(#voices==4 and not voices[1].suppress_support and voices[4].suppress_support)
local six=compile({"repeat_3","repeat_2","mana_reduce","spark"})
assert(six.projectile_count==6 and six.mana_spent==60 and #six.trace==4)
local discounted=compile({"mana_reduce","repeat_3","arrow"})
assert(discounted.mana_spent==28 and discounted.mana_required==28 and discounted.projectile_count==3)
local exact=compile({"repeat_2","repeat_2","scatter"})
assert(exact.projectile_count==12)
local w=require("nw/generator").starter()
w.cards={{spell_id="spark",card_uid="s"},{spell_id="repeat_2",card_uid="r"}}
w.runtime=C.initial(w.cards,w.stats,3)
w.runtime=assert(C.compile(w)).next_state
local wrapped=assert(C.compile(w))
assert(wrapped.wrapped and wrapped.projectile_count==2 and wrapped.mana_spent==40 and #wrapped.next_state.deck==2)
w.stats.cast_delay=.45;w.stats.recharge=.6
w.cards={{spell_id="recharge_down",card_uid="r"},{spell_id="spark",card_uid="s"},{spell_id="heavy",card_uid="h"}}
w.runtime=C.initial(w.cards,w.stats,3)
local fast=assert(C.compile(w))
assert(not fast.recharged and math.abs(fast.next_state.reload_delta+.43)<1e-9)
w.runtime=fast.next_state
local last=assert(C.compile(w))
assert(last.recharged and math.abs(last.next_state.remaining_recharge-.27)<1e-9 and last.next_state.reload_delta==0)
local halfangles={spark=3,arrow=1,heavy=4,scatter=2.5,fire=2.25,frost=2.25}
for _,id in ipairs(D.bullets) do
    for _,suffix in ipairs({"","_hit","_timer"}) do
        local spell=id..suffix
        local normal=compile({spell,"slash"}).blocks[1].projectiles[1]
        local precise=compile({"precision",spell,"slash"}).blocks[1].projectiles[1]
        assert(normal.spread==halfangles[id] and precise.spread==math.max(0,halfangles[id]-2))
        if id=="scatter" then
            assert(precise.angles[1]==-10 and precise.angles[2]==0 and precise.angles[3]==10)
        end
    end
    for _,mode in ipairs({"hit","timer"}) do
        local base=D.spells[id];local p=compile({id.."_"..mode,"slash"})
        local carrier=p.blocks[1].projectiles[1]
        assert(carrier.event==mode and carrier.base==id and carrier.damage==base.damage)
        assert(p.mana_spent==base.mana+(mode=="hit" and 4 or 5)+19)
        assert(p.blocks[carrier.payload].projectiles[1].kind=="melee")
    end
end
local p=compile({"imprint_hit","arrow_timer","whirl"})
assert(p.blocks[1].projectiles[1].event=="timer" and #p.blocks==2)
p=compile({"precision","precision","sine","homing","spiral","spark"})
assert(math.abs(p.blocks[1].projectiles[1].lifetime-.8*1.24)<1e-9 and p.blocks[1].projectiles[1].spread==0)
assert(math.abs(Flight.turn(0,math.pi,math.rad(4)))<=math.rad(4))
assert(compile({"orbit","spark"}).blocks[1].projectiles[1].lifetime==4)
assert(math.abs(compile({"orbit","speed_down","heavy"}).blocks[1].projectiles[1].lifetime-D.spells.heavy.lifetime*1.08*4*1.4)<1e-9)
for _,d in ipairs({"thrust","slash","whirl"}) do
    assert(Melee.contains(D.spells[d],.7,0,.2,0,1))
    assert(not Melee.contains(D.spells[d],5,0,.2,0,1))
end
-- Each scatter pellet prepays its own independent nested payload subtree.
DEGREES=math.pi/180
local objects,owner={}, {GUID=22,components={},IsValid=function() return true end}
SpawnPrefab=function()
    local obj={_shot={}}
    function obj:Launch(_,desc,x,z,dx,dz,cleanup) self.id=desc.id;self.x=x;self.z=z;self.cleanup=cleanup end
    function obj:Remove() self.cleanup() end
    table.insert(objects,obj);return obj
end
for _,fire in ipairs({true,false}) do
    objects={}
    assert(E.execute(compile({"scatter_hit","spark_timer","arrow"}),owner,1,3,1,0))
    assert(#objects==3 and E.stats()==9)
    if fire then
        for i=1,3 do objects[i]._shot.fire(9,12,0,1) end
        assert(#objects==6 and objects[4].x==9 and objects[4].z==12)
        objects[4]._shot.fire(10,16,0,1)
        assert(#objects==7 and objects[7].x==10)
    end
    for _,v in ipairs(objects) do v:Remove() end
    assert(E.stats()==0,"abandoned nested reservation leaked")
end
objects={}
-- Default configuration permits more than both former concurrent caps.
assert(E.execute(compile({"pierce_all","arrow_hit","spark_timer","arrow"}),owner,0,0,1,0))
for _=1,90 do objects[1]._shot.fire(0,0,1,0) end
assert(#objects==91 and E.stats()==181)
for _,obj in ipairs(objects) do obj:Remove() end
assert(E.stats()==0)
E.set_projectile_limit(true)
objects={}
assert(E.execute(compile({"pierce_all","arrow_hit","spark_timer","arrow"}),owner,0,0,1,0))
for _=1,50 do objects[1]._shot.fire(0,0,1,0) end
assert(E.stats()==23 and #objects==12,"replays exceeded concurrent subtree budget")
objects[2]:Remove()
objects[1]._shot.fire(0,0,1,0)
assert(#objects==13 and E.stats()==23,"replay did not resume after capacity freed")
for i,obj in ipairs(objects) do if i~=2 then obj:Remove() end end
assert(E.stats()==0)
objects={}
local single=compile({"spark"})
for i=1,160 do
    assert(E.execute(single,{GUID=math.ceil(i/24)},0,0,1,0))
end
local ok,err=E.execute(single,{GUID=100},0,0,1,0)
assert(not ok and err=="PROJECTILE_LIMIT")
E.set_projectile_limit(false)
assert(E.execute(single,{GUID=1},0,0,1,0) and E.stats()==161)
for _,obj in ipairs(objects) do obj:Remove() end
assert(E.stats()==0)
print("spell lab: 100 loadable cards, 12 imprint variants, 3 legacy IDs, geometry, timing and shared payload ownership")
