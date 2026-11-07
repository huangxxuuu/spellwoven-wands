local T=require("nw/locale").t
local D=require("nw/definitions")
local M={}
M.names={spark=T("火花弹"),arrow=T("魔法箭"),heavy=T("重能量球"),scatter=T("散弹"),fire=T("火焰弹"),frost=T("冰霜弹"),
    speed_up=T("加速"),speed_down=T("减速"),sine=T("正弦弹道"),spiral=T("螺旋弹道"),homing=T("追踪"),bounce=T("弹跳"),
    pierce=T("穿透"),explosion=T("爆炸"),chain=T("连锁闪电"),knockback=T("击退"),leech=T("生命汲取"),light=T("照明"),
    double=T("双重施法"),triple=T("三重施法"),trigger_hit=T("碰撞触发"),trigger_timer=T("定时触发"),
    damage_up=T("伤害强化"),precision=T("精准"),weak_homing=T("微弱追踪")}
M.short={spark=T("火花"),arrow=T("魔箭"),heavy=T("重弹"),scatter=T("散弹"),fire=T("火焰"),frost=T("冰霜"),
    speed_up=T("加速"),speed_down=T("减速"),sine=T("正弦"),spiral=T("螺旋"),homing=T("追踪"),bounce=T("弹跳"),
    pierce=T("穿透"),explosion=T("爆炸"),chain=T("闪电"),knockback=T("击退"),leech=T("汲取"),light=T("照明"),
    double=T("双重"),triple=T("三重"),trigger_hit=T("碰触"),trigger_timer=T("定时"),damage_up=T("增伤"),precision=T("精准"),weak_homing=T("弱追")}
