local C = require("nw/compiler")
local G = require("nw/generator")
local D = require("nw/definitions")
local U = require("nw/util")
local function eq(a,b)
    if type(a) == "number" and type(b) == "number" then
        assert(math.abs(a-b) < 1e-9, tostring(a).." ~= "..tostring(b)); return
    end
    assert(a == b, tostring(a).." ~= "..tostring(b))
end
local function wand(spells, mana, draws)
    local w = G.starter()
    w.stats.mana_max = mana or 500
    w.stats.draw_count = draws or 1
    w.cards = {}
    for i, id in ipairs(spells) do w.cards[i] = {card_uid=tostring(i),spell_id=id} end
    w.runtime = C.initial(w.cards, w.stats, 1)
    return w
end
local function cast(w)
    local p,e = C.compile(w)
    assert(p,e)
    w.runtime = p.next_state
    return p
end
local w = wand({"spark","double","arrow"})
eq(cast(w).projectile_count, 1)
local p = cast(w)
eq(p.projectile_count,2); eq(p.wrapped,true);eq(p.recharged,true)
eq(p.blocks[1].projectiles[1].id,"arrow")
eq(p.blocks[1].projectiles[2].id,"spark")
eq(p.mana_spent,15)
p = cast(wand({"double","spark"}))
eq(p.projectile_count,1);eq(p.wrapped,false)
w = wand({"spark","damage_up"});cast(w);p=cast(w)
eq(p.wrapped,true);eq(p.blocks[1].projectiles[1].damage,28)
p=cast(wand({"double","arrow","damage_up","arrow"}))
eq(p.blocks[1].projectiles[1].damage,32);eq(p.blocks[1].projectiles[2].damage,32)
p=cast(wand({"spark"},100,2));eq(p.projectile_count,1);eq(p.wrapped,false)
p=cast(wand({"double","heavy","spark","arrow"},17))
eq(p.projectile_count,2);eq(p.mana_spent,15)
p=cast(wand({"damage_up","heavy","spark"},20))
eq(p.next_state.mana,7);eq(p.blocks[1].projectiles[1].damage,28)
p=cast(wand({"damage_up","trigger_hit","spark"}))
eq(p.blocks[1].projectiles[1].damage,20);eq(p.blocks[2].projectiles[1].damage,18)
p=cast(wand({"trigger_hit","damage_up","spark"}))
eq(p.blocks[1].projectiles[1].damage,10);eq(p.blocks[2].projectiles[1].damage,28)
p=cast(wand({"heavy","arrow"},0));eq(p.projectile_count,0);eq(p.recharged,true)
p=cast(wand({"double","spark","arrow","heavy"},500,2));eq(p.projectile_count,3)
w=wand({"spark","arrow"});w.stats.shuffle=true
p=cast(w);eq(p.blocks[1].projectiles[1].id,"spark") -- fixed current deck, no per-card shuffle
w=wand({"trigger_hit","trigger_hit","trigger_hit","spark"})
local old=U.copy(w.runtime)
assert(C.compile(w),"nesting beyond two levels is allowed by default")
local failed,err=C.compile(w,nil,{depth=2});eq(failed,nil);eq(err,"COMPILE_LIMIT")
eq(w.runtime.mana,old.mana);eq(#w.runtime.deck,#old.deck)
w=wand({"double","spark"});failed,err=C.compile(w,nil,{nodes=1})
eq(failed,nil);eq(err,"COMPILE_LIMIT");eq(w.runtime.mana,500)
p=cast(wand({"double","heavy","heavy"}));eq(p.next_state.remaining_recharge,1.6)
w=wand({"spark"});w.always_cast="speed_up";p=cast(w)
eq(p.mana_spent,5);eq(p.blocks[1].projectiles[1].speed,28.25)
w=wand({"spark"});w.runtime.discard={"1"};failed,err=C.compile(w)
eq(err,"INVALID_DECK")
eq(#D.order,214)
print("rules: 17 scenarios + 102 standard/legacy definitions")

-- Conservation across repeated casts, including shuffle, skipped cards and wraps.
local R=require("nw/rng").new(123)
for case=1,200 do
    local ids={}
    for i=1,R:int(12) do ids[i]=D.order[R:int(#D.order)] end
    local x=wand(ids,120,R:int(3));x.stats.shuffle=case%2==0
    x.runtime=C.initial(x.cards,x.stats,case)
    for shot=1,20 do
        local before=U.copy(x.runtime)
        local result=C.compile(x)
        if result then x.runtime=result.next_state
        else eq(x.runtime.mana,before.mana);eq(#x.runtime.deck,#before.deck) end
        local seen,n={},0
        for _,area in ipairs({x.runtime.deck,x.runtime.discard}) do
            for _,id in ipairs(area) do assert(not seen[id]);seen[id]=true;n=n+1 end
        end
        eq(n,#x.cards)
        assert(x.runtime.mana>=0 and x.runtime.mana<=120)
        x.runtime.mana=math.min(120,x.runtime.mana+7)
    end
end
print("rules: 4000 additional randomized casts conserve cards and mana")
