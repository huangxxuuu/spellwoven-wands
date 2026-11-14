local C=require("nw/constants/wands")
local T=require("nw/locale").t
local G = require("nw/generator")
local Def = require("nw/definitions")
local Rules = require("nw/acquisition")
local RNG = require("nw/rng")
local Compiler = require("nw/compiler")
local M = {}

function M.uid()
    return TheWorld.components.nw_identity:Next()
end
function M.card(id, origin)
    return {card_uid=M.uid(), spell_id=id, source=origin}
end
function M.build(tier, source, theme, seed, loadout_seed, cosmetic_roll)
    local data
    if tier == 0 then
        data = G.starter(cosmetic_roll)
    else
        local rng = RNG.new(seed)
        local pool = {}
        for _, kind in ipairs(Def.archetypes) do table.insert(pool,kind) end
        if theme then
            for _, kind in ipairs(theme.kinds) do
                for _=1,C.theme_weight_copies do table.insert(pool,kind) end
            end
        end
        local kind = pool[rng:int(#pool)]
        rng:next()
        data = G.generate(rng.state, tier, kind, cosmetic_roll)
        data.origin_seed = seed
    end
    data.wand_uid, data.source = M.uid(), source
    data.starter = tier == 0
    data.cards = {}
    local loadout
    if theme then
        data.loadout_seed=loadout_seed or seed
        local rng=RNG.new(data.loadout_seed)
        loadout=require("nw/sources").wand_cards(theme,data.stats.capacity,function(n)
            if n then return rng:int(n) end
            return rng:next()
        end,data.stats.mana_max)
    end
    for i=1,data.stats.capacity do
        local id = tier == 0 and i == 1 and "spark" or loadout and loadout[i]
        data.cards[i] = id and M.card(id,source) or false
    end
    data.config_revision = 1
    data.runtime = Compiler.initial(data.cards, data.stats, data.seed)
    return data
end
function M.stat_text(data)
    local s = data.stats
    local innate = data.always_cast and require("nw/cards").names[data.always_cast]
    return string.format(T("%s    同发 %d    散射 %g°\n施放 %g 秒    充能 %g 秒\n法力 %g    回复 %g/秒    理智转化率 %g"),
        s.shuffle and T("乱序") or T("非乱序"),s.draw_count,s.spread,s.cast_delay,s.recharge,s.mana_max,
        s.mana_regen,G.sanity_conversion_for(s))..(innate and (T("\n固有  ")..innate) or "")
end
function M.describe(data)
    return string.format(T("%s · %d 格\n%s"), M.name(data), data.stats.capacity, M.stat_text(data))
end
function M.name(data)
    return data.starter and T("入门法杖") or (Rules.tiers[data.tier].." · "..Rules.kinds[data.archetype]..T("法杖"))
end

function M.upgrade(data)
    if data.wand_uid then return end
    data.wand_uid, data.source = M.uid(), "legacy"
    local changed = {}
    for _, card in ipairs(data.cards) do
        if card then
            local id = M.uid()
            changed[card.card_uid] = id
            card.card_uid, card.source = id, "legacy"
        end
    end
    for _, pile in ipairs({data.runtime.deck,data.runtime.discard}) do
        for i, old in ipairs(pile) do pile[i] = changed[old] or old end
    end
end
return M
