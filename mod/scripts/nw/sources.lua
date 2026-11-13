local Rarity = require("nw/card_rarity")
local Rules = require("nw/acquisition")
local M = {by_prefab={}}
local groups = {
    A={chance=.25,tier=2,core="nw_beast_core",dust=6},
    B={chance=.40,tier=3,core="nw_overlord_core",dust=10},
    C={chance=.60,tier=3,core="nw_overlord_core",dust=16},
    D={chance=1,tier=4,core="nw_overlord_core",dust=16},
}
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
dust("spider hound bat",.3,1)
dust("spider_warrior tentacle firehound icehound",1,1)
dust("knight bishop rook",1,2)

local function set(names)
    local result={}
    for name in names:gmatch("%S+") do result[name]=true end
    return result
end
local dense=set("spider bee killerbee beeguard mosquito hound crow robin robin_winter canary puffin butterfly rabbit bunnyman birchnutdrake penguin monkey lightflier babybeefalo pigman shadow_leech")
local limited=set("walrus tentacle worm knight knight_nightmare knight_yoth bishop bishop_nightmare rook rook_nightmare tentacle_pillar")
local otherboss=set("antlion daywalker2 eyeofterror twins leif leif_sparse lordfruitfly malbatross spiderqueen shadow_bishop shadow_rook shadow_knight stalker stalker_forest sharkboi")
local rates={A=.30,B=.45,C=.55,D=.65}
local specials={A=.08,B=.12,C=.18,D=.24}
local function card_budget(name,group)
    return rates[group] or (otherboss[name] and .30) or (limited[name] and .12) or (dense[name] and .02) or .06
end
local signature={}
M.signature=signature
local function exclusive(name,id,rate)
    local entries=signature[name] or {total=0}
    signature[name]=entries
    entries[#entries+1]={id=id,rate=rate}
    entries.total=entries.total+rate
end
exclusive("pigman","edge_propsign",.005)
exclusive("mutatedbearger","repeat_4",.08)
exclusive("crabking","repeat_4",.03)
exclusive("worm","phase_wall",.03)
exclusive("stalker_atrium","phase_wall",.12)
exclusive("daywalker","phase_wall",.04)
exclusive("bearger","pierce_all",.02)
exclusive("rook_nightmare","pierce_all",.03)
exclusive("minotaur","pierce_all",.12)
exclusive("dragonfly","repeat_3",.03)
exclusive("beequeen","repeat_3",.03)
exclusive("klaus","repeat_3",.04)
exclusive("toadstool","repeat_3",.05)
exclusive("toadstool_dark","repeat_3",.05)
exclusive("alterguardian_phase4_lunarrift","repeat_3",.16)
exclusive("shrouden","repeat_3",.16)

exclusive("robin","wild_double",.005)
exclusive("moose","wild_double",.12)
exclusive("hound","near_homing",.005)
exclusive("warg","near_homing",.08)
exclusive("killerbee","bee_swarm",.004)
exclusive("beequeen","bee_swarm",.15)
exclusive("lightflier","fireflies",.02)
exclusive("lightcrab","fireflies",.08)
exclusive("moonbutterfly","glass_disc",.01)
exclusive("mutatedhound","glass_disc",.04)
exclusive("spider_warrior","crit_rune",.008)
exclusive("spiderqueen","crit_rune",.10)
exclusive("alterguardian_phase3","star_vortex",.10)
exclusive("mutatedhound","star_vortex",.02)
exclusive("alterguardian_phase3","moon_fall",.12)
exclusive("rocky","moon_fall",.01)
exclusive("lightninggoat","tri_electric",.03)
exclusive("moose","tri_electric",.08)
exclusive("lightninggoat","shock_ring",.02)
exclusive("moose","shock_ring",.08)
exclusive("lightninggoat","storm_cloud",.01)
exclusive("moose","storm_cloud",.12)
exclusive("deer","deer_decoy",.01)
exclusive("klaus","deer_decoy",.15)
exclusive("slurper","vortex",.02)
exclusive("crabking","vortex",.12)
exclusive("firehound","searing_halo",.01)
exclusive("dragonfly","searing_halo",.08)
exclusive("firehound","side_embers",.01)
exclusive("dragonfly","side_embers",.12)
exclusive("bishop","twin_arc",.03)
exclusive("minotaur","twin_arc",.12)
exclusive("bishop_nightmare","end_beam",.03)
exclusive("minotaur","end_beam",.12)

-- When signature odds exhaust a species budget, reserve one fifth for material cards.
for name,entries in pairs(signature) do
    local rule=M.by_prefab[name]
    local budget=card_budget(name,rule and rule.group)
    if entries.total>=budget-1e-10 then
        local scale=.8*budget/entries.total
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
    -- Normalize mutually exclusive outcomes proportionally if a multiplier caps total odds at 100%.
    local roll=rng()*math.max(1/mult,chance)
    if roll<s then
        local cumulative=0
        for _,entry in ipairs(sig) do
            cumulative=cumulative+entry.rate
            if roll<cumulative then return entry.id end
        end
    end
    if roll<chance then return variant(pick(pool,rng),.10,rng) end
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
    local chance=require("nw/balance").is_loot_only() and .0005 or .0001
    if not has_wand_cards and hp>200 and mult>0 and rng()<chance*mult then
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
        local special=capacity<3 and "heal_ally" or ({"imprint_hit","imprint_timer","heal_ally"})[rng(3)]
        local payload=special~="heal_ally" and "spark" or nil
        local available=mana_max-spells[special].mana-(payload and spells[payload].mana or 0)
        return {special,affordable_card(carrier,available,carrier),payload}
    end
    local primary=variant(carrier,.15,rng)
    local bonus=affordable_card(variant(pick(pool,rng),.15,rng),mana_max-spells.spark.mana,carrier)
    return {affordable_card(primary,mana_max-spells[bonus].mana,carrier),bonus}
end
return M
