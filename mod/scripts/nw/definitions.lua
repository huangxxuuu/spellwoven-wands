local Parameters=require("nw/card_parameters")
local Modifier=require("nw/constants/modifiers")
local Fields=require("nw/constants/fields")
local M = { spells = {}, order = {} }
local function add(id, kind, mana, delay, params)
    local d = params or {}
    d.id, d.kind, d.mana, d.delay = id, kind, mana, delay
    d.recharge = d.recharge or 0
    M.spells[id] = d
    M.order[#M.order + 1] = id
end
local function card(id,kind)
    local d=Parameters.get(kind,id)
    add(id,kind,d.mana,d.delay,d)
end
card("spark","projectile")
card("arrow","projectile")
card("scatter","projectile")
card("heavy","projectile")
card("fire","projectile")
card("frost","projectile")
card("speed_up","modifier")
card("speed_down","modifier")
card("sine","modifier")
card("spiral","modifier")
card("homing","modifier")
card("bounce","modifier")
card("pierce","modifier")
card("explosion","modifier")
card("chain","instant")
card("knockback","modifier")
card("leech","modifier")
card("light","modifier")
card("double","multicast")
card("triple","multicast")
card("trigger_hit","trigger")
card("trigger_timer","trigger")
card("damage_up","modifier")
card("precision","modifier")
card("thrust","melee")
card("slash","melee")
card("whirl","melee")
card("orbit","modifier")
card("pierce_all","modifier")
card("imprint_hit","modifier")
card("imprint_timer","modifier")
card("heal_ally","modifier")
M.bullets={"spark","arrow","heavy","scatter","fire","frost"}
for _,id in ipairs(M.bullets) do
    local base=M.spells[id]
    for _,event in ipairs({"hit","timer"}) do
        local v=require("nw/util").copy(base)
        v.base,v.event,v.time=id,event,event=="timer" and Modifier.trigger.time or nil
        add(id.."_"..event,"projectile",base.mana+Modifier.trigger[event].mana,
            base.delay+Modifier.trigger[event].delay,v)
    end
end
card("mana_reduce","modifier")
card("recharge_down","modifier")
card("repeat_2","modifier")
card("repeat_3","modifier")
card("phase_wall","modifier")
card("spore_sentry","field")
card("vital_ring","field")
card("heavy_shot","modifier")
card("trident_cast","multicast")
card("chord_d","note")
card("repeat_4","modifier")
for _,card in ipairs(require("nw/expansion")) do
    add(card.id,card.kind,card.mana,card.kind=="field" and Fields.default_delay or 0,card)
end
for _,c in ipairs(require("nw/arsenal").cards) do add(c.id,c.kind,c.mana,c.delay,c) end
card("giant_shot","modifier")
card("short_life","modifier")
card("homing_rotate","modifier")
card("gunpowder","field")
card("ocarina_g","projectile")
for _,c in ipairs(require("nw/pitch_modifiers").cards) do add(c.id,c.kind,c.mana,c.delay,c) end
for _,c in ipairs(require("nw/arsenal").extra_notes) do add(c.id,c.kind,c.mana,c.delay,c) end
card("dark","modifier")
card("shrink_shot","modifier")
M.spells.thrust.source_weapon="spear";M.spells.slash.source_weapon="glasscutter"
M.spells.whirl.source_weapon="axe";M.spells.whirl.work={"CHOP"};M.spells.whirl.work_radius=M.spells.whirl.reach
M.trajectory={sine=true,spiral=true,precision=true,homing=true,bounce=true,orbit=true}
M.always = { "speed_up", "precision" }
M.spells.weak_homing=Parameters.get("modifier","weak_homing")
M.archetypes = { "sprout", "rapid", "reservoir", "renewal", "weaver", "chaos" }
return M
