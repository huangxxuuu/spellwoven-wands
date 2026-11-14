local C=require("nw/constants/acquisition").rarity
local T=require("nw/locale").t
local M = { names={T("普通"),T("精良"),T("稀有"),T("史诗")}, weights=require("nw/util").copy(C.weights), tiers={}, pool={} }
local sets = C.sets
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
add("spore_sentry",C.tiers.spore_sentry)
add("vital_ring",C.tiers.vital_ring)
add("heavy_shot",C.tiers.heavy_shot)
add("trident_cast",C.tiers.trident_cast)
add("chord_d",C.tiers.chord_d)
add("repeat_4",C.tiers.repeat_4)
for _,card in ipairs(require("nw/expansion")) do add(card.id,card.tier) end
for _,c in ipairs(require("nw/arsenal").cards) do if not require("nw/engraved_spells").retired[c.id] and not require("nw/arsenal").legacy_notes[c.id] then add(c.id,c.tier) end end
add("giant_shot",C.tiers.giant_shot)
add("shrink_shot",C.tiers.shrink_shot)
add("short_life",C.tiers.short_life)
add("homing_rotate",C.tiers.homing_rotate)
add("gunpowder",C.tiers.gunpowder)
add("ocarina_g",C.tiers.ocarina_g)
for _,c in ipairs(require("nw/pitch_modifiers").cards) do add(c.id,c.tier) end
for _,c in ipairs(require("nw/arsenal").extra_notes) do add(c.id,c.tier) end
add("dark",C.tiers.dark)
return M
