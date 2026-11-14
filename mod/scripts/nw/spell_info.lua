local Work=require("nw/constants/melee").work
local P=require("nw/spell_parameter_text")
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
    speed_up=P.effect("speed_up",D.spells.speed_up),
    speed_down=P.effect("speed_down",D.spells.speed_down),
    sine=P.effect("sine",D.spells.sine),
    spiral=P.effect("spiral",D.spells.spiral),
    homing=T("使弹体逐渐转向附近可攻击目标。"),
    bounce=T("每次撞墙结算碰撞效果并反弹，最多反弹两次。穿墙时忽略墙面。"),
    pierce=T("使弹体穿过目标，最多命中三个目标。"),
    knockback=T("命中后将可击退目标向后推开。"),
    leech=T("将部分有效伤害转化为施法者的生命。"),
    light=T("使弹体携带临时光源。"),
    double=T("继续抽取两张法术，合并为同一施法块。"),
    triple=T("继续抽取三张法术，合并为同一施法块。"),
    trigger_hit=T("发射载体弹；碰撞后释放预载法术。若此前从未成功释放载荷，正常消失时在消失处补发一次。"),
    trigger_timer=P.format("发射载体弹；{delay} 秒后释放预载法术。若此前尚未触发，正常消失时在消失处补发一次；已触发则不再释放。",{delay=D.spells.trigger_timer.time}),
    damage_up=P.effect("damage_up",D.spells.damage_up),
    precision=string.format(T("同一施法块的随机散射半角减少 %g 度，最低为零。"), -D.spells.precision.spread_add),
    weak_homing=T("固有修饰：以较小转向速度追踪附近目标。"),
}
local more={
    spore_sentry={T("荚刺哨株"),T("哨株"),P.effect("spore_sentry",D.spells.spore_sentry)},
    vital_ring={T("活力环"),T("活力"),P.effect("vital_ring",D.spells.vital_ring)},
    heavy_shot={T("沉重一击"),T("重击"),P.effect("heavy_shot",D.spells.heavy_shot)},
    trident_cast={T("三叉阵"),T("三叉"),P.effect("trident_cast",D.spells.trident_cast)},
    chord_d={T("弦琴 D·和鸣"),T("和鸣"),P.effect("chord_d",D.spells.chord_d)},
    repeat_4={T("四倍施法"),T("四倍"),P.effect("repeat_4",D.spells.repeat_4)},
    phase_wall={T("穿墙"),T("穿墙"),T("弹丸穿过完整墙体，优先于弹跳；穿越时不触发命中。可跨越海岸。")},
    mana_reduce={T("蓝耗降低"),T("节蓝"),P.format("抽下一张，立即提供 {mana} 法力支付后续卡。成功施法后剩余法力最多为法杖上限。",{mana=-D.spells.mana_reduce.mana})},
    recharge_down={T("减少充能时间"),T("快充"),T("抽下一张，缩短当前施法间隔与本轮整杖充能，均可降至零。仍受原版攻击动作与法术专属冷却约束。")},
    repeat_2={T("双倍施法"),T("双倍"),T("抽下一张。当前组的攻击同时释放两份，各自携带载荷。副本免耗蓝，真实抽到的卡计费一次。")},
    repeat_3={T("三倍施法"),T("三倍"),T("抽下一张。当前组的攻击同时释放三份。倍数可相乘，预载计入可选的单发上限。副本免耗蓝。")},
    thrust={T("长矛戳击"),T("矛刺"),P.effect("thrust",D.spells.thrust)},
    slash={T("玻璃刀砍"),T("刀砍"),P.effect("slash",D.spells.slash)},
    whirl={T("斧子旋转"),T("旋斧"),P.format("绕释放点扫过半径 {radius} 的小圆，每敌只伤一次。",{radius=D.spells.whirl.reach})},
    orbit={T("环绕自身"),T("环绕"),P.effect("orbit",D.spells.orbit)},
    pierce_all={T("高级穿透"),T("贯穿"),P.effect("pierce_all",D.spells.pierce_all)},
    imprint_hit={T("碰撞触发修饰"),T("碰印"),T("为下一枚普通远程弹或连锁闪电添加碰撞载荷。普通远程弹每次有效命中目标或撞墙时释放；若此前从未成功释放，正常消失时补发一次。连锁闪电每次跳跃命中分别释放，空跳和结束不补发。")},
    imprint_timer={T("定时触发修饰"),T("时印"),P.effect("imprint_timer",D.spells.imprint_timer)},
    heal_ally={T("命中友方回血"),T("友疗"),P.effect("heal_ally",D.spells.heal_ally)},
}
for _,card in ipairs(require("nw/expansion")) do more[card.id]={card.name,card.name,card.effect} end
for _,c in ipairs(require("nw/arsenal").cards) do more[c.id]={c.name,c.name,c.effect} end
for _,c in ipairs(require("nw/arsenal").extra_notes) do more[c.id]={c.name,c.name,c.effect} end
for _,c in ipairs(require("nw/pitch_modifiers").cards) do more[c.id]={c.name,c.name,c.effect} end
for id,v in pairs(more) do M.names[id],M.short[id],M.effects[id]=v[1],v[2],v[3] end
M.names.giant_shot=T("弹体巨化");M.short.giant_shot=T("巨化")
M.names.shrink_shot=T("弹体缩小");M.short.shrink_shot=T("缩小")
M.effects.shrink_shot=P.effect("shrink_shot",D.spells.shrink_shot)
M.names.short_life=T("缩短寿命");M.short.short_life=T("短寿")
M.names.homing_rotate=T("转向敌人");M.short.homing_rotate=T("转向")
M.effects.short_life=P.effect("short_life",D.spells.short_life)
M.effects.giant_shot=P.effect("giant_shot",D.spells.giant_shot)
M.effects.whirl=M.effects.whirl..P.format(" 对释放点半径 {radius} 内的可砍目标累积普通斧头 {efficiency}% 的工作量。",{radius=D.spells.whirl.work_radius,efficiency=Work.credit*100})
M.effects.speed_up=M.effects.speed_up..T(" 静态投射物获得向前速度，不改变音符音高。")
M.effects.speed_down=M.effects.speed_down..T(" 不改变音符音高。")
M.effects.fire=P.effect("fire",D.spells.fire)
M.effects.frost=P.effect("frost",D.spells.frost)
M.effects.leech=P.effect("leech",D.spells.leech)
M.effects.pierce=P.effect("pierce",D.spells.pierce)
M.effects.chain=P.effect("chain",D.spells.chain)
M.effects.knockback=P.effect("knockback",D.spells.knockback)
M.names.dark=T("暗雾");M.short.dark=T("暗雾")
M.effects.dark=P.effect("dark",D.spells.dark)
M.effects.light=P.effect("light",D.spells.light)
for _,id in ipairs(D.bullets) do
    for _,event in ipairs({"hit","timer"}) do
        local key=id.."_"..event
        M.names[key]=M.names[id]..T("·")..(event=="hit" and T("碰撞") or T("定时"))
        M.short[key]=M.short[id]..(event=="hit" and T("碰") or T("时"))
        M.effects[key]=M.effects[id].."\n"..(event=="hit" and T("每次有效碰撞时从弹丸位置释放载荷。若此前从未成功释放，正常消失时补发一次；已释放则不在消失时重复。") or P.format("飞行 {delay} 秒时释放载荷。若提前正常消失且此前尚未触发，在消失处补发一次；已触发则不再释放。散弹的每枚弹体独立释放定时载荷。",{delay=string.format("%.2f",P.trigger_time())}))
    end
