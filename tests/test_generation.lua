local G=require("nw/generator")
local D=require("nw/definitions")
local R=require("nw/wand_generation")
local RNG=require("nw/rng")
local r=RNG.new(1)
r:next();assert(r.state==16807);r:next();assert(r.state==282475249)
local means,full_six={},false
for tier=1,4 do
    means[tier]={}
    for _,kind in ipairs(D.archetypes) do
        local sums,extreme,draws,innates={},0,{},0
        for _,key in ipairs(R.keys) do sums[key]=0 end
        for i=1,1000 do
            local seed=r:int(2147483646)
            local a=G.generate(seed,tier,kind)
            local b=G.generate(seed,tier,kind)
            assert(a.generator_version==3 and a.generation_budget==nil and a.budget_remaining==nil)
            local s=a.stats
            local bad=false
            for _,key in ipairs(R.keys) do
                local lo,hi,centre,sigma,step=R.distribution(tier,kind,key)
                local bounds=R.bounds[key]
                assert(s[key]>=lo and s[key]<=hi and s[key]>=bounds[1] and s[key]<=bounds[2])
                assert(math.abs(s[key]/step-math.floor(s[key]/step+.5))<.00001)
                assert(s[key]==b.stats[key])
                sums[key]=sums[key]+s[key]
                if math.abs(s[key]-centre)>2*sigma then bad=true end
            end
            if bad then extreme=extreme+1 end
            assert(s.draw_count>=1 and s.draw_count<=6 and s.draw_count<=s.capacity)
            assert(s.draw_count==b.stats.draw_count and s.shuffle==b.stats.shuffle and a.always_cast==b.always_cast)
            assert(a.appearance.head_id==b.appearance.head_id)
            assert(a.appearance.length_class==(s.capacity<=4 and "short" or s.capacity<=8 and "medium" or "long"))
            assert(a.appearance.head_id:find("head_"..(s.shuffle and "plain" or "crystal").."_"..math.min(3,s.draw_count).."_",1,true)==1)
            if kind=="chaos" then assert(s.shuffle) end
            if kind=="sprout" or kind=="weaver" then assert(not s.shuffle) end
            if kind=="rapid" then assert(s.mana_regen>=5/s.cast_delay) end
            if a.always_cast then innates=innates+1 end
            draws[s.draw_count]=(draws[s.draw_count] or 0)+1
            if s.draw_count==6 and not full_six then
                local C=require("nw/compiler")
                a.cards={};for slot=1,s.capacity do a.cards[slot]={card_uid=tostring(slot),spell_id="spark"} end
                a.runtime=C.initial(a.cards,s,seed)
                local plan=assert(C.compile(a))
                assert(plan.projectile_count==6 and plan.mana_spent==30)
                full_six=true
            end
        end
        assert(extreme/1000<.40,"too many wands with any two-sigma outlier: "..tier..kind)
        assert(math.abs(innates/1000-R.tiers[tier].always)<.05)
        assert(draws[1] and draws[2])
        for _,key in ipairs(R.keys) do sums[key]=sums[key]/1000 end
        means[tier][kind]=sums
        if tier>1 then
            for _,key in ipairs(R.keys) do
                local prior=means[tier-1][kind][key]
                if key=="cast_delay" or key=="recharge" or key=="spread" then assert(sums[key]<prior)
                else assert(sums[key]>prior) end
            end
        end
    end
    local base=means[tier].sprout
    assert(means[tier].rapid.cast_delay<base.cast_delay and means[tier].rapid.mana_max<base.mana_max)
    assert(means[tier].reservoir.mana_max>base.mana_max and means[tier].reservoir.mana_regen<base.mana_regen)
    assert(means[tier].renewal.mana_regen>base.mana_regen and means[tier].renewal.mana_max<base.mana_max)
    assert(means[tier].weaver.capacity>base.capacity and means[tier].weaver.cast_delay>base.cast_delay)
end
assert(full_six)
local s=G.starter().stats
assert(s.capacity==2 and s.mana_max==120 and s.mana_regen==18 and s.cast_delay==.65 and s.recharge==1.4)
assert(not pcall(G.generate,1,0) and not pcall(G.generate,1,1,"invalid"))
print("generation: 24000 v3 wands, deterministic truncated Gaussians, rarity progression, six type tradeoffs, <40% whole-wand outliers, valid multishot and fixed starter")
