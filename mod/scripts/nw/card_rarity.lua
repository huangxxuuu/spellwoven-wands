local T=require("nw/locale").t
local M = { names={T("普通"),T("精良"),T("稀有"),T("史诗")}, weights={1,.65,.35,.20}, tiers={}, pool={} }
local sets = {
    "spark arrow heavy scatter thrust whirl precision speed_down",
    "fire frost slash sine spiral bounce orbit speed_up damage_up pierce knockback light double",
    "homing explosion chain leech mana_reduce recharge_down triple phase_wall pierce_all imprint_hit imprint_timer heal_ally",
    "repeat_2 repeat_3",
}
local function add(id,tier)
    M.tiers[id]=tier
    M.pool[#M.pool+1]=id
end
for tier,ids in ipairs(sets) do
    for id in ids:gmatch("%S+") do add(id,tier) end
end
for _,id in ipairs(require("nw/definitions").bullets) do
    add(id.."_hit",M.tiers[id]+1)
    add(id.."_timer",M.tiers[id]+1)
end
add("spore_sentry",2)
add("vital_ring",3)
add("heavy_shot",2)
add("trident_cast",2)
add("chord_d",2)
add("repeat_4",4)
for _,card in ipairs(require("nw/expansion")) do add(card.id,card.tier) end
for _,c in ipairs(require("nw/arsenal").cards) do if not require("nw/engraved_spells").retired[c.id] then add(c.id,c.tier) end end
add("giant_shot",3)
add("short_life",2)
add("homing_rotate",2)
add("gunpowder",2)
return M