end
for id in pairs(D.spells) do M.playable[id]=true end
function M.icon(id) return "nw_spell_"..id..".tex" end
function M.effect(id)
    if id=="mana_reduce" then
        return string.format(T("抽下一张，立即提供 %g 法力支付后续卡。成功施法后剩余法力最多为法杖上限。"),-D.spells[id].mana)
    end
    local effect=require("nw/spell_damage_text").get(id,M.effects[id])
    if id=="dark" and require("nw/dark_fog").effects_disabled then
        effect=effect.."\n"..T("（已禁用，只有视觉效果）")
    end
    return effect
end
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
    if D.trajectory[id] then lines[#lines+1]=P.trajectory_bonus() end
    if d.kind=="field" and id~="guard_ring" then lines[#lines+1]=T("基础移速 0；加速可推动，追踪可自行起步。") end
    lines[#lines+1]=T("效果：")..M.effect(id)
    if not M.playable[id] then lines[#lines+1]=T("实战效果尚未开放") end
    return table.concat(lines,"\n")
end
M.names.whirl=T("旋斧攻击")
M.names.ocarina_g=T("陶笛 G");M.short.ocarina_g=M.names.ocarina_g
M.effects.ocarina_g=T("奏响 G 音，短程声波留下回声标记。")
M.names.gunpowder=T("火药")
M.short.gunpowder=M.names.gunpowder
M.effects.gunpowder=P.effect("gunpowder",D.spells.gunpowder)
M.effects.explosion=P.effect("explosion",D.spells.explosion)
M.effects.homing=P.effect("homing",D.spells.homing)
M.effects.near_homing=P.effect("near_homing_short",D.spells.near_homing)
M.effects.homing_rotate=P.effect("homing_rotate",D.spells.homing_rotate)
M.effects.recharge_down=P.effect("recharge_down",D.spells.recharge_down)
M.effects.edge_voidcloth_scythe=P.effect("edge_voidcloth_scythe",D.spells.edge_voidcloth_scythe)
M.effects.payload_egg=T("永久保存载荷。直接攻击、范围攻击和爆炸均可击破，载荷归实际攻击者；无有效攻击者时使用中立施法源。风压只推动。陆地、船、海面边界不可跨越；在海上生成会落水消失。")
for id in pairs(require("nw/arsenal").notes) do
    M.effects[id]=(M.effects[id] or "").." "..require("nw/arsenal").tone_description(id)
end
function M.brief(id)
    local brief=require("nw/spell_briefs").get(id)
    if id=="dark" and require("nw/dark_fog").effects_disabled then
        brief=brief.."\n"..T("（已禁用，只有视觉效果）")
    end
    return brief
end
function M.tooltip(id)
    return D.spells[id] and M.brief(id) or T("空法术槽")
end
return M
