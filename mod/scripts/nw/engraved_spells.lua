local Work=require("nw/constants/melee").work
local NativeEffects=require("nw/constants/native_effects")
local P=require("nw/spell_parameter_text")
local Projectile=require("nw/constants/projectiles")
local Shots=Projectile.engraved
local Special=Projectile.engraved_special
local Melee=require("nw/constants/melee").engraving
local Fields=require("nw/constants/fields")
local T=require("nw/locale").t
local M={retired={}}
for source in ([[oar oar_driftwood oar_monkey malbatross_beak cane compass witchbroom golden_farm_hoe
    fumarole_farm_hoe pitchfork goldenpitchfork wateringcan premiumwateringcan merm_tool merm_tool_upgraded
    bugnet thulecitebugnet wortox_nabbag brush saddlehorn gestalt_cage queen_torch king_cane cutless
    rabbitkingspear houndstooth_blowpipe wathgrithr_shield lucy carnivalgame_golfclub yoth_knightstick vault_compass]]):gmatch("%S+") do
    M.retired["edge_"..source]=true
end

local shots={
    lighter={Shots.lighter.speed,Shots.lighter.lifetime,Shots.lighter.damage,P.effect("edge_lighter",Shots.lighter)},
    chum={Shots.chum.speed,Shots.chum.lifetime,Shots.chum.damage,P.effect("edge_chum",Shots.chum)},
    fishingrod={Shots.fishingrod.speed,Shots.fishingrod.lifetime,Shots.fishingrod.damage,T("沿飞行方向投出钓竿。命中可垂钓水源后收线，渔获落在朝向施法者的池塘边。")},
    oceanfishingrod={Shots.oceanfishingrod.speed,Shots.oceanfishingrod.lifetime,Shots.oceanfishingrod.damage,P.effect("edge_oceanfishingrod",Shots.oceanfishingrod)},
    trident={Shots.trident.speed,Shots.trident.lifetime,Shots.trident.damage,P.effect("edge_trident",Shots.trident)},
    orangestaff={Shots.orangestaff.speed,Shots.orangestaff.lifetime,Shots.orangestaff.damage,T("橙色魔弹消失时将施法者移至落点。不能穿透，海上落点可能导致落水。")},
    voidcloth_boomerang={Shots.voidcloth_boomerang.speed,Shots.voidcloth_boomerang.lifetime,Shots.voidcloth_boomerang.damage,T("投出原版阴郁回旋镖。去程随飞行逐渐变大，物理与位面伤害同时增长，命中或飞至尽头后飞回。")},
    voidcloth_scythe={Shots.voidcloth_scythe.speed,Shots.voidcloth_scythe.lifetime,Shots.voidcloth_scythe.damage,P.format("发射快速自转的无伤镰刀，连续采收沿途宽 {radius} 单位内的植物，不因采收而消失。同一株只采收一次；{range} 单位以内优先收入背包，装不下的留在地上。",{radius=Special.scythe_hit_radius,range=NativeEffects.harvest.inventory_range})},
    farm_hoe={Shots.farm_hoe.speed,Shots.farm_hoe.lifetime,Shots.farm_hoe.damage,T("锄头朝前，沿抛物线投向施法点。成功翻出土堆后消失；落点不能翻土时向前弹跳，寿命耗尽后消失。")},
    minifan={Shots.minifan.speed,Shots.minifan.lifetime,Shots.minifan.damage,P.effect("edge_minifan",Shots.minifan)},
    shieldofterror={Shots.shieldofterror.speed,Shots.shieldofterror.lifetime,Shots.shieldofterror.damage,P.effect("edge_shieldofterror",Shots.shieldofterror)},
    yoth_lance={Shots.yoth_lance.speed,Shots.yoth_lance.lifetime,Shots.yoth_lance.damage,P.effect("edge_yoth_lance",Shots.yoth_lance)},
    firestaff={Shots.firestaff.speed,Shots.firestaff.lifetime,Shots.firestaff.damage,T("朝施放方向发射原版火魔杖弹，命中时引燃。")},
    icestaff={Shots.icestaff.speed,Shots.icestaff.lifetime,Shots.icestaff.damage,T("朝施放方向发射原版冰魔杖弹，命中时灭火、施加寒冷。")},
    staff_lunarplant={Shots.staff_lunarplant.speed,Shots.staff_lunarplant.lifetime,Shots.staff_lunarplant.damage,P.effect("edge_staff_lunarplant",Shots.staff_lunarplant)},
    staff_tornado={Shots.staff_tornado.speed,Shots.staff_tornado.lifetime,Shots.staff_tornado.damage,T("龙卷风先朝瞄准点前进，随后在附近游荡并破坏。触发释放时先沿弹道前进。")},
}
M.extra={{"voidcloth_boomerang",T("阴郁回旋镖")},
    {"firestaff",T("火魔杖")},{"icestaff",T("冰魔杖")},{"staff_lunarplant",T("亮茄魔杖")},{"staff_tornado",T("天气风向标")},
    {"yellowstaff",T("唤星法杖")},{"opalstaff",T("唤月法杖")}}
