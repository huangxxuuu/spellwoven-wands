local C=require("nw/constants/acquisition").rewards
local Sources = require("nw/sources")
local Catalog = require("nw/natural_loot")
local M = {}
local ordinary={event="death"}
local exceptions={
    twinofterror1={event="loot"}, twinofterror2={event="loot"},
    sharkboi={event="minhealth"}, daywalker2={event="loot"}, wagdrone_rolling={event="loot"},
}
local excluded={}
for id in ([[
    charlie_boss wagboss_robot wagboss_robot_leg stalker_npc alterguardian_phase1 alterguardian_phase2
    alterguardian_phase1_lunarrift alterguardian_phase2_lunarrift alterguardian_phase3_lunarrift
    worm_boss_head worm_boss_tail worm_boss_segment worm_boss_dirt worm_boss_shadow_head
    worm_boss_shadow_tail worm_boss_shadow_segment worm_boss_shadow_dirt shadowthrall_centipede_head
    shadowthrall_centipede_body crabking_claw crabking_claw_shadow crabking_cannontower crabking_icewall
    tentacle_pillar_arm lunarthrall_plant_vine lunarthrall_plant_vine_end hedgehound_bush
    sharkboi_ice_hazard sharkboi_icespike nw_target_dummy nw_spell_punchingbag nw_spore_sentry
]]):gmatch("%S+") do excluded[id]=true end

local function source_name(inst)
    local id=inst.prefab
    return (id=="twinofterror1" or id=="twinofterror2") and "twins" or id
end
local function natural_materials(inst,name)
    if (name=="bat" and inst.components.acidinfusible and inst.components.acidinfusible:IsInfused())
        or ((name=="rocky" or name=="rocky_boss") and inst.nitregrowth) then
        return Catalog[name.."_acid"]
    elseif name=="monkey" and inst:HasTag("nightmare") then
        return Catalog.monkey_shadowloot
    elseif name=="rabbit" or name=="bunnyman" then
        local timer=inst.components.timer
        if timer and timer:TimerExists("forcenightmare") then return Catalog[name.."_shadowloot"] end
        if name=="rabbit" then
            local killer=inst.components.health.causeofdeath
            local observer=killer and killer.components.follower and killer.components.follower:GetLeader() or killer
            local sanity=observer and observer.replica.sanity
            if sanity and sanity:IsInsanityMode() and sanity:GetPercentNetworked() <=
                (observer:HasTag("dappereffects") and TUNING.DAPPER_BEARDLING_SANITY or TUNING.BEARDLING_SANITY) then
                return Catalog.rabbit_shadowloot
            end
        end
    end
    if Catalog[name] and name~="shadowthrall_parasite" then return Catalog[name] end
    local loot=inst.components.lootdropper
    return loot and loot:GetAllPossibleLoot(false) or {}
end
local function eligible(inst, event)
    local rule = Sources.by_prefab[inst.prefab] or exceptions[inst.prefab] or ordinary
    if rule.event ~= event or inst.components.nw_rewarded then return false end
    if excluded[inst.prefab] or inst:HasTag("player") or inst:HasTag("wall") or inst:HasTag("FX") then return false end
    if not Catalog[source_name(inst)] then
        if inst:HasTag("structure") or not (inst:HasTag("animal") or inst:HasTag("monster")
            or inst:HasTag("insect") or inst:HasTag("bird") or inst:HasTag("epic")
            or inst:HasTag("smallcreature") or inst:HasTag("largecreature") or
            (inst.components.combat and inst.components.locomotor and not inst:HasTag("inventoryitem"))) then return false end
    end
    if event == "death" then
        if not inst.components.health or not inst.components.health:IsDead() then return false end
        if inst.prefab == "bat_boss_shadow" then
            local twin = inst.components.entitytracker:GetEntity("clone")
            if twin and not twin.components.health:IsDead() then
                inst:AddComponent("nw_rewarded")
                return false
            end
        end
    elseif event == "loot" then
        if source_name(inst)=="twins" then
            for _,id in ipairs(inst.components.lootdropper.loot or {}) do
                if id=="shieldofterror" then return inst.components.health:IsDead() end
            end
            return false
        end
        if inst.prefab == "daywalker" or inst.prefab=="daywalker2" then return inst.defeated and inst.looted end
        if inst.prefab=="wagdrone_rolling" then
            local hp=inst.components.health
            return hp and hp.currenthealth<=hp.minhealth and inst.components.lootdropper.chanceloottable=="wagdrone_common"
        end
        if inst.prefab == "vault_pillar_guard" then return inst.trial and inst._vault_death_loot end
        if inst.prefab == "alterguardian_phase4_lunarrift" then
            return inst.sg.currentstate.name == "selfdestruct"
        end
        return inst.components.health and inst.components.health:IsDead()
    elseif event == "minhealth" then
        return inst.components.health.currenthealth<=inst.components.health.minhealth
    elseif event == "dropkey" then
        return inst:IsUnchained() and inst.components.health:IsDead()
    end
    return true
