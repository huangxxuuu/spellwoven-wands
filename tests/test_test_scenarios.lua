local scenes=require("nw/test_scenarios")
local D=require("nw/definitions").spells
local C=require("nw/compiler")
local seen={}
assert(#scenes==17)
local dual=0
for _,s in ipairs(scenes) do
    assert(not seen[s.id] and #s.steps==3 and #s.items>0);seen[s.id]=true
    if s.duo then
        dual=dual+1
        assert(#s.items==18 and #s.boxlabels==2 and #s.checks>=3)
        for _,check in ipairs(s.checks) do assert(#check==5) end
        for i,row in ipairs(s.items) do
            if row.name then assert(row.name:sub(1,1)==(i<=9 and "A" or "B")) end
        end
    end
    for _,row in ipairs(s.items) do
        assert(row.wand or row.card or row.prefab)
        if row.card then assert(D[row.card]) end
        if row.wand then
            assert(#row.wand<=(row.capacity or 12))
            local w=require("nw/generator").starter();w.stats.capacity=row.capacity or 12;w.stats.mana_max=600;w.cards={}
            for i=1,w.stats.capacity do
                local id=row.wand[i];assert(not id or D[id],tostring(id))
                w.cards[i]=id and {spell_id=id,card_uid=tostring(i)} or false
            end
            w.runtime=C.initial(w.cards,w.stats,71)
            assert(C.compile(w),s.id.." / "..row.name)
        end
    end
end
assert(dual==5)
print("test scenes: 17 scenarios, five A/B paired suites, explicit conditions/actions/outcomes; all loadouts compile")
