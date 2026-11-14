local Locale=require("nw/locale")
local Modifiers=require("nw/constants/modifiers")
local Projectiles=require("nw/constants/projectiles")
local Runtime=require("nw/constants/projectile_runtime")
local FieldRuntime=require("nw/constants/field_runtime")
local Motion=require("nw/constants/motion")
local Audio=require("nw/constants/audio")
local Limits=require("nw/constants/limits")
local Prefabs=require("nw/constants/prefabs")
local Dark=require("nw/constants/dark_fog")
local Instant=require("nw/constants/instant")
local NativeEffects=require("nw/constants/native_effects")
local NativeFallback=require("nw/constants/description").native_fallbacks
local FogWait=require("nw/constants/fog_boss").wait
local M={}
function M.word(value,liang,capital)
    local zh={"一","二","三","四","五","六","七","八","九","十"}
    local en={"one","two","three","four","five","six","seven","eight","nine","ten"}
    if Locale.language~="en" then return value==2 and liang and "两" or zh[value] or string.format("%g",value) end
    local word=en[value] or string.format("%g",value)
    return capital and word:gsub("^%l",string.upper) or word
end
function M.penetration_count(value)
    if Locale.language=="en" and value==2 then return "multiple" end
    return M.word(value,true,false)
end
function M.format(text,values)
    return (Locale.t(text):gsub("{([%w_]+)}",function(key)
        local value=assert(values[key],"Unknown spell description parameter: "..key)
        return type(value)=="number" and string.format("%g",value) or tostring(value)
    end))
end
function M.shrink_combination()
    local multiplier=math.max(Limits.min_size,Modifiers.rules.giant_step*Modifiers.rules.shrink_multiplier)
    if multiplier==1 then return Locale.t("一巨化加一缩小恢复原尺寸") end
    return M.format("一巨化加一缩小变为原尺寸的 ×{multiplier}",{multiplier=multiplier})