end
local function payout(inst, event)
    if not eligible(inst,event) then return end
    local name=source_name(inst)
    local rule=Sources.by_prefab[name] or ordinary
    inst:AddComponent("nw_rewarded")
    if event=="death" then inst.components.nw_rewarded.reset_on_revive=true end
    local pool=Sources.material_pool(natural_materials(inst,name),rule.group)
    local reward = Sources.roll(name,rule,pool,M.cardmult,M.wandmult,math.random)
    local origin = inst
    if inst.components.centipedebody then
        origin = inst.components.centipedebody.head_in_control or inst
    end
    local pt = origin:GetPosition()
    local function drop(name)
        if inst.components.lootdropper then return inst.components.lootdropper:SpawnLootPrefab(name,pt) end
        local item = SpawnPrefab(name)
        item.Transform:SetPosition(pt:Get())
        return item
    end
    if reward.core then drop(reward.core) end
    if reward.dust then drop("nw_dust").components.stackable:SetStackSize(reward.dust) end
    local loaded=false
    if reward.tier then
        local wand = drop("nw_wand")
        local cmp=wand.components.nw_wand
        cmp:InitializeNew(reward.tier,inst.prefab,{group=rule.group,kinds=rule.kinds,cards=rule.cards,material_pool=pool})
        for _,card in ipairs(cmp.data.cards) do
            if card then loaded=true;break end
        end
    end
    local health=inst.components.health
    reward.card=Sources.finish_card(health and health.maxhealth or 0,reward.card,loaded,M.cardmult,math.random)
    if reward.card then
        local card = drop("nw_spellcard")
        card.source = inst.prefab
        card:SetSpell(reward.card)
    end
    require("nw/first_boss_reward").pay(inst,origin,drop,rule)
end
function M.install(env)
    M.cardmult = env.GetModConfigData("card_drop_rate") or C.default_card_rate
    M.wandmult = env.GetModConfigData("wand_drop_rate") or C.default_wand_rate
    env.AddPrefabPostInit("world", function(world)
        if not world.ismastersim then return end
        world:AddComponent("nw_identity")
        if env.GetModConfigData("starting_wand") ~= false then
            world:ListenForEvent("ms_newplayerspawned",function(_,player)
                local spawner=world.components.playerspawner
                if not spawner or not spawner:IsPlayersInitialSpawn(player) then return end
                local wand=SpawnPrefab("nw_wand")
                wand.components.nw_wand:InitializeNew(0,"starter")
                player.components.inventory:GiveItem(wand)
                if not wand.components.inventoryitem:IsHeld() then
                    player:DoTaskInTime(0,function()
                        if wand:IsValid() and not wand.components.inventoryitem:IsHeld() then
                            wand.Transform:SetPosition(player.Transform:GetWorldPosition())
                        end
                    end)
                end
            end)
        end
        world:ListenForEvent("entity_death",function(_,data)
            if data and data.inst then payout(data.inst,"death") end
        end)
        world:ListenForEvent("entity_droploot", function(_,data)
            if data and data.inst then payout(data.inst,"loot") end
        end)
    end)
    local function hook(name,rule)
        local event = rule.event
        if event ~= "loot" and event ~= "death" then
            env.AddPrefabPostInit(name, function(inst)
                if TheWorld.ismastersim then
                    inst:ListenForEvent(event,function(entity) payout(entity,event) end)
                end
            end)
        end
    end
    for name,rule in pairs(Sources.by_prefab) do hook(name,rule) end
    for name,rule in pairs(exceptions) do hook(name,rule) end
end
return M