function M.configure(c,key)
    if key=="yellowstaff" or key=="opalstaff" then
        c.kind,c.native_field,c.cooldown="field",key=="yellowstaff" and "stafflight" or "staffcoldlight",Fields.native_cooldown[key]
        c.delay,c.damage,c.no_impact_damage=0,0,true
        c.effect=T("在释放点生成原版")..(key=="yellowstaff" and T("矮星") or T("极光"))..T("，寿命、照明、温度和理智效果与原版相同。固有无限穿透。基础静止，可用加速、减速、追踪和目标选择改变移动；环境附带效果不受目标选择限制。整次施法冷却至少 ")..c.cooldown..T(" 秒，作为触发载荷时同样生效。")
        return
    end
    local shot=shots[key]
    if key:find("^dumbbell") then
        shot={Special.dumbbell.speed,Special.dumbbell.lifetime,c.native_base_damage,T("斜抛哑铃，在空中穿过并攻击目标，落地后触发该哑铃的原版效果。")}
        c.ballistic=true
    end
    if shot then
        c.kind,c.speed,c.lifetime,c.damage,c.effect="projectile",unpack(shot)
        c.engraving=key
        c.arc,c.width,c.work_radius,c.reach,c.work,c.windup,c.duration=nil,nil,nil,nil,nil,nil,nil
        c.halfangle=0
        c.no_impact_damage=c.damage==0
    end
    if key=="chum" then c.delay=Special.chum_delay;c.ballistic=true
    elseif key=="voidcloth_scythe" then c.planar=nil;c.hit_radius=Special.scythe_hit_radius
    elseif key=="voidcloth_boomerang" then c.planar=Special.boomerang_planar
    elseif key=="farm_hoe" then c.ballistic=true
    elseif key=="yoth_lance" then c.innate={pierce={hits=Special.lance_hits}}
    elseif key=="nightsword" then c.mana=Melee.nightsword_mana;c.effect=P.format("挥出暗夜剑。每次施法耗费 {mana} 法力，持杖期间没有暗夜剑的持续理智损耗。",{mana=Melee.nightsword_mana})
    elseif key=="whip" or key=="bullkelp_root" or key=="pocketwatch_weapon" then
        c.pose,c.reach,c.width,c.arc=key=="pocketwatch_weapon" and "pocketwatch_atk" or "whip",Melee.whip.reach,Melee.whip.width,nil
        c.work_radius=c.reach
        c.effect=(key=="pocketwatch_weapon" and T("挥动警钟") or T("挥出鞭击"))..P.format("，攻击距离 {reach} 单位。",{reach=Melee.whip.reach})
    elseif key=="propsign" then
        c.pose,c.damage,c.no_impact_damage,c.pillow,c.arc="atk_prop",0,true,Melee.propsign.pillow,Melee.propsign.arc
        c.effect=T("挥动道具招牌击飞附近目标，不造成伤害。")
    elseif key=="hambat" then c.damage=c.native_base_damage;c.effect=T("以满新鲜度火腿棒的攻击力挥击。")
    elseif key=="lighter" then c.fire_radius=Special.fire_radius;c.ballistic=true
    elseif key=="ruins_bat" then c.effect=c.effect..T(" 有概率在命中处召唤暗影触手。")
    elseif key=="fumaroleaxe" or key=="fumarolepickaxe" then c.effect=c.effect:gsub(string.format("%g",Work.credit*100).."%%","100%%") end
end
return M
