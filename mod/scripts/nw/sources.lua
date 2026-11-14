local C=require("nw/constants/acquisition").sources
local Rarity = require("nw/card_rarity")
local Rules = require("nw/acquisition")
local M = {by_prefab={}}
local groups = C.groups
local function register(names, rule)
    for name in names:gmatch("%S+") do
        assert(not M.by_prefab[name], "duplicate reward: "..name)
        M.by_prefab[name] = rule
    end
end
local function boss(names, group, kinds, cards, event)
    register(names, {group=group,kinds=kinds,cards=cards,event=event or "death"})
end
local frost, beast, arcane = {"precision","arrow","spark"}, {"damage_up","heavy","spark"}, {"double","spark","arrow"}
local brute, agile, magic = {"reservoir","chaos"}, {"rapid","renewal"}, {"weaver","renewal"}
boss("deerclops","A",magic,frost)
boss("bearger","A",brute,beast)
boss("moose","A",agile,arcane)
boss("dragonfly","B",brute,beast)
boss("beequeen","B",magic,arcane)
boss("minotaur","B",{"reservoir","weaver"},beast)
boss("klaus","B",magic,frost,"dropkey")
boss("toadstool toadstool_dark crabking","C",brute,beast)
boss("alterguardian_phase3 stalker_atrium","C",magic,arcane)
boss("mutateddeerclops","D",magic,frost)
boss("mutatedbearger","D",brute,beast)
boss("mutatedwarg","D",agile,{"speed_up","scatter","spark"})
boss("rocky_boss_shadow","D",brute,beast)
boss("bat_boss_shadow","D",agile,arcane)
boss("worm_boss_shadow","D",brute,beast,"loot")
boss("alterguardian_phase4_lunarrift","D",magic,arcane,"loot")
boss("shrouden","D",magic,beast,"ms_charlie_boss_defeated")
boss("daywalker","B",brute,beast,"loot")
boss("vault_pillar_guard","C",brute,arcane,"loot")
boss("shadowthrall_centipede_controller","B",brute,beast)
boss("rocky_boss bat_boss","A",agile,frost)
boss("worm_boss","B",brute,beast,"loot")
local function dust(names, chance, count)
    register(names, {dustchance=chance,dust=count,event="death"})
end
for _,row in ipairs(C.dust) do dust(row.prefabs,row.chance,row.count) end

local function set(names)
    local result={}
    for name in names:gmatch("%S+") do result[name]=true end
    return result
end
local dense=set("spider bee killerbee beeguard mosquito hound crow robin robin_winter canary puffin butterfly rabbit bunnyman birchnutdrake penguin monkey lightflier babybeefalo pigman shadow_leech")
local limited=set("walrus tentacle worm knight knight_nightmare knight_yoth bishop bishop_nightmare rook rook_nightmare tentacle_pillar")
local otherboss=set("antlion daywalker2 eyeofterror twins leif leif_sparse lordfruitfly malbatross spiderqueen shadow_bishop shadow_rook shadow_knight stalker stalker_forest sharkboi")
local rates=C.rates
local specials=C.specials
local function card_budget(name,group)
    return rates[group] or (otherboss[name] and C.budget.otherboss) or (limited[name] and C.budget.limited) or (dense[name] and C.budget.dense) or C.budget.ordinary
