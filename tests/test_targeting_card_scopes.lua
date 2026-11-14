-- Every registered card uses the same compiled selector representation. This
-- guards new card families, repeated plans and nested payload scope boundaries.
local D=require("nw/definitions")
local C=require("nw/compiler")
local Cards=require("nw/cards")
local selectors={}
for _,id in ipairs(Cards.order) do
    if D.spells[id].select_target then selectors[#selectors+1]=id end
end
assert(#selectors==7)
local cases=0
for _,selector in ipairs(selectors) do
    local category=D.spells[selector].select_target
    for _,id in ipairs(Cards.order) do
        local wand=require("nw/generator").starter()
        wand.stats.mana_max=10000
        wand.cards={{spell_id=selector,card_uid="scope"},{spell_id=id,card_uid="tested"},
            {spell_id="spark",card_uid="tail"},{spell_id="spark",card_uid="payload"}}
        wand.runtime=C.initial(wand.cards,wand.stats,42)
        local plan=assert(C.compile(wand),selector.." + "..id)
        local expected={[category]=true}
        if D.spells[id].select_target then expected[D.spells[id].select_target]=true end
        for _,p in ipairs(plan.blocks[1].projectiles) do
            assert(p.flags.targets and p.flags.targets[category],selector.." + "..id)
            for k,v in pairs(p.flags.targets) do assert(v and expected[k],id.." widened target scope") end
            if p.payload then
                for _,child in ipairs(plan.blocks[p.payload].projectiles) do
                    assert(not child.flags.targets,id.." leaked selection into an independent payload")
                end
            end
        end
        assert(plan.blocks[1].modifiers.flags.targets[category])
        cases=cases+1
    end
end
assert(cases==7*#Cards.order)
print("targeting card scopes: "..#selectors.." selectors x "..#Cards.order.." registered cards, union and independent payload boundaries")
