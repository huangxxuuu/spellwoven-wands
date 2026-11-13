local C=require("nw/compiler")
local A=require("nw/arsenal")
local D=require("nw/definitions")
local Cards=require("nw/cards")
local function wand(ids)
    local w=require("nw/generator").starter()
    w.stats.mana_max=600;w.stats.draw_count=1;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,7)
    return w
end
local function cast(ids) return assert(C.compile(wand(ids))) end
local function first(ids) return cast(ids).blocks[1].projectiles[1] end
local function shift(ids) return first(ids).pitch or 0 end
assert(shift({"pitch_octave_up","pitch_semitone_down","note_a"})==11)
assert(A.resolve_tone("note_a",11).pitch==32) -- A4 -> G#5
assert(shift({"pitch_semitone_down","pitch_octave_up","note_a"})==11)
assert(shift({"pitch_octave_up","pitch_octave_down","pitch_semitone_up","pitch_semitone_down","note_a"})==0)
assert(shift({"pitch_octave_up","pitch_octave_up","note_a"})==12)
assert(shift({"speed_up","speed_down","note_a"})==0)
local group=cast({"double","note_a","pitch_semitone_up","note_c"}).blocks[1]
assert(#group.projectiles==2)
for _,p in ipairs(group.projectiles) do assert(p.pitch==1) end
local w=wand({"pitch_octave_down","note_a","note_a"});local plan=assert(C.compile(w))
assert(plan.blocks[1].projectiles[1].pitch==-12)
w.runtime=plan.next_state;assert((C.compile(w).blocks[1].projectiles[1].pitch or 0)==0)
for _,carrier in ipairs({"arrow_hit","arrow_timer"}) do
    local outer=cast({"pitch_octave_up",carrier,"note_a"})
    local parent=outer.blocks[1].projectiles[1]
    assert(parent.pitch==12 and (outer.blocks[parent.payload].projectiles[1].pitch or 0)==0)
    local inner=cast({carrier,"pitch_semitone_down","note_a"})
    parent=inner.blocks[1].projectiles[1]
    assert((parent.pitch or 0)==0 and inner.blocks[parent.payload].projectiles[1].pitch==-1)
end
local plain=first({"note_c"});local tuned=first({"pitch_octave_down","note_c"})
assert(tuned.id=="note_c" and tuned.speed==plain.speed and tuned.lifetime==plain.lifetime and tuned.damage==plain.damage)
assert(first({"pitch_semitone_up","ocarina_b"}).id=="ocarina_b")
local harp=first({"chord_d"});local shifted=first({"pitch_semitone_down","chord_d"})
assert(shifted.radius==harp.radius and shifted.kind==harp.kind and shifted.mana==harp.mana)
assert(A.resolve_tone("kantele_dsharp",0).pitch==12) -- Stable old ID, now actual C4.
assert(A.resolve_tone("ocarina_a2",12).pitch==33)
assert(A.tone("ocarina_a2",12)=="nw_instruments/ocarina/one_m081")
assert(A.tone("ocarina_a2",99)==A.tone("ocarina_a2",12))
assert(A.tone("kantele_a",-12)=="nw_instruments/kantele/one_m057")
assert(A.tone("note_a",11)~=nil)
-- All three exact recorded beat lengths are selected; no pitch/speed DSP.
local Effects=require("nw/spell_effects");local oldfx=Effects.fx;local calls=0
local played,duration
Effects.fx=function()
    calls=calls+1
    return {SoundEmitter={PlaySoundWithParams=function(_,event,params) assert(event and next(params)==nil);played=event end},
        Remove=function() end,DoTaskInTime=function(_,time) duration=time end}
end
local Fields=require("nw/expanded_fields")
assert(Fields.sound(nil,0,0,"unknown",14)==false and calls==0)
for _,id in ipairs({"note_a","kantele_a"}) do
    for _,beats in ipairs({.5,1,2}) do
        assert(Fields.sound(nil,0,0,id,0,beats))
        local tone=A.resolve_tone(id,0,beats)
        assert(played==tone.event and math.abs(duration-tone.duration-.1)<.000001)
    end
end
assert(calls==6)
Effects.fx=oldfx
-- Sum first, then saturate: duplicates cannot exceed half/two beats, and
-- surplus Speed Up cards still cancel against Slow Down in either order.
for _,id in ipairs({"note_c","kantele_f"}) do
    for _,row in ipairs({{{},1},{{"speed_up"},.5},{{"speed_down"},2},
        {{"speed_up","speed_up"},.5},{{"speed_down","speed_down"},2},
        {{"speed_up","speed_down"},1},{{"speed_up","speed_up","speed_down"},.5},
        {{"speed_down","speed_up","speed_up"},.5},{{"speed_down","speed_down","speed_up"},2}}) do
        local ids={};for _,v in ipairs(row[1]) do ids[#ids+1]=v end;ids[#ids+1]=id
        assert(first(ids).beats==row[2])
    end
end
assert(shift({"pitch_octave_up","pitch_octave_up","pitch_octave_down","note_a"})==12)
assert(shift({"pitch_octave_down","pitch_octave_down","pitch_octave_up","note_a"})==-12)
local score=cast({"speed_up","arrow_hit","speed_down","kantele_b"})
local carrier=score.blocks[1].projectiles[1]
assert(not carrier.beats and score.blocks[carrier.payload].projectiles[1].beats==2)
local group=cast({"speed_up","double","note_c","kantele_f"}).blocks[1]
assert(#group.projectiles==2 and group.projectiles[1].beats==.5 and group.projectiles[2].beats==.5)
local recipes=require("nw/acquisition")
for _,instrument in ipairs({"ocarina","kantele"}) do
    local found={}
    for _,recipe in ipairs(recipes.recipes) do
        local note=A.notes[recipe.card]
        if note and note.instrument==instrument then found[#found+1]=note end
    end
    assert(#found==7)
    for i,pitch in ipairs({12,14,16,17,19,21,23}) do
        assert(found[i].pitch==pitch)
        local id
        for key,note in pairs(A.notes) do if note==found[i] then id=key end end
        assert(A.resolve_tone(id,-99).pitch==pitch-12 and A.resolve_tone(id,99).pitch==pitch+12)
    end
end
local recipes=require("nw/acquisition");local rarity=require("nw/card_rarity")
for _,card in ipairs(require("nw/pitch_modifiers").cards) do
    local r=assert(recipes.by_name["nw_inscribe_"..card.id])
    assert(D.spells[card.id].mana==1 and rarity.tiers[card.id]==1 and r.station=="nw_workbench")
    assert(r.group==recipes.by_name.nw_inscribe_note_a.group)
    assert(r.ingredients[1][1]=="nw_blank" and r.ingredients[1][2]==1 and #r.ingredients==3)
    assert(Cards.codes[card.id]>Cards.codes.ocarina_g)
    assert(require("nw/hover_data").card_details(card.id,false).effect)
end
assert(#Cards.order==224 and Cards.codes.pitch_octave_up==218 and Cards.codes.pitch_semitone_down==221)
print("pitch cards: accumulation, cancellation, multicast, cast/payload isolation, note identity, audio bounds and recipes passed")
