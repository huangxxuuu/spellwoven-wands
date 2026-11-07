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
assert(shift({"pitch_octave_up","pitch_octave_up","note_a"})==24)
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
assert(A.resolve_tone("ocarina_a2",12).pitch==45)
assert(A.tone("ocarina_a2",12)=="nw_instruments/ocarina/m093")
local path,reason=A.tone("ocarina_a2",14);assert(path==nil and reason=="unsupported_pitch")
assert(A.tone("kantele_a",-12)=="nw_instruments/kantele/m045")
assert(A.tone("note_a",11)~=nil)
-- Unsupported sound must not ask the engine to play a nil or substituted event.
local Effects=require("nw/spell_effects");local oldfx=Effects.fx;local calls=0
Effects.fx=function()
    calls=calls+1
    return {SoundEmitter={PlaySoundWithParams=function(_,event,params) assert(event and next(params)==nil) end},
        Remove=function() end,DoTaskInTime=function(_,duration) assert(duration>1 and duration<25) end}
end
local Fields=require("nw/expanded_fields")
assert(Fields.sound(nil,0,0,"ocarina_a2",14)==false and calls==0)
assert(Fields.sound(nil,0,0,"note_a",0)==true and calls==1)
assert(Fields.sound(nil,0,0,"kantele_a",0)==true and calls==2)
Effects.fx=oldfx
local recipes=require("nw/acquisition");local rarity=require("nw/card_rarity")
for _,card in ipairs(require("nw/pitch_modifiers").cards) do
    local r=assert(recipes.by_name["nw_inscribe_"..card.id])
    assert(D.spells[card.id].mana==1 and rarity.tiers[card.id]==1 and r.station=="nw_workbench")
    assert(r.group==recipes.by_name.nw_inscribe_note_a.group)
    assert(r.ingredients[1][1]=="nw_blank" and r.ingredients[1][2]==1 and #r.ingredients==3)
    assert(Cards.codes[card.id]>Cards.codes.ocarina_g)
    assert(require("nw/hover_data").card_details(card.id,false).effect)
end
assert(#Cards.order==220 and Cards.codes.pitch_octave_up==218 and Cards.codes.pitch_semitone_down==221)
print("pitch cards: accumulation, cancellation, multicast, cast/payload isolation, note identity, audio bounds and recipes passed")
