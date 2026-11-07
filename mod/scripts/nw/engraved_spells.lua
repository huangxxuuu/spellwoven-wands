local T=require("nw/locale").t
-- Keep retired definitions readable for saves and preserve their original network codes.
local M={retired={}}
for source in ([[oar oar_driftwood oar_monkey malbatross_beak cane compass witchbroom golden_farm_hoe
    fumarole_farm_hoe pitchfork goldenpitchfork wateringcan premiumwateringcan merm_tool merm_tool_upgraded
    bugnet thulecitebugnet wortox_nabbag brush saddlehorn gestalt_cage queen_torch king_cane cutless
    rabbitkingspear houndstooth_blowpipe wathgrithr_shield lucy carnivalgame_golfclub yoth_knightstick vault_compass]]):gmatch("%S+") do
    M.retired["edge_"..source]=true
end

-- speed, lifetime, damage, description. Effects marked utility never deal impact damage.
local shots={
    lighter={16,1.5,17,T("沿抛物线向施法点投出旋转的打火机，吸收沿途半径 3 内的火焰；命中或落地时烤熟半径 3 内的食物并点燃可燃物。")},
    chum={18,4,0,T("沿抛物线向施法点投掷鱼食，接触地面或海面后撒下饵屑并消失。海面诱鱼，陆地只有视觉效果。施法间隔增加 10 秒。")},
    fishingrod={14,1,0,T("沿飞行方向投出钓竿。命中可垂钓水源后收线，渔获落在朝向施法者的池塘边。")},
    oceanfishingrod={16,1.3,0,T("投出鱼钩。将钩中的海鱼或漂浮物朝施法者方向抛向最近的岸或船，最远 20 单位。")},
    trident={16,1,0,T("投出鲸角，在终点发动海上水柱效果，并浸湿周围 2 单位的目标和农田。")},
    orangestaff={18,1.5,0,T("橙色魔弹消失时将施法者移至落点。不能穿透，海上落点可能导致落水。")},
    voidcloth_boomerang={15,20/15,5,T("投出原版暗影回旋镖。去程随飞行逐渐变大，物理与位面伤害同时增长，命中或飞至尽头后飞回。")},
    voidcloth_scythe={10,1.6,0,T("发射快速自转的无伤镰刀，连续采收沿途宽 1.6 单位内的植物，不因采收而消失。同一株只采收一次；8 单位以内优先收入背包，装不下的留在地上。")},
    farm_hoe={18,4,0,T("锄头朝前，沿抛物线投向施法点。成功翻出土堆后消失；落点不能翻土时向前弹跳，寿命耗尽后消失。")},
    minifan={15,1,5,T("发射旋转的扇叶，造成 5 点基础伤害。")},
    shieldofterror={12,5,0,T("盾牌在距离施法者 2 单位处环绕。位于攻击范围内时，可在护甲结算前挡下合计 50 点伤害。")},
    yoth_lance={18,1,51,T("朝施放方向射出冲锋骑枪，可穿过两个目标。")},
    firestaff={50,.3,0,T("朝施放方向发射原版火魔杖弹，命中时引燃。")},
    icestaff={50,.3,0,T("朝施放方向发射原版冰魔杖弹，命中时灭火、施加寒冷。")},
    staff_lunarplant={15,25/15,0,T("命中造成原版亮茄弹的 10 点基础位面伤害，并在合格目标间反弹。穿透时每次命中均可发起一条反弹链。")},
    staff_tornado={10,1.6,0,T("龙卷风先朝瞄准点前进，随后在附近游荡并破坏。触发释放时先沿弹道前进。")},
}
M.extra={{"voidcloth_boomerang",T("暗影回旋镖")},
    {"firestaff",T("火魔杖")},{"icestaff",T("冰魔杖")},{"staff_lunarplant",T("亮茄魔杖")},{"staff_tornado",T("天气风向标")},
    {"yellowstaff",T("唤星法杖")},{"opalstaff",T("唤月法杖")}}
function M.configure(c,key)
    if key=="yellowstaff" or key=="opalstaff" then
        c.kind,c.native_field,c.cooldown="field",key=="yellowstaff" and "stafflight" or "staffcoldlight",key=="yellowstaff" and 240 or 60
        c.delay,c.damage,c.no_impact_damage=0,0,true
        c.effect=T("在释放点生成原版")..(key=="yellowstaff" and T("矮星") or T("极光"))..T("，寿命、照明、温度和理智效果与原版相同。基础静止，可用加速、减速、追踪和目标选择改变移动。整次施法冷却至少 ")..c.cooldown..T(" 秒，作为触发载荷时同样生效。")
        return
    end
    local shot=shots[key]
    if key:find("^dumbbell") then
        shot={15,4,c.native_base_damage,T("斜抛哑铃，在空中穿过并攻击目标，落地后触发该哑铃的原版效果。")}
        c.ballistic=true
    end
    if shot then
        c.kind,c.speed,c.lifetime,c.damage,c.effect="projectile",unpack(shot)
        c.engraving=key
        c.arc,c.width,c.work_radius,c.reach,c.work,c.windup,c.duration=nil,nil,nil,nil,nil,nil,nil
        c.halfangle=0
        c.no_impact_damage=c.damage==0
    end
    if key=="chum" then c.delay=10;c.ballistic=true
    elseif key=="voidcloth_scythe" then c.planar=nil;c.hit_radius=1.6
    elseif key=="voidcloth_boomerang" then c.planar=5
    elseif key=="farm_hoe" then c.ballistic=true
    elseif key=="yoth_lance" then c.innate={pierce={hits=3}}
    elseif key=="nightsword" then c.mana=32;c.effect=T("挥出暗夜剑。每次施法耗费 32 法力，持杖期间没有暗夜剑的持续理智损耗。")
    elseif key=="whip" or key=="bullkelp_root" or key=="pocketwatch_weapon" then
        c.pose,c.reach,c.width,c.arc=key=="pocketwatch_weapon" and "pocketwatch_atk" or "whip",4,1,nil
        c.work_radius=c.reach
        c.effect=(key=="pocketwatch_weapon" and T("挥动警钟") or T("挥出鞭击"))..T("，攻击距离 4 单位。")
    elseif key=="propsign" then
        c.pose,c.damage,c.no_impact_damage,c.pillow,c.arc="atk_prop",0,true,1.5,360
        c.effect=T("挥动道具招牌击飞附近目标，不造成伤害。")
    elseif key=="hambat" then c.damage=c.native_base_damage;c.effect=T("以满新鲜度火腿棒的攻击力挥击。")
    elseif key=="lighter" then c.fire_radius=3;c.ballistic=true
    elseif key=="ruins_bat" then c.effect=c.effect..T(" 有概率在命中处召唤暗影触手。")
    elseif key=="fumaroleaxe" or key=="fumarolepickaxe" then c.effect=c.effect:gsub("75%%","100%%") end
end
return M
