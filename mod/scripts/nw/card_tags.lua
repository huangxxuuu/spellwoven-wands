-- Discovery filters, not an exhaustive catalogue of every internal spell field.
-- IDs are independent from translated labels. Ordinary costs/damage do not make
-- a spell a mana/damage modifier, and a targeting radius does not imply AoE.
local Def=require("nw/definitions")
local Arsenal=require("nw/arsenal")
local Identities=require("nw/card_visuals").cards
local T=require("nw/locale").t
local M={}
M.order={"melee","area","element","planar","explosive","control",
    "movement","recovery","defense","tool","music","light",
    "damage","speed","lifetime","target","mana","recharge",
    "trajectory","homing","pierce","multicast","copy","trigger"}
local labels={
    melee="近战",area="范围",element="元素",planar="位面",explosive="爆炸",control="控场",
    movement="位移",recovery="恢复",defense="防御",tool="工具",music="音乐",light="照明",
    damage="伤害",speed="速度",lifetime="寿命",target="目标",mana="法耗",recharge="充能",
    trajectory="弹道",homing="追踪",pierce="穿透",multicast="多重",copy="复制",trigger="触发",
}
local specials={}
local function group(tag,ids)
    for id in ids:gmatch("%S+") do
        specials[id]=specials[id] or {};specials[id][tag]=true
    end
end
-- Geometry is checked against the executor, including environmental effects and
-- scope modifiers. Search radii on sentries/swarms and shield orbits are excluded.
group("area",[[searing_halo twin_arc explosion end_beam spore_ball vital_ring crystal_mine sleep_crystal
    moon_fall bog_whip detonate rain_cloud deer_decoy shock_ring vortex gunpowder giant_shot shrink_shot
    edge_lighter edge_trident edge_voidcloth_scythe edge_staff_tornado edge_chum]])
group("area","dark")
group("control","dark")
group("melee","bog_whip melee_mark")
-- Recovery includes health and sanity gain, not avoidance of an equipment drain.
-- The temporary native shadow axe starts at level 1, whose life steal is zero.
group("recovery","vital_ring leech edge_batbat edge_yellowstaff edge_opalstaff")
-- Actual light sources; fiery/fullbright art alone does not illuminate the world.
group("light","light edge_nightstick edge_torch edge_queen_torch edge_yellowstaff edge_opalstaff")
group("defense","guard_ring edge_shieldofterror")
-- Fire, cold/temperature, electricity and wetness mechanics. Planar stays separate.
group("element",[[edge_lighter edge_torch edge_firestaff chill_touch edge_icestaff edge_opalstaff edge_yellowstaff
    chain tri_electric shock_ring storm_cloud twin_arc rain_cloud edge_trident wet_weak
    edge_dumbbell_bluegem edge_dumbbell_redgem explosion gunpowder]])
group("explosive","explosion crystal_mine sleep_crystal detonate gunpowder end_beam spore_ball")
group("control","slime knockback gust vortex deer_decoy chill_touch edge_icestaff edge_dumbbell_bluegem edge_whip")
-- Movement is displacement of the caster; moving enemies belongs to control.
group("movement","land_hook edge_orangestaff")
group("tool","edge_fishingrod edge_oceanfishingrod edge_trident edge_voidcloth_scythe edge_farm_hoe edge_staff_tornado explosion gunpowder")
-- Trajectory includes spread, directional splitting, returns, orbits and walls.
group("trajectory",[[reverse_path return_path phase_wall homing_rotate weak_homing near_homing side_embers
    edge_voidcloth_boomerang edge_shieldofterror edge_staff_lunarplant edge_staff_tornado]])
group("homing","homing near_homing homing_rotate weak_homing")
group("speed","accelerate")
group("damage","wet_weak melee_mark harmless crit_rune")
group("lifetime","orbit")
group("mana","mana_reduce")
group("recharge","recharge_down wild_charge")

function M.for_card(id)
    local d=Def.spells[id]
    if not d then return {} end
    local tags={}
    if d.kind=="melee" then tags.melee=true;tags.area=true end
    if d.kind=="multicast" then tags.multicast=true end
    if d.copies then tags.copy=true end
    -- Only releasing/imprinting subsequent spells is a trigger. Ordinary hit
    -- effects, crystal detonation and the ocarina's echo do not qualify.
    if d.event or d.imprint then tags.trigger=true end
    if d.heal or d.flag=="leech" then tags.recovery=true end
    if d.burn_damage or d.freeze or d.electric then tags.element=true end
    if d.freeze or d.pillow then tags.control=true end
    if d.planar and d.planar>0 or id=="edge_staff_lunarplant" then tags.planar=true end
    if d.kind=="note" and d.radius or d.native_field then tags.area=true end
    if d.work and #d.work>0 then tags.tool=true end
    if d.speed_mult or d.speed_add then tags.speed=true end
    if d.damage_add or d.damage_mult then tags.damage=true end
    if d.lifetime_mult then tags.lifetime=true end
    if d.select_target then tags.target=true end
    if Arsenal.notes[id] or d.pitch_shift then tags.music=true end
    if Arsenal.notes[id] and Arsenal.notes[id].instrument=="kantele" then tags.recovery=true end
    if Def.trajectory[id] or d.spread_add or d.fan or d.angles or d.ballistic then tags.trajectory=true end
    if d.flag=="pierce" or d.flag=="pierce_all" or d.innate and (d.innate.pierce or d.innate.pierce_all) then tags.pierce=true end
    if d.innate and (d.innate.spiral or d.innate.returning) then tags.trajectory=true end
    if d.innate and d.innate.knockback then tags.control=true end
    -- Engraved dumbbells pierce in flight and invoke the native landing AoE.
    -- The native blue/red bells additionally freeze/ignite; the fresh heat bell
    -- has no persistent heat source after the temporary native item is removed.
    if d.engraving and d.engraving:find("^dumbbell") then tags.pierce=true;tags.area=true end
    for tag in pairs(specials[d.base or id] or {}) do tags[tag]=true end
    -- Use the player-facing main class: copy controls also have kind=modifier
    -- internally, but their damage penalty does not make them damage modifiers.
    if tags.damage and not (Identities[id] and Identities[id].primary_class=="modifier") then tags.damage=nil end
    return tags
end
function M.options(present)
    local options={}
    for _,id in ipairs(M.order) do
        if present[id] then
            options[#options+1]={id=id,text=T(labels[id]),description=T(labels[id])}
        end
    end
    return options
end
return M
