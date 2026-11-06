local V=require("nw/visual")
local records={}
local state={
    SetBank=function(_,bank) assert(bank=="nw_parts") end,
    SetBuild=function(_,build) assert(build=="nw_parts") end,
    PlayAnimation=function(_,anim) records.anim=anim end,
    OverrideSymbol=function(_,slot,build,sym) records[slot]=sym end,
}
local seen={}
for code=0,V.count-1 do
    V.apply({AnimState=state},code,"ground")
    local key=records.anim..records.head..records.body..records.tail
    assert(not seen[key]);seen[key]=true
    V.apply({AnimState=state},code,"held")
    assert(records.anim:sub(1,5)=="held_")
end
assert(V.count==4374 and V.count<65536)
for _,shuffle in ipairs({false,true}) do
    for draws=1,3 do
        for _,regen in ipairs({8,24.99,25,80}) do
            for cosmetic=0,V.cosmetic_rolls-1 do
                local roll=cosmetic%18
                local stats={shuffle=shuffle,draw_count=draws,capacity=8,mana_regen=regen}
                local d={stats=stats,appearance=V.appearance(stats,cosmetic)}
                local code=V.from_data(d)
                local head,length,tail,body=V.parts(code)
                local style=math.floor(cosmetic/18)+1
                assert(body==string.format("body_%02d_medium",style) and d.appearance.body_id==body)
                assert(V.atlas(code)==V.atlas((style-1)*486))
                V.upgrade(d);assert(V.from_data(d)==code)
                assert(head=="head_"..(shuffle and "plain" or "crystal").."_"..draws.."_"..V.colors[roll%3+1])
                local shape=regen>=25 and "round" or roll<9 and "drop" or "diamond"
                assert(length=="medium" and tail=="tail_"..shape.."_"..V.colors[math.floor(roll/3)%3+1])
            end
        end
    end
end
local legacy={seed=1,wand_uid="nw:a:1:2",stats={capacity=2,mana_regen=18,shuffle=false,draw_count=1}}
V.upgrade(legacy)
local look=V.from_data(legacy)
legacy.appearance=nil;V.upgrade(legacy);assert(V.from_data(legacy)==look)
legacy.appearance={appearance_schema=2,roll=16}
V.upgrade(legacy);assert(legacy.appearance.roll==16)
local migrated=V.from_data(legacy)
V.upgrade(legacy);assert(V.from_data(legacy)==migrated)
print("visual: all 4374 looks, nine shaft styles, stable v2 migration and save/restore")
