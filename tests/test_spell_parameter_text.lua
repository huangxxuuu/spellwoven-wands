local P=require("nw/spell_parameter_text")
local Locale=require("nw/locale")
local D=require("nw/definitions")
local Copy=require("nw/util").copy
local Modifiers=require("nw/constants/modifiers")
local Projectiles=require("nw/constants/projectiles")
local Runtime=require("nw/constants/projectile_runtime")
local Fields=require("nw/constants/field_runtime")
local Info=require("nw/spell_info")
local function contains(text,fragment) assert(text:find(fragment,1,true),text.." missing "..fragment) end
for _,language in ipairs({"zh","en"}) do
    Locale.configure(language,language)
    local beam=Copy(D.spells.end_beam)
    beam.damage,beam.end_damage=37,43
    local hold,fade=Runtime.beam.hold,Runtime.beam.fade
    Runtime.beam.hold,Runtime.beam.fade=2.3,.7
    local text=P.effect("end_beam",beam)
    if language=="zh" then
        contains(text,"造成 37 伤害");contains(text,"终点半径 1.5 爆 43")
        contains(text,"留存 2.3 秒后用 0.7 秒")
    else
        contains(text,"for 37 damage");contains(text,"bursts for 43 damage")
        contains(text,"lasts 2.3 seconds");contains(text,"over 0.7 seconds")
    end
    Runtime.beam.hold,Runtime.beam.fade=hold,fade
    local step=Modifiers.rules.giant_step
    Modifiers.rules.giant_step=3
    text=P.effect("giant_shot",D.spells.giant_shot)
    contains(text,"3");contains(text,"6");contains(text,"9")
    text=P.effect("shrink_shot",D.spells.shrink_shot)
    contains(text,"1.2")
    assert(not text:find(language=="zh" and "恢复原尺寸" or "restores normal size",1,true))
    Modifiers.rules.giant_step=step
    local duration=Projectiles.effects.grow_orb.growth_duration
    Projectiles.effects.grow_orb.growth_duration=2
    text=P.effect("grow_orb",D.spells.grow_orb)
    contains(text,"40");contains(text,"2")
    Projectiles.effects.grow_orb.growth_duration=duration
    local rain=Copy(Fields.rain.pulses)
    Fields.rain.pulses[#Fields.rain.pulses+1]=2.5
    text=P.effect("rain_cloud",D.spells.rain_cloud)
    contains(text,language=="zh" and "三次" or "Three local pulses")
    Fields.rain.pulses=rain
    local hits=Projectiles.engraved_special.lance_hits
    Projectiles.engraved_special.lance_hits=4
    text=P.effect("edge_yoth_lance",D.spells.edge_yoth_lance)
    contains(text,language=="zh" and "三个目标" or "three targets")
    Projectiles.engraved_special.lance_hits=hits
    assert(not pcall(P.format,"{missing}",{}))
    local near=Copy(D.spells.near_homing)
    near.radius,near.acceleration,near.damping,near.turn_rate=9,30,2,180
    text=P.effect("near_homing_short",near)
    for _,value in ipairs({"9","30","2","15","180"}) do contains(text,value) end
    for id in pairs(D.spells) do
        local effect=P.effect(id,D.spells[id])
        if effect then assert(not effect:find("{[%w_]+}"),id.." contains an unresolved parameter") end
    end
end
Locale.configure("zh","zh")
assert(Info.effects.near_homing==P.effect("near_homing_short",D.spells.near_homing))
print("spell parameter text: bilingual semantic arguments, runtime tuning, growth and counts")
