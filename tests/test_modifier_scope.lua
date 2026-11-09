-- Verified against installed Noita data.wak, build
-- 9dbd52ced019a643169a2db02f46c77f8766c6e5 (2026-11-09 audit).
-- gun.lua: draw_shot uses one c, then register_action/SetProjectileConfigs;
-- create_shot resets payload state. gun_actions.lua: BURST_2 draws into c,
-- DAMAGE changes c and draws one more action. No proprietary source included.
local C=require("nw/compiler")
local function cast(ids,draws)
    local w=require("nw/generator").starter()
    w.stats.mana_max=1000;w.stats.draw_count=draws or 1;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,1)
    return assert(C.compile(w)),w
end
for _,ids in ipairs({
    {"damage_up","double","spark","arrow"},
    {"double","damage_up","spark","arrow"},
    {"double","spark","damage_up","arrow"},
}) do
    local p=cast(ids)
    assert(p.blocks[1].projectiles[1].damage==28 and p.blocks[1].projectiles[2].damage==32)
end
local p=cast({"spark","damage_up","arrow"},2)
assert(p.blocks[1].projectiles[1].damage==28 and p.blocks[1].projectiles[2].damage==32,"native draw count also shares a block")
p=cast({"damage_up","spark_hit","spark"})
assert(p.blocks[1].projectiles[1].damage==28 and p.blocks[2].projectiles[1].damage==18)
p=cast({"spark_hit","damage_up","spark"})
assert(p.blocks[1].projectiles[1].damage==18 and p.blocks[2].projectiles[1].damage==28)
p=cast({"double","spark_hit","spark","damage_up","arrow"})
assert(p.blocks[1].projectiles[1].damage==28 and p.blocks[1].projectiles[2].damage==32)
assert(p.blocks[2].projectiles[1].damage==18,"late outer modifier cannot cross into a finished payload")
p=cast({"spark_hit","double","spark","damage_up","arrow"})
assert(p.blocks[1].projectiles[1].damage==18)
assert(p.blocks[2].projectiles[1].damage==28 and p.blocks[2].projectiles[2].damage==32)
local first,w=cast({"spark","damage_up","arrow"})
w.runtime=first.next_state;local second=assert(C.compile(w))
assert(first.blocks[1].projectiles[1].damage==18 and second.blocks[1].projectiles[1].damage==32,"later casts cannot retroactively modify an earlier block")
print("Noita scope: shared multicast/root-draw modifiers, independent payload blocks, no cross-cast effects")
