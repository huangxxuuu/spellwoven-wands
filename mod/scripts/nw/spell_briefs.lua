-- Player-facing summaries. Numerical reference text remains in spell_info.effects.
local M={}
local text={
pitch_octave_up={"将同组乐器音升高一个八度；升降先抵消，最终最多升降一个八度。","Raises this group's notes by an octave; shifts cancel before clamping to one octave up or down."},
pitch_octave_down={"将同组乐器音降低一个八度；升降先抵消，最终最多升降一个八度。","Lowers this group's notes by an octave; shifts cancel before clamping to one octave up or down."},
pitch_semitone_up={"将同组乐器音升高一个半音；升降先抵消，最终最多升降一个八度。","Raises this group's notes by a semitone; shifts cancel before clamping to one octave up or down."},
pitch_semitone_down={"将同组乐器音降低一个半音；升降先抵消，最终最多升降一个八度。","Lowers this group's notes by a semitone; shifts cancel before clamping to one octave up or down."},
spark={"发射一枚轻型魔法火花。","Fires a light magical spark."},
arrow={"发射一枚快速而精准的魔法箭。","Fires a fast, accurate magic arrow."},
heavy={"发射一枚缓慢而沉重的魔法弹。","Fires a slow, heavy magic bolt."},
scatter={"扇形发射一簇散弹，每枚独立命中并触发载荷。","Fires a fan of pellets, each with its own hits and triggers."},
fire={"发射炽热的火焰弹，蒸干并点燃目标。","Fires a fiery bolt that dries and ignites its target."},
frost={"发射冰霜弹，使目标降温并扑灭火焰。","Fires a frost bolt that chills its target and extinguishes flames."},
speed_up={"提高投射物初速度，也能推动静止法术。乐器改为半拍，与减速按数量抵消，只保留半拍、一拍、两拍。","Increases launch speed and sets stationary spells in motion. Instruments use half a beat; Speed Up and Slow Down cancel by count, leaving half, one or two beats."},
speed_down={"降低投射物速度并延长飞行时间。乐器改为两拍，与加速按数量抵消，只保留半拍、一拍、两拍。","Slows projectiles and extends flight time. Instruments use two beats; Speed Up and Slow Down cancel by count, leaving half, one or two beats."},
damage_up={"提高投射物和攻击法术的伤害。","Increases projectile and attack spell damage."},
precision={"降低投射物的散射。","Reduces projectile spread."},
sine={"使投射物沿波浪形弹道飞行。","Makes projectiles travel in a wave."},
spiral={"使投射物沿螺旋形弹道飞行。","Makes projectiles travel in a spiral."},
homing={"给予投射物向附近目标方向的加速度。","Accelerates projectiles toward nearby targets."},
near_homing={"给予投射物向近距离目标方向的强劲加速度。","Strongly accelerates projectiles toward targets at short range."},
homing_rotate={"使投射物转向附近目标，不增加速度。","Turns projectiles toward nearby targets without adding speed."},
weak_homing={"使投射物缓慢转向附近目标。","Gently turns projectiles toward nearby targets."},
bounce={"使投射物撞墙后反弹。","Makes projectiles bounce off walls."},
pierce={"使投射物穿过目标并继续造成命中。","Lets projectiles pass through targets and keep hitting."},
pierce_all={"使投射物持续穿透目标。","Lets projectiles keep piercing targets."},
phase_wall={"使投射物穿过墙体，不触发撞墙效果。","Lets projectiles pass through walls without a wall impact."},
explosion={"使法术命中时爆炸，伤及周围敌友并点燃物体，不直接摧毁建筑、船和码头。","Makes spell impacts explode, harming friend and foe and igniting objects without directly demolishing structures, boats or docks."},
gunpowder={"放下一堆燃烧的火药。可受移动修饰影响，寿命修饰改变引线时长；被扑灭则消失。","Places burning gunpowder. Movement modifiers affect it; lifetime modifiers change its fuse. Vanishes if extinguished."},
chain={"释放在附近目标之间跳跃的闪电；雨中潮湿时可能反噬。","Releases lightning that jumps between nearby targets; it may backfire when you are wet in the rain."},
knockback={"使法术命中时击退目标。","Adds knockback to spell impacts."},
leech={"将部分造成的伤害转化为施法者的生命。","Restores the caster's health from a portion of damage dealt."},
light={"使投射物发光，并在消失处留下短暂余光。","Makes projectiles shine and leave a brief afterglow."},
double={"同时施放后续的一对法术。","Casts the next pair of spells together."},
triple={"同时施放后续的一组三个法术。","Casts the next three spells together."},
thrust={"向前刺出一柄长矛。","Thrusts a spear forward."},
slash={"挥出一道宽阔的玻璃刀斩击。","Swings a glass cutter in a broad arc."},
whirl={"旋斧绕柄下端水平扫过一圈，攻击并砍伐周围目标。","Sweeps an axe around its lower grip, striking and chopping nearby targets."},
orbit={"使投射物环绕施法者飞行。","Makes projectiles orbit the caster."},
imprint_hit={"为下一枚普通投射物添加碰撞载荷。","Adds an impact-triggered payload to the next ordinary projectile."},
imprint_timer={"为下一枚普通投射物添加定时载荷。","Adds a timed payload to the next ordinary projectile."},
heal_ally={"使投射物接触受伤的友方时为其治疗。","Lets projectiles heal wounded allies on contact."},
mana_reduce={"降低本次施法的法力消耗。","Reduces the mana cost of the cast."},
recharge_down={"缩短法杖的施放间隔与充能时间。","Reduces cast delay and wand recharge time."},
repeat_2={"复制本组法术，使其成对释放。","Duplicates this spell group."},
repeat_3={"将本组法术复制成三份释放。","Casts three copies of this spell group."},
repeat_4={"释放更多本组法术的副本，但每份威力降低。","Casts more copies of this spell group at reduced power."},
spore_sentry={"种下一株短暂存在、自动攻击附近目标的荚刺哨株。","Plants a temporary thorn sentry that attacks nearby targets."},
vital_ring={"生成一片短暂恢复生命的区域。","Creates a temporary healing area."},
heavy_shot={"增强投射物伤害，但降低速度并增加散射。","Makes projectiles stronger, slower and less accurate."},
giant_shot={"放大法术的外观和实际作用范围，不直接增加伤害。","Enlarges spells and their effective areas without directly increasing damage."},
trident_cast={"将后续法术向前方呈扇形分开施放。","Casts the following spells in a forward fan."},
short_life={"缩短投射物与有限场地法术的存在时间，也缩短火药引线。","Shortens projectile and finite field lifetimes, including star duration and gunpowder fuses."},
gust={"发射推开目标的气流，也能推动载荷卵而不击破它。","Fires a gust that pushes targets and moves payload eggs without breaking them."},
spore_ball={"发射缓慢飘行、破裂时伤害附近目标的孢球。","Fires a drifting spore ball that bursts to hurt nearby targets."},
flint_lance={"投出能够穿透目标的燧晶长枪。","Throws a flint lance that pierces targets."},
crystal_mine={"放置感应附近目标后引爆的晶雷。","Places a crystal mine that detonates when targets approach."},
sleep_crystal={"放置可受击引爆、也可用晶雷引爆令启动的晶体。","Places a crystal that detonates when attacked or activated by Detonate Crystals."},
slime={"发射黏液，黏滞命中的目标。","Fires slime that slows its target."},
grow_orb={"发射在飞行中逐渐变大的魔法球。","Fires a magic orb that grows as it travels."},
heal_bolt={"发射为命中目标恢复生命的治疗弹。","Fires a bolt that heals its target."},
star_vortex={"发射分裂成旋转弹群的星旋。","Fires a star vortex made of swirling projectiles."},
moon_fall={"在指定地点召唤延迟落下的月石。","Calls down a moon rock after a brief delay."},
bog_whip={"从释放点向前挥出触手鞭击。","Lashes a tentacle forward from the release point."},
detonate={"引爆指定地点附近属于自己的晶体。","Detonates your crystals near the selected point."},
bee_swarm={"召唤短暂袭击附近目标的蜂群。","Summons a swarm that briefly attacks nearby targets."},
delay_seal={"留下符印，稍后从符印处释放载荷法术。","Leaves a seal that releases its payload after a delay."},
rain_cloud={"召唤局部雨云，浸湿附近目标并灭火。","Summons a rain cloud that wets nearby targets and extinguishes fires."},
guard_ring={"召唤环绕自身、抵消敌方投射物的护盾。","Summons orbiting shields that block incoming enemy projectiles."},
wild_charge={"缩短充能时间，但增加投射物散射。","Reduces recharge time at the cost of greater spread."},
long_life={"延长投射物与有限场地法术的存在时间，也延长火药引线。","Extends projectile and finite field lifetimes, including star duration and gunpowder fuses."},
reverse_path={"使投射物飞行一段时间后掉头。","Makes projectiles reverse direction after a short flight."},
return_path={"使投射物飞出后转向施法者返航。","Makes projectiles turn back toward the caster."},
light_shot={"使投射物更快、更精准，但降低伤害。","Makes projectiles faster and more accurate, but weaker."},
accelerate={"使投射物在飞行中逐渐加速。","Makes projectiles accelerate during flight."},
chill_touch={"使法术命中时附带寒冷。","Adds chilling power to spell impacts."},
wet_weak={"提高法术对潮湿目标造成的伤害。","Increases spell damage against wet targets."},
melee_mark={"使命中的目标更易受到接下来的近战攻击。","Marks targets to take more damage from the next melee strike."},
wild_double={"同时施放后续的一对法术，但增加散射。","Casts the next pair of spells together with greater spread."},
two_way={"将后续法术分别向前后施放。","Casts following spells forward and backward."},
note_a={"发出短鸣，为命中的目标留下回声标记。","Fires a short note that marks its target for an echo."},
note_c={"发出应答声波，引发短鸣标记的回声伤害。","Fires a responding note that triggers an echo on marked targets."},
glass_disc={"发射能够穿透目标并折返的月玻璃飞刃。","Fires a piercing moon-glass blade that turns back."},
land_hook={"发射抓钩，将施法者牵引向陆地落点。","Fires a hook that pulls the caster toward its land destination."},
tri_electric={"发射一簇带有电击效果的魔法球。","Fires a cluster of electrified magic orbs."},
end_beam={"发射贯穿光束，留下间隔伤害的紫色光带，在终点聚爆。","Fires a piercing purple beam that leaves a lingering damage trail and bursts at its endpoint."},
deer_decoy={"召唤吸引附近敌人的灵鹿，结束时旋身消散并造成轻微伤害。","Summons a spirit deer that draws nearby enemies, then spins and fades with a gentle hit."},
payload_egg={"留下储存载荷的空心卵。被攻击打破后释放法术，归击破者施放。","Leaves an egg containing a payload. Breaking it releases the spells under the breaker's ownership."},
fireflies={"召唤短暂伴随并袭击附近目标的萤虫。","Summons brief firefly companions that attack nearby targets."},
shock_ring={"生成向周围释放电击的法术环。","Creates a ring that shocks nearby targets."},
storm_cloud={"召唤向附近目标落雷的局部雷云。","Summons a local storm cloud that strikes nearby targets."},
vortex={"生成将附近目标拉向中心的漩涡。","Creates a vortex that pulls nearby targets inward."},
harmless={"移除投射物的直接伤害，但保留其载荷。","Removes a projectile's direct damage while retaining its payload."},
searing_halo={"使投射物持续灼伤身边的目标。","Makes projectiles scorch nearby targets as they travel."},
twin_arc={"在同时施放的投射物之间连接伤害电弧。","Links projectiles from the same cast with damaging arcs."},
side_embers={"使飞行中的投射物向两侧发射余烬。","Makes flying projectiles emit embers to either side."},
crit_rune={"提高法术造成暴击的机会。","Increases the chance of a critical spell hit."},
cast_four={"同时施放后续的一组四个法术。","Casts the next four spells together."},
hex_cast={"将后续法术向周围各个方向展开施放。","Spreads the following spells around the caster."},
}
local tools={NET={"捕捉","catch creatures"},CHOP={"砍伐","chop"},DIG={"挖掘","dig"},MINE={"采矿","mine"},HAMMER={"锤击","hammer"},SCYTHE={"采收","harvest"},TILL={"翻土","till soil"},TERRAFORM={"铲起地皮","remove turf"}}
local weapons={
lighter={"向施法点抛出旋转的打火机，吸收沿途火焰，命中或落地时烤熟食物并点燃周围物品。","Lobs a spinning lighter toward the cast point, absorbing flames along its path and cooking food and igniting nearby objects on impact or landing."},
oceanfishingrod={"投出鱼钩，将钩中的海鱼或漂浮物拉向岸边或船上。","Casts a hook that reels ocean fish or floating objects toward shore or a boat."},
fishingrod={"投出钓竿，从命中的池塘中钓出鱼。","Casts a fishing rod that catches a fish from a pond."},
voidcloth_scythe={"发射旋转的巨大镰刀，持续采收沿途植物。","Fires a large spinning scythe that harvests plants along its path."},
chum={"抛出鱼食，在海面撒下诱鱼的饵屑。","Throws chum that attracts fish on the ocean."},
farm_hoe={"抛出锄头翻土，无法翻土时继续弹跳。","Throws a hoe that tills soil and bounces if it cannot."},
trident={"投出鲸角，在终点引发水柱并浸湿周围。","Throws a horn that erupts in a waterspout and wets its surroundings."},
orangestaff={"发射橙色魔弹，将施法者传送至弹体的落点。","Fires an orange bolt that teleports the caster to its destination."},
voidcloth_boomerang={"投出逐渐变大的暗影回旋镖，命中后折返。","Throws a growing shadow boomerang that returns after impact."},
firestaff={"发射能够点燃目标的火魔杖弹。","Fires a fire-staff projectile that ignites targets."},
icestaff={"发射能够灭火和冻结目标的冰魔杖弹。","Fires an ice-staff projectile that extinguishes and chills targets."},
staff_lunarplant={"发射在目标间反弹的亮茄魔杖弹。","Fires a brightshade projectile that bounces between targets."},
staff_tornado={"释放朝瞄准点前进、随后游荡破坏的龙卷风。","Releases a tornado that advances toward the aim point, then roams and destroys."},
yellowstaff={"召唤提供光亮与温暖的矮星，可被移动修饰推动。","Summons a dwarf star that provides light and warmth and can be moved by modifiers."},
opalstaff={"召唤散发清冷光芒的月光球，可被移动修饰推动。","Summons a chilling lunar light that can be moved by modifiers."},
shieldofterror={"召唤环绕自身、替自己挡下伤害的恐怖盾牌。","Summons an orbiting terror shield that absorbs incoming damage."},
minifan={"发射旋转的扇叶。","Fires a spinning fan blade."},
yoth_lance={"射出能够穿透目标的冲锋骑枪。","Fires a charging lance that pierces targets."},
}
function M.get(id)
    local lang=require("nw/locale").language=="en" and 2 or 1
    local d=require("nw/definitions").spells[id]
    local row=text[id]
    local arsenal=require("nw/arsenal")
    if arsenal.notes[id] then
        local summary=row and row[lang] or (arsenal.notes[id].instrument=="kantele"
            and ({"奏响琴音，使周围玩家回复理智。","Plays a lyre note that restores nearby players' sanity."})[lang]
            or ({"发出短鸣，为命中的目标留下回声标记。","Fires a short note that marks its target for an echo."})[lang])
        return summary.."\n"..arsenal.tone_description(id)
    end
    if row then return row[lang] end
    if d and d.base then
        return M.get(d.base)..(d.event=="hit" and ({"命中时释放载荷法术。"," Releases its payload on impact."})[lang]
            or ({"飞行片刻后释放载荷法术，每枚弹体独立触发。"," Releases its payload after a brief flight; each projectile triggers independently."})[lang])
    end
    if id=="trigger_hit" or id=="trigger_timer" then return M.get("spark")..(id=="trigger_hit" and ({"命中时释放载荷。"," Releases its payload on impact."})[lang] or ({"稍后释放载荷。"," Releases its payload after a delay."})[lang]) end
    if d and d.select_target then
        local kind={hostile={"敌对生物","hostile creatures"},neutral={"中立生物","neutral creatures"},friendly={"友好生物","friendly creatures"},building={"建筑","structures"},nature={"自然物","natural objects"},players_other={"其他玩家","other players"},self={"自身","the caster"}}
        return lang==1 and "使本组法术选取"..kind[d.select_target][1].."作为目标。" or "Lets this spell group target "..kind[d.select_target][2].."."
    end
    if d and d.source_weapon then
        local key=d.source_weapon
        if weapons[key] then return weapons[key][lang] end
        if key:find("^dumbbell") then return ({"抛出哑铃，命中和落地时发挥其力量。","Throws a dumbbell that strikes in flight and releases its power on landing."})[lang] end
        local actions={}
        for _,a in ipairs(d.work or {}) do if tools[a] then actions[#actions+1]=tools[a][lang] end end
        local summary=lang==1 and "挥出"..require("nw/spell_info").names[id].."的攻击。" or "Attacks with "..require("nw/spell_info").names[id].."."
        if #actions>0 then summary=summary..(lang==1 and "同时可以"..table.concat(actions,"、").."。" or " Can also "..table.concat(actions,", ")..".") end
        if key=="torch" or key=="lighter" then summary=summary..({"能够点燃目标。"," Can ignite targets."})[lang] end
        if d.electric then summary=summary..({"附带电击效果。"," Carries an electric effect."})[lang] end
        if d.planar then summary=summary..({"附带位面伤害。"," Deals planar damage."})[lang] end
        if d.pillow then summary=summary..({"能够击退目标。"," Can knock targets back."})[lang] end
        return summary
    end
    error("Missing brief spell description: "..tostring(id))
end
return M
