local T=require("nw/locale").t
local Cards=require("nw/cards")
local Info=require("nw/spell_info")
local Def=require("nw/definitions")
local Visual=require("nw/visual")
local M={}

-- Sent on configuration changes only. Use the rolled values, including legacy
-- rolls, rather than reconstructing them from the seed or parsing display text.
local keys={"draw_count","spread","cast_delay","recharge","mana_max","mana_regen","sanity_conversion","capacity"}
function M.encode(data)
    local values={data.stats.shuffle and 1 or 0}
    for _,key in ipairs(keys) do values[#values+1]=data.stats[key] end
    values[#values+1]=data.always_cast or "-"
    return table.concat(values,",")
end
function M.decode(encoded)
    local values={}
    for v in encoded:gmatch("[^,]+") do values[#values+1]=v end
    if #values~=#keys+2 or values[1]~="0" and values[1]~="1" then return end
    local s={shuffle=values[1]=="1",innate=Info.names[values[#values]]}
    for i,key in ipairs(keys) do
        s[key]=tonumber(values[i+1])
        if not s[key] then return end
    end
    return s
end
function M.wand(encoded,slots,look,title)
    local s=M.decode(encoded)
    local cards=Cards.decode(slots)
    if not s or #cards~=s.capacity then return {title=T("正在读取法杖…")} end
    local used=0
    for _,id in ipairs(cards) do if id then used=used+1 end end
    return {title=title,subtitle=s.shuffle and T("乱序") or T("非乱序"),
        atlas=Visual.atlas(look),icon=Visual.icon(look)..".tex",wand_look=look,
        fields={{T("齐发数"),s.draw_count},{T("偏斜"),s.spread.."°"},
            {T("施咒间歇"),s.cast_delay..T(" 秒")},{T("回充时长"),s.recharge..T(" 秒")},
            {T("魔力储量"),s.mana_max},{T("魔力回涌"),s.mana_regen..T(" / 秒")},
            {T("心神转化"),require("nw/generator").sanity_conversion_for(s)},{T("符文槽"),s.capacity}},
        innate=s.innate,slots=slots,count=used.." / "..#cards}
end
function M.card_details(id,brief)
    local d=Def.spells[id]
    if not d then return {title=T("正在读取法术卡…")} end
    local fields={}
    local function add(k,v) fields[#fields+1]={k,v} end
    local tags=require("nw/card_tags")
    local names={}
    for _,tag in ipairs(tags.options(tags.for_card(id))) do names[#names+1]=tag.text end
    local subtitle=table.concat(names," · ")
    if d.jump_damage then add(T("首击 / 后续"),d.damage.." / "..d.jump_damage)
    elseif d.kind=="instant" or d.kind=="melee" then add(T("范围伤害"),d.damage..T(" / 目标"))
    elseif d.kind=="projectile" and d.heal then add(T("命中治疗"),d.heal)
    elseif d.damage then add(T("单弹伤害"),d.count and d.count>1 and d.damage.." × "..d.count or d.damage)
    elseif d.explosion_damage then add(T("范围伤害"),d.explosion_damage..T(" / 目标"))
    elseif id=="gunpowder" then add(T("范围伤害"),(TUNING and TUNING.GUNPOWDER_DAMAGE or 200)..T(" / 目标"))
    elseif d.damage_add then add(T("伤害加成"),string.format("%+g",d.damage_add))
    elseif d.speed_mult then add(T("速度倍率"),"×"..d.speed_mult)
    elseif d.spread_add then add(T("散射修正"),string.format("%+g°",d.spread_add))
    elseif d.turn_rate and not brief then add(T("最大转向"),d.turn_rate..T("° / 秒"))
    elseif d.amplitude and not brief then add(T("振幅"),d.amplitude)
    elseif d.bounces then add(T("反弹次数"),d.bounces)
    elseif d.hits then add(T("最多命中"),d.hits)
    elseif d.flag=="pierce_all" then add(T("最多命中"),T("不限"))
    elseif d.distance then add(T("击退距离"),d.distance)
    elseif d.fraction then add(T("吸血比例"),string.format("%g%%",100*d.fraction))
    elseif d.heal then add(T("治疗量"),d.heal)
    elseif d.copies then add(T("组内份数"),d.copies)
    elseif d.draws then add(T("抽取张数"),d.draws)
    elseif d.imprint then add(T("触发条件"),d.imprint=="hit" and T("碰撞") or T("定时")) end
    add(T("法力消耗"),d.mana)
    add(T("施放修正"),string.format(T("%+.2f 秒"),d.delay))
    add(T("充能修正"),string.format(T("%+.2f 秒"),d.recharge or 0))
    if d.kind=="field" and id~="guard_ring" then add(T("基础移速"),T("0 / 秒")) end
    if d.speed then
        add(T("弹速"),d.speed..T(" / 秒"));add(T("寿命"),d.lifetime..T(" 秒"))
        local range=require("nw/spell_limits").range
        add(T("基础射程"),math.min(range>0 and range or math.huge,d.speed*d.lifetime))
        if d.halfangle then add(T("基础散射"),"±"..d.halfangle.."°") end
    end
    if d.frequency and not brief then add(T("频率"),d.frequency..T(" / 秒")) end
    if d.lifetime_mult then add(T("寿命倍率"),"×"..d.lifetime_mult) end
    if d.reach then add(d.width and T("攻击距离") or T("范围半径"),d.reach) end
    if d.radius then
        local label=d.jump_damage and T("跳跃距离") or d.flag=="orbit" and T("轨道半径")
            or d.flag=="homing" and T("搜索半径") or d.flag=="light" and T("照明半径") or T("作用半径")
        add(label,d.radius)
    end
    if d.work and #d.work>0 then add(T("工作半径"),d.work_radius);add(T("工作效率"),T("原工具 ×0.75")) end
    if d.planar then add(T("位面伤害"),d.planar) end
    local note=require("nw/arsenal").notes[id]
    if note then add(T("音级"),note.label) end
    if d.pitch_shift then add(T("音高偏移"),string.format(T("%+d 半音"),d.pitch_shift)) end
    if d.max_targets then add(T("最多目标"),d.max_targets) end
    if Def.trajectory[id] then add(T("弹道延寿"),"+8%") end
    local effect=Info.effect(id)
    if Def.trajectory[id] then effect=effect..T(" 不同弹道的额外延寿合计最多 +24%。") end
    return {title=Info.names[id],subtitle=subtitle,tags=names,atlas="images/inventoryimages/nw_icons.xml",
        icon=Info.icon(id),fields=fields,effect=effect}
end
function M.card(id)
    local data=M.card_details(id,true)
    if data.fields then data.effect=Info.brief(id) end
    return data
end
return M