end
local signature={}
M.signature=signature
local function exclusive(name,id,rate)
    local entries=signature[name] or {total=0}
    signature[name]=entries
    entries[#entries+1]={id=id,rate=rate}
    entries.total=entries.total+rate
end
for _,entry in ipairs(C.signature) do exclusive(entry.prefab,entry.id,entry.rate) end

for name,entries in pairs(signature) do
    local rule=M.by_prefab[name]
    local budget=card_budget(name,rule and rule.group)
    if entries.total>=budget-C.signature_epsilon then
        local scale=C.signature_budget_fraction*budget/entries.total
        entries.total=0
        for _,entry in ipairs(entries) do
            entry.rate=entry.rate*scale
            entries.total=entries.total+entry.rate
        end
    end
end

function M.material_pool(materials,group)
    local ids,seen={},{}
    local function add(material)
        for _,id in ipairs(Rules.by_material[material] or {}) do
            if not seen[id] then ids[#ids+1]=id;seen[id]=true end
        end
    end
    for material in pairs(materials) do add(material) end
    if group=="A" then add("nw_beast_core") end
    table.sort(ids)
    return ids
end
local function weight(id) return Rarity.weights[Rarity.tiers[id]] end
local function total_weight(pool)
    local total=0
    for _,id in ipairs(pool) do total=total+weight(id) end
    return total
end
local function pick(pool,rng)
    local roll=rng()*total_weight(pool)
    for _,id in ipairs(pool) do
        roll=roll-weight(id)
        if roll<0 then return id end
    end
    return pool[#pool]
end
local bullets=set("spark arrow heavy scatter fire frost")
local function variant(id,rate,rng)
    if not bullets[id] then return id end
    local r=rng()
    if r<rate then return id.."_hit" elseif r<2*rate then return id.."_timer" end
    return id
end
local function loose_card(name,group,pool,mult,rng)
    if mult<=0 then return end
    local base=card_budget(name,group)
    local sig=signature[name]
    local s=sig and sig.total or 0
    local chance=s+(base-s)*math.min(1,total_weight(pool))
    if chance==0 then return end
    local roll=rng()*math.max(1/mult,chance)
    if roll<s then
        local cumulative=0
        for _,entry in ipairs(sig) do
            cumulative=cumulative+entry.rate
            if roll<cumulative then return entry.id end
        end
    end
    if roll<chance then return variant(pick(pool,rng),C.loose_variant_rate,rng) end
end
function M.roll(name,rule,pool,cardmult,wandmult,rng)
    local reward={}
    local group=rule.group
    if group then
        local g=groups[group]
        reward.core=not require("nw/balance").is_balanced() and g.core or nil
        reward.dust=g.dust
        if group=="D" or rng()<math.min(1,g.chance*wandmult) then reward.tier=g.tier end
    elseif rule.dustchance and rng()<rule.dustchance then
        reward.dust=rule.dust
    end
    reward.card=loose_card(name,group,pool,cardmult,rng)
    return reward
end

local fallback={}
for _,id in ipairs(Rarity.pool) do
    if id~="edge_propsign" then fallback[#fallback+1]=id end
end

function M.finish_card(hp,card,has_wand_cards,mult,rng)
    if card then return card end
    local chance=require("nw/balance").is_loot_only() and C.fallback_loot_only_chance or C.fallback_chance
    if not has_wand_cards and hp>C.fallback_min_health and mult>0 and rng()<chance*mult then
        return fallback[rng(#fallback)]
    end
end

local spells=require("nw/definitions").spells
local function affordable_card(id, limit, primary)
    if spells[id].mana<=limit then return id end
    local base=spells[id].base
    if base and spells[base].mana<=limit then return base end
    return spells[primary].mana<=limit and primary or "spark"
end

function M.wand_cards(theme,capacity,rng,mana_max)
    mana_max=mana_max or math.huge
    local attack,pool,seen={},{},{}
    for _,id in ipairs(theme.cards) do
        if bullets[id] then attack[#attack+1]=id end
        pool[#pool+1]=id;seen[id]=true
    end
    for _,id in ipairs(theme.material_pool or {}) do
        if not seen[id] then pool[#pool+1]=id end
    end
    local carrier=pick(attack,rng)
    if rng()<specials[theme.group] then
        local special=capacity<C.special_min_capacity and "heal_ally" or C.special_cards[rng(#C.special_cards)]
        local payload=special~="heal_ally" and "spark" or nil
        local available=mana_max-spells[special].mana-(payload and spells[payload].mana or 0)
        return {special,affordable_card(carrier,available,carrier),payload}
    end
    local primary=variant(carrier,C.wand_variant_rate,rng)
    local bonus=affordable_card(variant(pick(pool,rng),C.wand_variant_rate,rng),mana_max-spells.spark.mana,carrier)
    return {affordable_card(primary,mana_max-spells[bonus].mana,carrier),bonus}
end
return M
