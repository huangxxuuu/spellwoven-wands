local A=require("nw/arsenal")
local C=require("nw/compiler")
local T=require("nw/targeting")
local Cards=require("nw/cards")
local function cast(ids)
    local w=require("nw/generator").starter()
    w.stats.mana_max=600;w.cards={}
    for i,id in ipairs(ids) do w.cards[i]={spell_id=id,card_uid=tostring(i)} end
    w.runtime=C.initial(w.cards,w.stats,4)
    return assert(C.compile(w))
end
local tones={}
for id,note in pairs(A.notes) do
    local bank,p=A.tone(id,0)
    local midi=tonumber(bank:match("/m(%d+)$"))
    assert(midi==note.pitch+48 and next(p)==nil)
    tones[id]=true
end
local total=0;for _ in pairs(tones) do total=total+1 end;assert(total==14)
local scale=cast({"speed_up","speed_up","speed_down","note_c"})
assert((scale.blocks[1].projectiles[1].pitch or 0)==0)
local outer=cast({"target_nature","target_building","arrow_hit","whirl"})
local parent=outer.blocks[1].projectiles[1];local child=outer.blocks[parent.payload].projectiles[1]
assert(parent.flags.targets.nature and parent.flags.targets.building and not child.flags.targets)
local override=cast({"target_nature","arrow_hit","target_self","spark"})
assert(T.only_self(override.blocks[2].projectiles[1].flags))
local pvp=false
TheNet={GetPVPEnabled=function() return pvp end}
local function entity(tag)
    local e={components={health={IsDead=function() return false end},combat={}}}
    e.HasTag=function(_,key) return key==tag end;e.IsValid=function() return true end;e.IsInLimbo=function() return false end
    e.components.combat.CanTarget=function() return true end
    e.components.combat.IsAlly=function() return false end
    return e
end
local me,you=entity("player"),entity("player")
assert(T.allowed(me,me,{targets={self=true}}) and T.allowed(me,you,{targets={self=true,players_other=true}}))
pvp=true
assert(T.allowed(me,you,{targets={players_other=true}}) and not T.allowed(me,me,{targets={players_other=true}}))
local neutral,hostile,pet=entity("animal"),entity("hostile"),entity("animal")
pet.components.follower={leader=me}
assert(T.allowed(me,neutral,{targets={neutral=true}}) and not T.allowed(me,neutral,{targets={hostile=true}}))
assert(T.allowed(me,hostile,{targets={hostile=true}}) and T.allowed(me,pet,{targets={friendly=true}}))
assert(not T.allowed(me,pet,{targets={neutral=true}}))
local wall,plant=entity("wall"),entity("plant")
assert(T.allowed(me,wall,{targets={building=true}}) and not T.allowed(me,plant,{targets={building=true}}))
plant.components.health=nil;plant.components.combat=nil
assert(T.matches(me,plant,{nature=true}) and not T.allowed(me,plant,{targets={nature=true}}))
assert(T.allowed(me,me,{targets={self=true,players_other=true}}) and T.allowed(me,you,{targets={self=true,players_other=true}}))
assert(Cards.codes.note_c==103 and Cards.codes.spark==1 and #Cards.order<=255)
assert(not Cards.codes.target_players_all and Cards.codes.target_players_other==194 and Cards.codes.target_self==195)
assert(Cards.decode("193,194,195")[1]=="target_players_other")
assert(Cards.migrate_id("target_players_all")=="target_players_other")
local union=cast({"target_players_other","target_self","spark"}).blocks[1].projectiles[1].flags
assert(union.targets.self and union.targets.players_other and not T.only_self(union))
local n=0;for id,c in pairs(A.weapons) do n=n+1;assert((c.kind=="melee" or c.kind=="projectile" and c.engraving or c.kind=="field" and c.native_field) and c.damage>=0 and c.work_radius==c.reach) end
assert(n==91 and math.abs(A.weapons.edge_spear_wathgrithr_lightning.damage-47.6)<.0001)
print("arsenal: weapon definitions, notes unaffected by speed modifiers, nested target scopes, PvP gates")