M.playable={spark=true,arrow=true,heavy=true,scatter=true,double=true,triple=true,speed_up=true,speed_down=true,damage_up=true,precision=true}
M.effects={
    spark=T("发射一枚轻型魔法火花。"),
    arrow=T("发射一枚飞行更快的魔法箭。"),
    heavy=T("发射缓慢但威力更大的能量球。"),
    scatter=T("同时发射三枚向不同方向散开的弹丸。"),
    fire=T("命中后造成火焰伤害，并施加持续灼烧。"),
    frost=T("命中后造成伤害，并累积冰冻效果。"),
    speed_up=T("同组初速度 ×1.5，另加 2 单位/秒初速度；多张倍率相乘、初速度增量相加。"),
    speed_down=T("飞行速度乘以 0.65，寿命乘以 1.4。"),
    sine=T("弹丸左右各摆动 1.2 单位，每秒 1.6 次波动。"),
    spiral=T("以半径 1.45 单位绕圈前进，每秒 2.4 圈。"),
    homing=T("使弹体逐渐转向附近可攻击目标。"),
    bounce=T("每次撞墙结算碰撞效果并反弹，最多反弹两次。穿墙时忽略墙面。"),
    pierce=T("使弹体穿过目标，最多命中三个目标。"),
    knockback=T("命中后将可击退目标向后推开。"),
    leech=T("将部分有效伤害转化为施法者的生命。"),
    light=T("使弹体携带临时光源。"),
    double=T("继续抽取两张法术，合并为同一施法块。"),
    triple=T("继续抽取三张法术，合并为同一施法块。"),
    trigger_hit=T("发射载体弹；碰撞后释放预载法术。若此前从未成功释放载荷，正常消失时在消失处补发一次。"),
    trigger_timer=T("发射载体弹；0.5 秒后释放预载法术。若此前尚未触发，正常消失时在消失处补发一次；已触发则不再释放。"),
    damage_up=T("同一施法块内每枚弹体增加 10 点伤害。"),
    precision=string.format(T("同一施法块的随机散射半角减少 %g 度，最低为零。"), -D.spells.precision.spread_add),
    weak_homing=T("固有修饰：以较小转向速度追踪附近目标。"),
}
local more={
    spore_sentry={T("荚刺哨株"),T("哨株"),T("临时随从，60 生命，可被怪物击倒。在释放点萌发，0.6 秒后索敌。6 秒内向半径 4 内的敌人发射最多三枚荚刺。并存数量由世界设置控制。")},
    vital_ring={T("活力环"),T("活力"),T("每个环每秒为圈内玩家和玩家随从回复 2 生命，共三次。多个环重叠时，治疗量叠加。")},
    heavy_shot={T("沉重一击"),T("重击"),T("同组每弹伤害 +12，弹速 ×0.65，随机散射半角 +2°。")},
    trident_cast={T("三叉阵"),T("三叉"),T("抽三张法术，分别朝左 20°、正前和右 20° 释放。每一路仍保留自身散射。")},
    chord_d={T("弦琴 D·和鸣"),T("和鸣"),T("在释放点奏出 D 音，附近玩家回复 1 理智，每位玩家每 3 秒最多受益一次。")},
    repeat_4={T("四倍施法"),T("四倍"),T("同组释放四份，每份造成 45% 伤害，副本免耗蓝。击退、吸血及友疗修饰只保留一份；愈合弹的每份按 45% 治疗；载荷计入可选的单发上限。")},
    phase_wall={T("穿墙"),T("穿墙"),T("弹丸穿过完整墙体，优先于弹跳；穿越时不触发命中。可跨越海岸。")},
    mana_reduce={T("蓝耗降低"),T("节蓝"),T("抽下一张，立即提供 30 法力支付后续卡。成功施法后剩余法力最多为法杖上限。")},
    recharge_down={T("减少充能时间"),T("快充"),T("抽下一张，缩短当前施法间隔与本轮整杖充能。最低分别为 0.20 秒、0.30 秒。")},
    repeat_2={T("双倍施法"),T("双倍"),T("抽下一张。当前组的攻击同时释放两份，各自携带载荷。副本免耗蓝，真实抽到的卡计费一次。")},
    repeat_3={T("三倍施法"),T("三倍"),T("抽下一张。当前组的攻击同时释放三份。倍数可相乘，预载计入可选的单发上限。副本免耗蓝。")},
    thrust={T("长矛戳击"),T("矛刺"),T("从释放点向前刺出长 2.4、宽 1 的范围。")},
    slash={T("玻璃刀砍"),T("刀砍"),T("从释放点挥出半径 2.2、100° 的扇形斩击。")},
    whirl={T("斧子旋转"),T("旋斧"),T("绕释放点扫过半径 1.15 的小圆，每敌只伤一次。")},
    orbit={T("环绕自身"),T("环绕"),T("弹丸随施法者环绕，半径随体型和速度调整（2.5～8），平滑入轨，角速度最高 210°/秒。普通弹命中一次消失，基础穿透可命中三次。基础寿命乘 4、至少 4 秒，再应用增减寿命修正，无寿命上限。")},
    pierce_all={T("高级穿透"),T("贯穿"),T("不限命中次数，同一弹对同一敌人间隔 0.10 秒；仍受墙与寿命限制。")},
    imprint_hit={T("碰撞触发修饰"),T("碰印"),T("下一枚普通远程弹每次有效命中敌人或撞墙时释放预载法术。若此前从未成功释放载荷，正常消失时补发一次；已释放则不在消失时重复。")},
    imprint_timer={T("定时触发修饰"),T("时印"),T("下一枚普通远程弹在 0.50 秒时释放预载法术。若提前正常消失且此前尚未触发，在消失处补发一次；已触发则不再释放。")},
    heal_ally={T("命中友方回血"),T("友疗"),T("遇受伤队友或玩家随从治疗 8 点并消耗弹丸，遇敌照常攻击。")},
}
for _,card in ipairs(require("nw/expansion")) do more[card.id]={card.name,card.name,card.effect} end
for _,c in ipairs(require("nw/arsenal").cards) do more[c.id]={c.name,c.name,c.effect} end
for _,c in ipairs(require("nw/pitch_modifiers").cards) do more[c.id]={c.name,c.name,c.effect} end
for id,v in pairs(more) do M.names[id],M.short[id],M.effects[id]=v[1],v[2],v[3] end
M.names.giant_shot=T("弹体巨化");M.short.giant_shot=T("巨化")
M.names.short_life=T("缩短寿命");M.short.short_life=T("短寿")
M.names.homing_rotate=T("转向敌人");M.short.homing_rotate=T("转向")
M.effects.homing_rotate=T("半径 8，每 0.10 秒重选目标，最多转向 360°/秒。只改变方向，不提供速度；静止实体需先获得初速度或外部推动。")
M.effects.short_life=T("同组飞行弹体与触发载体寿命 ×0.5，多张相乘，最低 0.1 秒。与延寿修正相乘，可缩短环绕时间；不改变速度、伤害或定时触发的倒计时。碰撞／定时载体正常消失时，若此前未释放过载荷，会在消失处补发一次。火药引线也乘该倍率；也影响有限寿命的静态场；永久晶体与载荷卵仍永久。")
M.effects.giant_shot=T("放大远程弹、静态投射物、瞬发效果和近战的外观及实际作用范围。同组倍率相加：1 张 ×2.5、2 张 ×5、3 张 ×7.5。伤害数值、移动速度和主体寿命不变。星体照明、温度与理智范围同步扩大；哨株和虫群的自动攻击可覆盖扩大后的范围。独立触发载荷需另装巨化。")
M.effects.whirl=M.effects.whirl..T(" 对释放点半径 1.15 内的可砍目标累积普通斧头 75% 的工作量。")
M.effects.speed_up=M.effects.speed_up..T(" 静态投射物获得向前速度，不改变音符音高。")
M.effects.speed_down=M.effects.speed_down..T(" 不改变音符音高。")
M.effects.fire=T("每次命中蒸发直击伤害 ÷ 5 的潮湿值，仍有潮湿值时不会点燃。干燥后尝试引燃，随后每秒 3.6 点火伤，共三次，各弹独立。")
M.effects.frost=T("直击后灭火并增加 0.4 寒冷值，由目标冻抗决定冻结。")
M.effects.homing=T("半径 8，每 0.10 秒重选目标。朝目标施加 12 单位/秒²推进，并施加速度阻尼 0.24；持续同向追踪时速度趋近 50 单位/秒，永久实体额外阻力会降低此速度。可推动静止实体。多张推进与阻尼相加，与短距离追踪独立叠加。")
M.effects.leech=T("实际造成的可归属生命损失的 5% 回复给施法者。")
M.effects.pierce=T("最多命中三次；重复命中同一敌人至少相隔 0.10 秒。")
M.effects.explosion=T("从杖头或载体触发点立即爆炸一次，半径 3，每个敌人受 25 点基础伤害。")
M.effects.chain=T("从杖头或触发点放电。首击优先前方敌人，碰撞触发优先命中对象。共 4 个攻击落点，逐跳间隔 0.15 秒，每跳最多 6 单位，首跳 15、后续 10。无目标时沿发射方向 ±85° 空跳 6 单位，再从落点索敌。按原版电武器结算。")..T(" 下雨且施法者潮湿、距当前跳点不超过 6 单位时，后续每跳有 20% 概率反噬，单链最多一次。")
M.effects.knockback=T("沿命中时弹道方向击退约 1 单位，由目标的原生击退动作结算。")
M.effects.light=T("弹体照明半径 2，终止时留光 3 秒，残光数量由世界设置控制。")
for _,id in ipairs(D.bullets) do
    for _,event in ipairs({"hit","timer"}) do
        local key=id.."_"..event
        M.names[key]=M.names[id]..T("·")..(event=="hit" and T("碰撞") or T("定时"))
        M.short[key]=M.short[id]..(event=="hit" and T("碰") or T("时"))
        M.effects[key]=M.effects[id].."\n"..(event=="hit" and T("每次有效碰撞时从弹丸位置释放载荷。若此前从未成功释放，正常消失时补发一次；已释放则不在消失时重复。") or T("飞行 0.50 秒时释放载荷。若提前正常消失且此前尚未触发，在消失处补发一次；已触发则不再释放。散弹的每枚弹体独立释放定时载荷。"))
    end
