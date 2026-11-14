local Copy=require("nw/util").copy
local Parameters=require("nw/card_parameters")
local Projectile=require("nw/constants/projectiles")
local Modifier=require("nw/constants/modifiers")
local Definitions=require("nw/definitions")
local Damage=require("nw/base_damage")
local Compiler=require("nw/compiler")

local original_damage=Projectile.cards.spark.damage
local original_angle=Projectile.cards.scatter.angles[1]
local first=Parameters.get("projectile","scatter")
local second=Parameters.get("projectile","scatter")
first.angles[1]=original_angle+1
assert(second.angles[1]==original_angle)
assert(Projectile.cards.scatter.angles[1]==original_angle)
assert(Definitions.spells.scatter.angles[1]==original_angle)

for _,rate in ipairs({.5,1.5,.75,1}) do
    Damage.configure(rate)
    assert(Definitions.spells.spark.damage==original_damage*rate)
    assert(Projectile.cards.spark.damage==original_damage)
end

local function cast()
    local wand=require("nw/generator").starter()
    wand.stats.mana_max=1000
    wand.cards={
        {spell_id="giant_shot",card_uid="large"},
        {spell_id="shrink_shot",card_uid="small"},
        {spell_id="spark",card_uid="shot"},
    }
    wand.runtime=Compiler.initial(wand.cards,wand.stats,1)
    local plan=assert(Compiler.compile(wand))
    return plan.blocks[1].projectiles[1]
end

local defaults=Copy(Modifier.rules)
Modifier.rules.giant_step=3
Modifier.rules.shrink_multiplier=.5
local shot=cast()
assert(shot.size_mult==1.5)
assert(shot.damage==Definitions.spells.spark.damage)
assert(shot.speed==Definitions.spells.spark.speed)
Modifier.rules.giant_step=defaults.giant_step
Modifier.rules.shrink_multiplier=defaults.shrink_multiplier

local Balance=require("nw/balance")
local mana=Modifier.cards.mana_reduce.mana
Modifier.cards.mana_reduce.mana=-37
Balance.configure("fun")
assert(Definitions.spells.mana_reduce.mana==-37)
Modifier.cards.mana_reduce.mana=mana
Balance.configure("balanced")
assert(Modifier.cards.mana_reduce.mana==mana)
Balance.configure("fun")
assert(Definitions.spells.mana_reduce.mana==Modifier.cards.mana_reduce.mana)
assert(Projectile.cards.spark.damage==original_damage)
print("constants: independent card copies, world damage isolation and configurable size rules")
