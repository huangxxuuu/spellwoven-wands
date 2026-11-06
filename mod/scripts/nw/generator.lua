local D=require("nw/definitions")
local R=require("nw/wand_generation")
local RNG=require("nw/rng")
local Visual=require("nw/visual")
local M={sanity_conversion=20}
local distributions={}

-- Discrete truncated Gaussian: normalize only legal values, so no clamped
-- overflow accumulates at either endpoint. Cached CDFs make sampling bounded.
local function sample(rng,tier,kind,key)
    local cachekey=tier..":"..kind..":"..key
    local dist=distributions[cachekey]
    if not dist then
        local lo,hi,centre,sigma,step=R.distribution(tier,kind,key)
        dist={total=0}
        for i=math.ceil(lo/step-.000001),math.floor(hi/step+.000001) do
            local value=math.floor(i*step*100000+.5)/100000
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
    for i=1,math.min(capacity,6) do total=total+profile.draw[i] end
    local pick=rng:next()*total
    for i=1,math.min(capacity,6) do
        pick=pick-profile.draw[i]
        if pick<0 then return i end
    end
end
function M.generate(seed,tier,archetype,cosmetic_roll)
    assert(type(tier)=="number" and tier>=1 and tier<=4 and tier==math.floor(tier),"invalid tier")
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
    return {schema_version=1,generator_version=3,seed=seed,tier=tier,archetype=archetype,
        stats=stats,always_cast=always,
        appearance=Visual.appearance(stats,cosmetic_roll or (rng:int(Visual.cosmetic_rolls)-1))}
end
function M.starter(cosmetic_roll)
    local stats = { capacity = 2, sanity_conversion = M.sanity_conversion, mana_max = 120, mana_regen = 18, cast_delay = .65,
        recharge = 1.4, draw_count = 1, spread = 6, shuffle = false }
    return { schema_version = 1, generator_version = 1, seed = 1, tier = 1,
        archetype = "sprout", stats = stats, appearance = Visual.appearance(stats,cosmetic_roll or 0) }
end
return M
