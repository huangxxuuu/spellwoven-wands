local C=require("nw/constants/wands")
local D=require("nw/definitions")
local R=require("nw/wand_generation")
local RNG=require("nw/rng")
local Visual=require("nw/visual")
local Balance=require("nw/balance")
local M={sanity_conversion=C.sanity_conversion}
local distributions={}

function M.sanity_conversion_for(stats)
    local base=stats and stats.sanity_conversion or M.sanity_conversion
    return base*(Balance.is_balanced() and C.balance.sanity_conversion_mult or 1)
end

local function sample(rng,tier,kind,key)
    local cachekey=tier..":"..kind..":"..key..":"..tostring(Balance.is_balanced())
    local dist=distributions[cachekey]
    if not dist then
        local lo,hi,centre,sigma,step=R.distribution(tier,kind,key)
        dist={total=0}
        for i=math.ceil(lo/step-C.distribution.epsilon),math.floor(hi/step+C.distribution.epsilon) do
            local value=math.floor(i*step*C.distribution.precision+.5)/C.distribution.precision
            dist.total=dist.total+math.exp(-.5*((value-centre)/sigma)^2)
            dist[#dist+1]={value,dist.total}
        end
        assert(#dist>0 and dist.total>0,"empty wand distribution")
        distributions[cachekey]=dist
    end
    local pick=rng:next()*dist.total
    for _,row in ipairs(dist) do if pick<row[2] then return row[1] end end
    return dist[#dist][1]
end
local function draw_count(rng,profile,capacity)
    local total=0
    for i=1,math.min(capacity,C.distribution.max_draw) do total=total+profile.draw[i] end
    local pick=rng:next()*total
    for i=1,math.min(capacity,C.distribution.max_draw) do
        pick=pick-profile.draw[i]
        if pick<0 then return i end
    end
end
function M.generate(seed,tier,archetype,cosmetic_roll)
    assert(type(tier)=="number" and tier>=C.distribution.min_tier and tier<=C.distribution.max_tier and tier==math.floor(tier),"invalid tier")
    local rng=RNG.new(seed)
    archetype=archetype or D.archetypes[rng:int(#D.archetypes)]
    local profile=assert(R.types[archetype],"invalid archetype")
    local stats={sanity_conversion=M.sanity_conversion}
    for _,key in ipairs(R.keys) do stats[key]=sample(rng,tier,archetype,key) end
    stats.draw_count=draw_count(rng,profile,stats.capacity)
    stats.shuffle=profile.shuffle
    if stats.shuffle==nil then stats.shuffle=rng:next()<R.tiers[tier].shuffle end
    local always
    if rng:next()<R.tiers[tier].always then always=D.always[rng:int(#D.always)] end
    return {schema_version=C.schema_version,generator_version=C.generator_version,seed=seed,tier=tier,archetype=archetype,
        stats=stats,always_cast=always,
        appearance=Visual.appearance(stats,cosmetic_roll or (rng:int(Visual.cosmetic_rolls)-1))}
end
function M.starter(cosmetic_roll)
    local stats = { capacity = C.starter.capacity, sanity_conversion = M.sanity_conversion, mana_max = C.starter.mana_max, mana_regen = C.starter.mana_regen, cast_delay = C.starter.cast_delay,
        recharge = Balance.is_balanced() and C.balance.starter_recharge or C.starter.recharge, draw_count = C.starter.draw_count, spread = C.starter.spread, shuffle = false }
    return { schema_version = C.schema_version, generator_version = C.starter_generator_version, seed = C.starter.seed, tier = C.starter.tier,
        archetype = C.starter.archetype, stats = stats, appearance = Visual.appearance(stats,cosmetic_roll or 0) }
end
return M