end
local templates={
    ["gust"]={text="{damage} 伤，生物最多推 {distance} 单位，Boss 不吃位移。命中载荷卵时沿弹道叠加弹速一半的速度，不释放载荷；不能推动晶雷与休眠晶体。",values=function(d) return {damage=d.damage,distance=d.innate.knockback.distance} end},
    ["spore_ball"]={text="{damage} 伤，存活 {lifetime} 秒；可击破，碎裂仅判一次。",values=function(d) return {damage=d.damage,lifetime=d.lifetime} end},
    ["flint_lance"]={text="{damage} 伤，先天最多穿 {hits} 敌，可跨越海岸。",values=function(d) return {damage=d.damage,hits=d.innate.pierce.hits} end},
    ["crystal_mine"]={text="{damage} 伤，生成后立即感应，半径 {radius}。不随时间消失，随世界存档；施法者离线、离开分片或变为幽灵时暂停触发。与休眠晶体共用可选数量上限。",values=function(d) return {damage=d.damage,radius=d.radius} end},
    ["sleep_crystal"]={text="{damage} 伤，不随时间消失，随世界存档；受到攻击或被晶雷引爆令启动时爆炸。施法者离线、离开分片或变为幽灵时仍可被攻击引爆，移动暂停。与近感晶雷共用可选数量上限。",values=function(d) return {damage=d.damage} end},
    ["slime"]={text="{damage} 伤，普通敌减速 {slow}% 持续 {duration} 秒；同源刷新。",values=function(d) return {damage=d.damage,slow=(1-Projectiles.effects.slime.speed_multiplier)*100,duration=Projectiles.effects.slime.duration} end},
    ["grow_orb"]={text="{damage}→{grown} 伤，飞满 {duration} 秒封顶，同时略增半径。",values=function(d) return {damage=d.damage,grown=d.damage*(1+Projectiles.effects.grow_orb.growth_damage/Projectiles.effects.grow_orb.growth_base*Projectiles.effects.grow_orb.growth_duration),duration=Projectiles.effects.grow_orb.growth_duration} end},
    ["heal_bolt"]={text="给命中目标回复 {heal} 点生命。默认按普通弹体选取目标，可用目标卡指定友方。",values=function(d) return {heal=d.heal} end},
    ["star_vortex"]={text="{count} 枚各 {damage} 伤，共享 {lifetime} 秒寿命，计入可选的单发上限。",values=function(d) return {count=Locale.language=="en" and M.word(d.count,false,true) or d.count,damage=d.damage,lifetime=d.lifetime} end},
    ["moon_fall"]={text="地标等 {delay} 秒落石，半径 {radius}、{damage} 伤，建筑免伤。",values=function(d) return {delay=FieldRuntime.moon_fall.delay,radius=d.radius,damage=d.damage} end},
    ["bog_whip"]={text="从触发点沿弹向鞭打长 {reach} 的区域，每敌 {damage} 伤。",values=function(d) return {reach=d.reach,damage=d.damage} end},
    ["detonate"]={text="最远指定 {range} 单位，在施法点周围 {radius} 单位引爆所有近感晶雷和休眠晶体，不区分释放者，不受目标选择限制。",values=function(d) return {range=d.aim_range,radius=d.radius} end},
    ["bee_swarm"]={text="最多 {count} 次各 {damage} 伤，同一调度器控制，不掉蜂刺。",values=function(d) return {count=FieldRuntime.swarm.count,damage=d.damage} end},
    ["delay_seal"]={text="{delay} 秒后由印记释放预抽的一组，只抽 1 张。",values=function(d) return {delay=FieldRuntime.payload.delay} end},
    ["rain_cloud"]={text="半径 {radius}，持续 {duration} 秒，{count}次局部湿润与灭火。",values=function(d) return {radius=d.radius,duration=FieldRuntime.rain.lifetime,count=M.word(#FieldRuntime.rain.pulses,true,true)} end},
    ["guard_ring"]={text="护盾环绕施法者 {duration} 秒，每抵消一枚射向自己的敌方投射物消耗一面盾。",values=function(d) return {duration=FieldRuntime.guard.lifetime} end},
    ["wild_charge"]={text="同块随机半角 +{spread}°，充能 −{recharge} 秒。",values=function(d) return {spread=d.spread_add,recharge=-d.recharge} end},
    ["long_life"]={text="飞行弹体寿命 ×{multiplier}，多张相乘，无寿命上限；默认无累计射程限制，可由世界设置开启。也延长火药引线；也影响有限寿命的静态场，永久实体仍永久。",values=function(d) return {multiplier=d.lifetime_mult} end},
    ["reverse_path"]={text="{delay} 秒后反向一次，增寿 {bonus}%。",values=function(d) return {delay=Motion.returning.reverse_delay,bonus=(d.lifetime_mult-1)*100} end},
    ["return_path"]={text="{delay} 秒后掉头，再以最多 {turn}°/秒转向施法者。",values=function(d) return {delay=Motion.returning.delay,turn=Motion.returning.turn_rate} end},
    ["light_shot"]={text="速度 ×{speed}，伤害 ×{damage}，半角 −{spread}°。",values=function(d) return {speed=d.speed_mult,damage=d.damage_mult,spread=-d.spread_add} end},
    ["accelerate"]={text="从 {initial} 倍初速起步，{duration} 秒内升到 {final} 倍。",values=function(d) return {initial=Motion.acceleration.initial_factor,duration=Motion.acceleration.duration,final=Motion.acceleration.initial_factor+Motion.acceleration.gain} end},
    ["chill_touch"]={text="每张附魔每次命中附加 {cold} 寒冷。",values=function(d) return {cold=Modifiers.rules.chill_increment} end},
    ["wet_weak"]={text="对潮湿目标伤害 +{bonus}%，可叠加原版电击和火伤结算。",values=function(d) return {bonus=(Modifiers.rules.wet_multiplier-1)*100} end},
    ["melee_mark"]={text="命中后标记 {duration} 秒，下一次合格近战 +{bonus}% 并消费。",values=function(d) return {duration=Modifiers.effects.melee_mark.duration,bonus=Modifiers.effects.melee_mark.bonus*100} end},
    ["wild_double"]={text="抽 {draw} 张，半角 +{spread}°，略减充能。",values=function(d) return {draw=d.draws,spread=d.spread_add} end},
    ["two_way"]={text="抽 {draw} 张，固定 {front}°/{back}°，分别叠各自小散射。",values=function(d) return {draw=d.draws,front=d.fan[1],back=d.fan[2]} end},
    ["note_a"]={text="短程声波标记首敌 {duration} 秒，直伤 {damage}；强化可赋予一次直伤。",values=function(d) return {duration=Audio.timing.mark_duration,damage=d.damage} end},
    ["glass_disc"]={text="{damage} 伤，最多 {hits} 命中；不自伤。",values=function(d) return {damage=d.damage,hits=d.innate.pierce.hits} end},
    ["land_hook"]={text="最长牵引 {distance} 单位，只在陆地生效。",values=function(d) return {distance=Projectiles.effects.land_hook.max_distance} end},
    ["tri_electric"]={text="{count}枚各 {damage} 基础电伤。",values=function(d) return {count=M.word(d.count,false,true),damage=d.damage} end},
    ["end_beam"]={text="贯穿光束每目标每 {interval} 秒造成 {damage} 伤害并触发碰撞效果。光带留存 {hold} 秒后用 {fade} 秒收细消散；终点半径 {radius} 爆 {end_damage}。",values=function(d) return {interval=Runtime.beam.interval,damage=d.damage,hold=Runtime.beam.hold,fade=Runtime.beam.fade,radius=Projectiles.effects.end_beam.end_radius,end_damage=d.end_damage} end},
    ["deer_decoy"]={text="{duration} 秒灵鹿幻影吸引普通怪，结束时旋身消散，造成一次 {damage} 点伤害，不分敌我。",values=function(d) return {duration=FieldRuntime.decoy.lifetime,damage=d.damage} end},
    ["fireflies"]={text="短时跟随，最多袭击{count}次各 {damage} 伤。",values=function(d) return {count=M.word(FieldRuntime.swarm.escort_count,true,false),damage=d.damage} end},
    ["shock_ring"]={text="半径 {radius}，{duration} 秒内{count}次各 {damage} 基础电伤。",values=function(d) return {radius=d.radius,duration=FieldRuntime.electricity.ring_lifetime,count=M.word(FieldRuntime.electricity.ring_count,true,false),damage=d.damage} end},
    ["storm_cloud"]={text="{count}次预警，各 {damage} 基础电伤。",values=function(d) return {count=M.word(FieldRuntime.electricity.cloud_count,false,true),damage=d.damage} end},
    ["vortex"]={text="半径 {radius} 只拉普通敌人一次，最大位移 {step}。",values=function(d) return {radius=d.radius,step=FieldRuntime.vortex.max_step} end},
    ["harmless"]={text="直伤归零，寿命 ×{lifetime}，仍可带独立载荷。",values=function(d) return {lifetime=d.lifetime_mult} end},
    ["searing_halo"]={text="半径 {radius}，每目标每 {interval} 秒最多 {damage} 伤。",values=function(d) return {radius=Modifiers.effects.halo.radius,interval=Modifiers.effects.halo.interval,damage=d.effect_damage} end},
    ["twin_arc"]={text="同一施法两弹间距离不超过 {distance}；每目标每 {interval} 秒最多一次电伤。",values=function(d) return {distance=Modifiers.effects.twin_arc.max_distance,interval=Modifiers.effects.twin_arc.interval} end},
    ["side_embers"]={text="母弹经过 {distance} 单位向两侧各发 1 枚，最多 {groups} 组。",values=function(d) return {distance=Modifiers.effects.side_embers.distance_interval,groups=Modifiers.effects.side_embers.max_groups} end},
    ["near_homing"]={text="半径 {radius} 内向目标推进，加速度 {force}，速度阻尼 {damping}；持续同向追踪时速度趋近 {speed} 单位/秒，移动场地实体的额外阻力会降低此速度。可推动静止实体，与普通追踪独立叠加。",values=function(d) return {radius=d.radius,force=d.acceleration,damping=d.damping,speed=d.acceleration/d.damping} end},
    ["crit_rune"]={text="直击 +{chance} 个百分点暴击率，暴击 ×{multiplier}。",values=function(d) return {chance=Modifiers.effects.crit.chance*100,multiplier=Modifiers.effects.crit.multiplier} end},
    ["cast_four"]={text="抽 {draw} 张，额外充能 +{recharge} 秒。",values=function(d) return {draw=d.draws,recharge=d.recharge} end},
    ["hex_cast"]={text="抽 {draw} 张，按 {angle}° 隔开。",values=function(d) return {draw=d.draws,angle=d.fan[2]-d.fan[1]} end},
    ["note_c"]={text="命中短鸣标记触发一次 {damage} 伤回声。",values=function(d) return {damage=d.echo_damage} end},
    ["speed_up"]={text="同组初速度 ×{speed}，另加 {addition} 单位/秒初速度；多张倍率相乘、初速度增量相加。 乐器改为半拍；与减速按数量抵消，只保留半拍、一拍、两拍三档。",values=function(d) return {speed=d.speed_mult,addition=d.speed_add} end},
    ["speed_down"]={text="飞行速度乘以 {speed}，寿命乘以 {lifetime}。 乐器改为两拍；与加速按数量抵消，只保留半拍、一拍、两拍三档。",values=function(d) return {speed=d.speed_mult,lifetime=d.lifetime_mult} end},
    ["sine"]={text="弹丸左右各摆动 {amplitude} 单位，每秒 {frequency} 次波动。",values=function(d) return {amplitude=d.amplitude,frequency=d.frequency} end},
    ["spiral"]={text="以半径 {amplitude} 单位绕圈前进，每秒 {frequency} 圈。",values=function(d) return {amplitude=d.amplitude,frequency=d.frequency} end},
    ["damage_up"]={text="同一施法块内每枚弹体增加 {damage} 点伤害。",values=function(d) return {damage=d.damage_add} end},
    ["thrust"]={text="从释放点向前刺出长 {reach}、宽 {width} 的范围。",values=function(d) return {reach=d.reach,width=d.width} end},
    ["slash"]={text="从释放点挥出半径 {reach}、{arc}° 的扇形斩击。",values=function(d) return {reach=d.reach,arc=d.arc} end},
    ["heavy_shot"]={text="同组每弹伤害 +{damage}，弹速 ×{speed}，随机散射半角 +{spread}°。",values=function(d) return {damage=d.damage_add,speed=d.speed_mult,spread=d.spread_add} end},
    ["heal_ally"]={text="默认遇受伤队友或玩家随从治疗 {heal} 点并消耗弹丸，遇敌照常攻击。使用目标卡时按所选类别治疗受伤且可治疗的对象。",values=function(d) return {heal=d.heal} end},
    ["giant_shot"]={text="放大远程弹、静态投射物、瞬发效果和近战的外观及实际作用范围。同组倍率相加：1 张 ×{one}、2 张 ×{two}、3 张 ×{three}。伤害数值、移动速度和主体寿命不变。星体照明、温度与理智范围同步扩大；哨株和虫群的自动攻击可覆盖扩大后的范围。独立触发载荷需另装巨化。",values=function(d) return {one=Modifiers.rules.giant_step,two=2*Modifiers.rules.giant_step,three=3*Modifiers.rules.giant_step} end},
    ["shrink_shot"]={text="缩小远程弹、静态投射物、瞬发效果和近战的外观及实际作用范围。每张 ×{multiplier}，多张相乘，最终最低 ×{minimum}。与巨化同组时，先合计巨化倍率再乘缩小倍率；{combination}，与卡牌顺序无关。伤害数值、移动速度和主体寿命不变。星体照明、温度与理智范围同步缩小；哨株和虫群自动攻击范围同步缩小。独立触发载荷需另装缩小。",values=function(d) return {multiplier=Modifiers.rules.shrink_multiplier,minimum=Limits.min_size,combination=M.shrink_combination()} end},
    ["short_life"]={text="同组飞行弹体与触发载体寿命 ×{multiplier}，多张相乘，最低 {minimum} 秒。与延寿修正相乘，可缩短环绕时间；不改变速度、伤害或定时触发的倒计时。碰撞／定时载体正常消失时，若此前未释放过载荷，会在消失处补发一次。火药引线也乘该倍率；也影响有限寿命的静态场；永久晶体与载荷卵仍永久。",values=function(d) return {multiplier=d.lifetime_mult,minimum=Limits.min_lifetime} end},
    ["homing"]={text="搜索半径 {radius}，推进加速度 {force}，阻尼 {damping}；趋近速度 {speed} 单位/秒，转向上限 {turn}°/秒。可推动静止实体。",values=function(d) return {radius=d.radius,force=d.acceleration,damping=d.damping,speed=d.acceleration/d.damping,turn=d.turn_rate} end},
    ["homing_rotate"]={text="搜索半径 {radius}，转向上限 {turn}°/秒。只改变方向，不增加速度。",values=function(d) return {radius=d.radius,turn=d.turn_rate} end},
    ["frost"]={text="直击后灭火并增加 {cold} 寒冷值，由目标冻抗决定冻结。",values=function(d) return {cold=d.freeze} end},
    ["leech"]={text="实际造成的可归属生命损失的 {percent}% 回复给施法者。",values=function(d) return {percent=d.fraction*100} end},
    ["light"]={text="弹体照明半径 {radius}，终止时留光 {duration} 秒，残光数量由世界设置控制。",values=function(d) return {radius=d.radius,duration=d.duration} end},
    ["explosion"]={text="命中时触发半径 {radius}、伤害 {damage} 的爆炸，不分敌我并点燃可燃物；不直接破坏建筑、船和码头，保留法术爆炸外观。穿透命中同样触发，穿墙不触发；目标选择不限制爆炸。它是修饰，不是独立载荷。",values=function(d) return {radius=d.radius,damage=d.explosion_damage} end},
    ["knockback"]={text="沿命中时弹道方向击退约 {distance} 单位，由目标的原生击退动作结算。",values=function(d) return {distance=d.distance} end},
    ["pierce"]={text="最多命中{count}次；重复命中同一敌人至少相隔 {interval} 秒。",values=function(d) return {count=M.word(d.hits,false,false),interval=string.format("%.2f",Runtime.collision.hit_interval)} end},
    ["imprint_timer"]={text="下一枚普通远程弹在 {delay} 秒时释放预载法术。若提前正常消失且此前尚未触发，在消失处补发一次；已触发则不再释放。",values=function(d) return {delay=string.format("%.2f",Modifiers.trigger.time)} end},
    ["spore_sentry"]={text="临时随从，{health} 生命，可被怪物击倒。在释放点萌发，{grow} 秒后索敌。{duration} 秒内向半径 {radius} 内的敌人发射最多{count}枚荚刺。并存数量由世界设置控制。",values=function(d) return {health=Prefabs.garden.spore_sentry.health,grow=Prefabs.garden.spore_sentry.grow_time,duration=Prefabs.garden.spore_sentry.lifetime+Prefabs.garden.spore_sentry.wilt_time,radius=d.radius,count=M.word(Prefabs.garden.spore_sentry.shots,false,false)} end},
    ["vital_ring"]={text="每个环每秒回复 {heal} 生命，共{count}次。默认治疗圈内玩家和玩家随从；使用目标卡时按所选类别治疗适用对象。多个环重叠时，治疗量叠加。",values=function(d) return {heal=Prefabs.garden.vital_ring.heal,count=M.word(Prefabs.garden.vital_ring.pulses,false,false)} end},
    ["chord_d"]={text="在释放点奏出 D 音，回复 {sanity} 理智，每个目标每 {cooldown} 秒最多受益一次。默认作用于附近玩家；使用目标卡时按所选类别作用于有理智的对象。",values=function(d) return {sanity=Prefabs.garden.chord.sanity,cooldown=Prefabs.garden.chord.cooldown} end},
    ["repeat_4"]={text="同组释放{copies}份，每份造成 {damage}% 伤害，副本免耗蓝。击退、吸血及友疗修饰只保留一份；愈合弹的每份按 {heal}% 治疗；载荷计入可选的单发上限。",values=function(d) return {copies=M.word(d.copies,false,false),damage=d.copy_damage*100,heal=d.copy_damage*100} end},
    ["trident_cast"]={text="抽{draw}张法术，分别朝左 {left}°、正前和右 {right}° 释放。每一路仍保留自身散射。",values=function(d) return {draw=M.word(d.draws,false,false),left=-d.fan[1],right=d.fan[3]} end},
    ["orbit"]={text="弹丸随施法者环绕，半径随体型和速度调整（{min_radius}～{max_radius}），平滑入轨，角速度最高 {turn}°/秒。普通弹命中一次消失，基础穿透可命中{hits}次。基础寿命乘 {lifetime}、至少 {minimum} 秒，再应用增减寿命修正，无寿命上限。",values=function(d) return {min_radius=Motion.orbit.min_radius,max_radius=Motion.orbit.max_radius,turn=Motion.orbit.max_turn_rate,hits=M.word(Modifiers.cards.pierce.hits,false,false),lifetime=Modifiers.rules.orbit_lifetime_multiplier,minimum=Modifiers.rules.orbit_min_lifetime} end},
    ["pierce_all"]={text="不限命中次数，同一弹对同一敌人间隔 {interval} 秒；仍受墙与寿命限制。",values=function(d) return {interval=string.format("%.2f",Runtime.collision.hit_interval)} end},
    ["fire"]={text="每次命中蒸发直击伤害 ÷ {divisor} 的潮湿值，仍有潮湿值时不会点燃。干燥后尝试引燃，随后每秒 {damage} 点火伤，共{count}次，各弹独立。",values=function(d) return {divisor=Projectiles.effects.fire.evaporation_divisor,damage=d.burn_damage,count=M.word(d.burn_ticks,false,false)} end},
    ["recharge_down"]={text="施放间隔修正 −{delay} 秒，充能时间修正 −{recharge} 秒。充能修正可持续叠加至负值，实际等待按 0 处理。",values=function(d) return {delay=-d.delay,recharge=-d.recharge} end},
    ["dark"]={text="弹体沿途、连锁闪电的攻击点与跳跃路径留下持续 {minimum}～{maximum} 秒的黑雾。基础半径 {radius}，范围与外观受巨化、缩小影响，不影响玩家。小型生物恐惧停顿 {fear} 秒后慌乱；普通生物目盲，只能感知 {sense} 单位内原本的敌人，失去目标后短暂盲走。暗影生物免控并加速 {speed}%。支持的巨兽优先用原生范围招式驱雾，冷却时尝试可用攻击；均在冷却时在雾中慌乱并持续尝试，{body_delay} 秒后身体驱散沿途暗雾，离雾即停止。原伤害及效果保留。重叠不叠加。",values=function(d) return {minimum=Dark.sources.min_duration,maximum=Dark.sources.max_duration,radius=Dark.sources.radius,fear=Dark.control.fear_time,sense=Dark.control.radius,speed=(Dark.control.shadow_speed-1)*100,body_delay=FogWait.body_delay} end},
    ["edge_voidcloth_scythe"]={text="发射原尺寸两倍的旋转镰刀，采收碰撞半径 {radius}，连续采收沿途植物；同一株只采收一次，{pickup} 单位内优先收入背包。",values=function(d) return {radius=Projectiles.engraved_special.scythe_hit_radius,pickup=NativeEffects.harvest.inventory_range} end},
    ["chain"]={text="从杖头或触发点放电。首击优先前方敌人，碰撞触发优先命中对象。共 {count} 个攻击落点，逐跳间隔 {interval} 秒，每跳最多 {radius} 单位，首跳 {damage}、后续 {later_damage}。无目标时沿发射方向 ±{spread}° 空跳 {distance} 单位，再从落点索敌。按原版电武器结算。 下雨且施法者潮湿、距当前跳点不超过 {backfire_distance} 单位时，后续每跳有 {chance}% 概率反噬，单链最多一次。",values=function(d) return {count=Locale.language=="en" and M.word(d.max_targets,false,true) or d.max_targets,interval=Instant.chain.interval,radius=d.radius,damage=d.damage,later_damage=d.jump_damage,spread=Instant.chain.empty_spread_degrees,distance=d.radius,backfire_distance=d.radius,chance=Instant.chain.backfire_chance*100} end},
    ["gunpowder"]={text="生成原版火药，基础引线随机 {minimum}～{maximum} 秒，再乘寿命修饰倍率。支持静态投射物移动修饰；伤害修饰影响基础伤害 {damage}，巨化同步放大外观与基础爆炸半径 {radius}。不分敌我，保留原版破坏与点燃；被扑灭则消失，存档保留剩余引线。",values=function(d) return {minimum=NativeFallback.gunpowder_fuse_min,maximum=NativeFallback.gunpowder_fuse_max,damage=(TUNING and TUNING.GUNPOWDER_DAMAGE or NativeFallback.gunpowder_damage)*(d.base_damage_multiplier or 1),radius=NativeFallback.gunpowder_radius} end},
    ["edge_lighter"]={text="沿抛物线向施法点投出旋转的打火机，吸收沿途半径 {absorb} 内的火焰；命中或落地时烤熟半径 {radius} 内的食物并点燃可燃物。",values=function(d) return {absorb=Projectiles.engraved_special.fire_radius,radius=Projectiles.engraved_special.fire_radius} end},
    ["edge_chum"]={text="沿抛物线向施法点投掷鱼食，接触地面或海面后撒下饵屑并消失。海面诱鱼，陆地只有视觉效果。施法间隔增加 {delay} 秒。",values=function(d) return {delay=Projectiles.engraved_special.chum_delay} end},
    ["edge_oceanfishingrod"]={text="投出鱼钩。将钩中的海鱼或漂浮物朝施法者方向抛向最近的岸或船，最远 {range} 单位。",values=function(d) return {range=NativeEffects.reel.max_distance} end},
    ["edge_trident"]={text="投出鲸角，在终点发动海上水柱效果，并浸湿周围 {radius} 单位的目标和农田。",values=function(d) return {radius=NativeEffects.trident.wet_radius} end},
    ["edge_minifan"]={text="发射旋转的扇叶，造成 {damage} 点基础伤害。",values=function(d) return {damage=d.damage} end},
    ["edge_shieldofterror"]={text="盾牌在距离施法者 {radius} 单位处环绕。位于攻击范围内时，可在护甲结算前挡下合计 {armor} 点伤害。",values=function(d) return {radius=NativeEffects.shield.radius,armor=NativeEffects.shield.armor} end},
    ["edge_yoth_lance"]={text="朝施放方向射出冲锋骑枪，可穿过{count}个目标。",values=function(d) return {count=M.penetration_count(Projectiles.engraved_special.lance_hits-1)} end},
    ["edge_staff_lunarplant"]={text="命中造成原版亮茄弹的 {planar} 点基础位面伤害，并在合格目标间反弹。穿透时每次命中均可发起一条反弹链。",values=function(d) return {planar=NativeFallback.lunar_projectile_planar*(d.base_damage_multiplier or 1)} end},
    ["near_homing_short"]={text="搜索半径 {radius}，推进加速度 {force}，阻尼 {damping}；趋近速度 {speed} 单位/秒，转向上限 {turn}°/秒。可推动静止实体。",values=function(d) return {radius=d.radius,force=d.acceleration,damping=d.damping,speed=d.acceleration/d.damping,turn=d.turn_rate} end},
}
function M.effect(id,d,fallback)
    local template=templates[id]
    if not template or not d then return fallback end
    return M.format(template.text,template.values(d))
end
function M.trigger_time() return Modifiers.trigger.time end
function M.trajectory_bonus()
    return M.format("弹道延寿 +{bonus}%（不同类型合计最多 +{maximum}%）",{bonus=Modifiers.rules.path_lifetime_bonus*100,maximum=Modifiers.rules.path_lifetime_bonus*Modifiers.rules.path_bonus_limit*100})
end
return M
