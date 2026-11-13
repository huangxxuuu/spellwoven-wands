local rules = require("nw/acquisition")
local src = require("nw/sources")
local factory = require("nw/wand_factory")
local compiler = require("nw/compiler")
local cards = require("nw/cards")
local recycle = require("nw/recycle")
local rng = require("nw/rng").new(19369573)
local function random(n) return n and rng:int(n) or rng:next() end

local counts, writable = {}, {}
for _, r in ipairs(rules.recipes) do
    counts[r.product]=(counts[r.product] or 0)+1
    if r.card then
        assert(cards.playable[r.card] and (not writable[r.card] or r.card=="scatter"))
        writable[r.card]=true
        assert(r.ingredients[1][1]=="nw_blank" and r.ingredients[1][2]==1)
        for _,v in ipairs(r.ingredients) do assert(v[1]~="nw_dust") end
    end
    if r.tier then assert(r.tier<=3) end
    if r.product == "nw_dust" then
        assert(#r.ingredients==2 and r.ingredients[2][1]=="goldnugget" and r.count==4)
    end
end
local unique=0;for _ in pairs(writable) do unique=unique+1 end;assert(unique==151)
assert(counts.nw_wand==4 and counts.nw_dust==3 and counts.nw_spellcard==154 and counts.nw_overlord_core==3)
local blank = rules.by_name.nw_blank
local dust
for _, ingredient in ipairs(blank.ingredients) do
    if ingredient[1] == "nw_dust" then dust = ingredient[2] end
end
assert(dust==2 and blank.count==2)
local d = factory.build(0,"starter",nil,1)
assert(d.stats.capacity==2 and d.cards[1].spell_id=="spark" and not d.cards[2])
for tier=1,3 do
    d=factory.build(tier,"craft",nil,381); assert(d.tier==tier)
    for _,v in ipairs(d.cards) do assert(v==false) end
    assert(recycle.amount({components={nw_wand={data=d}}})==tier*4)
end
local epic=0
for name, rule in pairs(src.by_prefab) do
    if rule.group then
        local r=src.roll(name,rule,{},0,0,random)
        if rule.group=="D" then
            epic=epic+1;assert(r.tier==4 and r.core=="nw_overlord_core")
        else assert(not r.tier) end
        for i=1,48 do
            local data=factory.build(r.tier or 3,name,rule,random(1073741823))
            assert(data.always_cast~="weak_homing" and #data.cards==data.stats.capacity)
            local p=assert(compiler.compile(data))
            assert(p.projectile_count>0 and p.mana_spent<=data.stats.mana_max)
            assert(recycle.amount({components={nw_wand={data=data}}})==({4,8,12,20})[data.tier])
        end
    end
end
assert(epic==8 and not src.by_prefab.charlie_boss and not src.by_prefab.wagboss_robot and not src.by_prefab.stalker_npc)
local ncard,nwand=0,0
local knight=src.material_pool({gears=true})
for i=1,100000 do
    local r=src.roll("knight",src.by_prefab.knight,knight,1,1,random)
    if r.card then ncard=ncard+1;assert(writable[r.card]) end
    r=src.roll("dragonfly",src.by_prefab.dragonfly,{},1,1,random)
    if r.tier then nwand=nwand+1;assert(r.tier==3) end
end
assert(math.abs(ncard-12000)<500 and math.abs(nwand-40000)<800)
local old={cards={{card_uid="prototype:1"},false,{card_uid="slot:3:8"}},runtime={deck={"slot:3:8"},discard={"prototype:1"}}}
factory.upgrade(old)
assert(old.runtime.deck[1]==old.cards[3].card_uid and old.runtime.discard[1]==old.cards[1].card_uid)
local id=old.wand_uid;factory.upgrade(old);assert(old.wand_uid==id)
print("acquisition: 8 epic encounter endpoints, fixed cores, playable loadouts, recipes, legacy draw order, 100000 rate samples")