end
for id in pairs(D.spells) do M.playable[id]=true end
function M.icon(id) return "nw_spell_"..id..".tex" end
function M.detailed_tooltip(id)
    local d=D.spells[id]
    if not d then return T("空法术槽") end
    local damage = d.jump_damage and string.format(T("基础电伤 %g / %g / %g / %g"),d.damage,d.jump_damage,d.jump_damage,d.jump_damage)
        or (d.kind=="melee" or d.kind=="instant") and string.format(T("范围伤害 %g / 目标"),d.damage)
        or d.kind=="projectile" and d.heal and string.format(T("命中治疗 %g"),d.heal)
        or d.damage and string.format(T("单弹伤害 %g × %d 枚"),d.damage,d.count or 1)
        or d.damage_add and string.format(T("每弹附加伤害 %+g"),d.damage_add) or T("直接伤害 无")
    local lines={M.names[id],damage..T("    法力消耗：")..d.mana,
        string.format(T("施法间隔修正 %+.2f 秒    充能时间修正 %+.2f 秒"),d.delay,d.recharge or 0)}
    if d.cooldown then lines[#lines+1]=T("整次施法冷却下限 ")..d.cooldown..T(" 秒（含触发载荷）") end
    if d.ballistic then lines[#lines+1]=string.format(T("水平初速 %g/秒，落地结算"),d.speed)
    elseif d.engraving=="shieldofterror" then lines[#lines+1]=string.format(T("环绕时间 %g 秒"),d.lifetime)
    elseif d.speed then lines[#lines+1]=string.format(T("弹速 %g/秒    寿命 %g 秒"),d.speed,d.lifetime) end
    if d.halfangle and not d.ballistic and d.engraving~="shieldofterror" then
        local range=require("nw/spell_limits").range
        lines[#lines+1]=string.format(T("基准散射 ±%g°    基础直射距离 %g"),d.halfangle,math.min(range>0 and range or math.huge,d.speed*d.lifetime))
    end
    if D.trajectory[id] then lines[#lines+1]=T("弹道延寿 +8%（不同类型合计最多 +24%）") end
    if d.kind=="field" and id~="guard_ring" then lines[#lines+1]=T("基础移速 0；加速可推动，追踪可自行起步。") end
    lines[#lines+1]=T("效果：")..M.effects[id]
    if not M.playable[id] then lines[#lines+1]=T("实战效果尚未开放") end
    return table.concat(lines,"\n")
end
M.names.whirl=T("旋斧攻击")
M.names.ocarina_g=T("陶笛 G");M.short.ocarina_g=M.names.ocarina_g
M.effects.ocarina_g=T("奏响 G 音，短程声波留下回声标记。")
M.names.gunpowder=T("火药")
M.short.gunpowder=M.names.gunpowder
M.effects.gunpowder=T("生成原版火药，基础引线随机 3～6 秒，再乘寿命修饰倍率。支持静态投射物移动修饰；伤害修饰影响基础伤害 200，巨化同步放大外观与基础爆炸半径 3。不分敌我，保留原版破坏与点燃；被扑灭则消失，存档保留剩余引线。")
M.effects.explosion=T("命中时触发半径 3、伤害 25 的爆炸，不分敌我并点燃可燃物；不直接破坏建筑、船和码头，保留法术爆炸外观。穿透命中同样触发，穿墙不触发；目标选择不限制爆炸。它是修饰，不是独立载荷。")
M.effects.homing=T("搜索半径 8，推进加速度 36，阻尼 0.72；趋近速度 50 单位/秒，转向上限 360°/秒。可推动静止实体。")
M.effects.near_homing=T("搜索半径 3，推进加速度 72，阻尼 1.44；趋近速度 50 单位/秒，转向上限 360°/秒。可推动静止实体。")
M.effects.homing_rotate=T("搜索半径 8，转向上限 360°/秒。只改变方向，不增加速度。")
M.effects.recharge_down=T("施放间隔修正 −0.17 秒，充能时间修正 −0.33 秒。充能修正可持续叠加至负值，实际等待按 0 处理。")
M.effects.edge_voidcloth_scythe=T("发射原尺寸两倍的旋转镰刀，采收碰撞半径 1.6，连续采收沿途植物；同一株只采收一次，8 单位内优先收入背包。")
M.effects.payload_egg=T("永久保存载荷。直接攻击、范围攻击和爆炸均可击破，载荷归实际攻击者；无有效攻击者时使用中立施法源。风压只推动。陆地、船、海面边界不可跨越；在海上生成会落水消失。")
for id in pairs(require("nw/arsenal").notes) do
    M.effects[id]=(M.effects[id] or "").." "..require("nw/arsenal").tone_description(id)
end
M.brief=require("nw/spell_briefs").get
function M.tooltip(id)
    return D.spells[id] and M.brief(id) or T("空法术槽")
end
return M
