local M = { spells = {}, order = {} }
local function add(id, kind, mana, delay, params)
    local d = params or {}
    d.id, d.kind, d.mana, d.delay = id, kind, mana, delay
    d.recharge = d.recharge or 0
    M.spells[id] = d
    M.order[#M.order + 1] = id
end
local function bullet(id, mana, delay, damage, speed, lifetime, extra)
    local p = extra or {}
    p.damage, p.speed, p.lifetime = damage, speed, lifetime
    p.count = p.count or 1
    add(id, "projectile", mana, delay, p)
end
bullet("spark", 5, -.07, 18, 17.5, .8, {halfangle=3,recharge=-.10})
bullet("arrow", 8, -.03, 22, 25, 1.2, {halfangle=1,recharge=-.05})
bullet("scatter", 13, .05, 9, 15, 1.2, { halfangle=2.5,recharge=.03,count = 3, angles = {-10, 0, 10} })
bullet("heavy", 18, .12, 27, 8.75, 1.8, { halfangle=4,recharge = .1 })
bullet("fire", 12, .05, 9, 15, 1.2, {halfangle=2.25,recharge=.03,burn_damage=3.6,burn_ticks=3 })
bullet("frost", 10, .05, 9, 15, 1.2, {halfangle=2.25,recharge=.03,freeze=.4 })
add("speed_up", "modifier", 3, 0, { speed_mult = 1.5, speed_add = 2 })
add("speed_down", "modifier", 3, 0, { speed_mult = .65, lifetime_mult = 1.4 })
add("sine", "modifier", 4, 0, { flag = "sine", amplitude = 1.2, frequency = 1.6 })
add("spiral", "modifier", 5, 0, { flag = "spiral", amplitude = 1.45, frequency = 2.4 })
add("homing", "modifier", 12, .03, { flag = "homing", acceleration = 36, damping = .72, turn_rate=180, radius = 8 })
add("bounce", "modifier", 6, 0, { flag = "bounce", bounces = 2 })
add("pierce", "modifier", 10, .02, { flag = "pierce", hits = 3 })
add("explosion", "modifier", 16, .08, { flag="explosive_hit", radius = 3, explosion_damage = 25 })
add("chain", "instant", 14, .05, { radius = 6, damage = 15, jump_damage = 10, max_targets = 4 })
add("knockback", "modifier", 5, 0, { flag = "knockback", distance = 1, duration = .2 })
add("leech", "modifier", 12, .05, { flag = "leech", fraction = .05 })
add("light", "modifier", 2, 0, { flag = "light", radius = 2, duration = 3 })
add("double", "multicast", 2, 0, { draws = 2 })
add("triple", "multicast", 4, .02, { draws = 3 })
add("trigger_hit", "trigger", 10, .03, { damage = 10, speed = 14, lifetime = 1, event = "hit" })
add("trigger_timer", "trigger", 10, .03, { damage = 10, speed = 10, lifetime = 1.2, event = "timer", time = .5 })
add("damage_up", "modifier", 8, .03, { damage_add = 10 })
add("precision", "modifier", 3, 0, { spread_add = -2 })
add("thrust","melee",8,.03,{damage=27.2,reach=2.4,width=1,duration=.24,windup=.09})
add("slash","melee",19,.15,{damage=54.4,reach=2.2,arc=100,duration=.30,windup=.12,recharge=.10})
add("whirl","melee",14,.08,{damage=21.76,reach=1.15,duration=.42,windup=.42,recharge=.05})
add("orbit","modifier",10,.05,{flag="orbit",radius=2})
add("pierce_all","modifier",22,.08,{flag="pierce_all"})
add("imprint_hit","modifier",10,.03,{imprint="hit"})
add("imprint_timer","modifier",10,.03,{imprint="timer"})
add("heal_ally","modifier",14,.05,{flag="heal_ally",heal=8})
M.bullets={"spark","arrow","heavy","scatter","fire","frost"}
for _,id in ipairs(M.bullets) do
    local base=M.spells[id]
    for _,event in ipairs({"hit","timer"}) do
        local v=require("nw/util").copy(base)
        v.base,v.event,v.time=id,event,event=="timer" and .5 or nil
        add(id.."_"..event,"projectile",base.mana+(event=="hit" and 4 or 5),
            base.delay+(event=="hit" and .02 or .03),v)
    end
end
-- Append after every 0.7.0 definition to preserve network/save card codes.
add("mana_reduce","modifier",-30,.17)
add("recharge_down","modifier",12,-.17,{recharge=-.33})
add("repeat_2","modifier",35,.33,{copies=2})
add("repeat_3","modifier",50,.58,{copies=3})
add("phase_wall","modifier",10,.04,{flag="phase_wall"})
add("spore_sentry","field",18,.12,{damage=6,radius=4})
add("vital_ring","field",30,.18,{radius=2})
add("heavy_shot","modifier",12,.08,{damage_add=12,speed_mult=.65,spread_add=2})
add("trident_cast","multicast",8,.05,{draws=3,fan={-20,0,20}})
add("chord_d","note",10,.03,{radius=3})
add("repeat_4","modifier",70,.83,{copies=4,copy_damage=.45})
for _,card in ipairs(require("nw/expansion")) do
    add(card.id,card.kind,card.mana,card.kind=="field" and .12 or 0,card)
end
for _,c in ipairs(require("nw/arsenal").cards) do add(c.id,c.kind,c.mana,c.delay,c) end
add("giant_shot","modifier",16,.05,{flag="giant"})
add("short_life","modifier",6,0,{lifetime_mult=.5})
-- Append only: existing network/save card codes must remain stable.
add("homing_rotate","modifier",8,.02,{flag="homing_rotate",turn_rate=180,radius=8})
add("gunpowder","field",20,.12,{tier=2})
M.spells.thrust.source_weapon="spear";M.spells.slash.source_weapon="glasscutter"
M.spells.whirl.source_weapon="axe";M.spells.whirl.work={"CHOP"};M.spells.whirl.work_radius=M.spells.whirl.reach
M.trajectory={sine=true,spiral=true,precision=true,homing=true,bounce=true,orbit=true}
M.always = { "speed_up", "precision" }
M.spells.weak_homing = { id = "weak_homing", kind = "modifier", mana = 0, delay = 0, recharge = 0, flag = "homing_rotate", turn_rate = 100, radius = 6 }
M.archetypes = { "sprout", "rapid", "reservoir", "renewal", "weaver", "chaos" }
return M
