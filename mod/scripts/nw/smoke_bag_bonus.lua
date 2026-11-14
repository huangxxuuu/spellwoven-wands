local M={}
function M.run()
    TheWorld:PushEvent("ms_setclocksegs",{day=16,dusk=0,night=0})
    local a,b=SpawnPrefab("wilson"),SpawnPrefab("wilson")
    for _,p in ipairs({a,b}) do p.components.health:SetInvincible(true);p.entity:SetCanSleep(false) end
    local bag=assert(SpawnPrefab("nw_spell_punchingbag"))
    bag.Transform:SetPosition(0,0,0);a.Transform:SetPosition(1,0,0);b.Transform:SetPosition(12,0,0)
    assert(bag.components.trader and bag.components.inventory and bag.components.workable,"NW_BAG: native components")
    assert(bag.components.workable:GetWorkLeft()==6 and bag:HasTag("equipmentmodel"),"NW_BAG: native interactions")
    assert(AllRecipes.nw_spell_punchingbag and AllRecipes.nw_spell_punchingbag.placer=="nw_spell_punchingbag_placer")
    require("nw/punchingbag").visual(bag)
    assert(bag._nw_spark_badge.AnimState:GetBuild()=="nw_objects")
    bag.components.combat:GetAttacked(a,18.5)
    bag.components.combat:GetAttacked(b,18.5)
    assert(math.abs(bag._nw_combo.total-37)<.001,"NW_BAG: combined damage")
    bag.components.health:DoDelta(100)
    bag:PushEvent("blocked",{})
    assert(bag._nw_combo.total==37,"NW_BAG: regen/block must not reset")
    bag._nw_combo.last_hit=GetTime()-1
    bag.components.combat:GetAttacked(a,10)
    assert(bag._nw_combo.total==10,"NW_BAG: one-second gap")
    local armour=SpawnPrefab("armorwood");bag.components.inventory:Equip(armour)
    bag.components.combat:GetAttacked(a,100)
    assert(math.abs(bag._nw_combo.total-30)<.01,"NW_BAG: native armour mitigation")
    bag.components.inventory:Unequip(EQUIPSLOTS.BODY):Remove()
    bag.components.combat:GetAttacked(a,10000)
    assert(bag._nw_combo.total==10030 and bag._nw_combo_text:value()=="10030","NW_BAG: full overflow number")
    local saved=bag:GetSaveRecord();bag:Remove();bag=assert(SpawnSaveRecord(saved))
    assert(bag._nw_combo.total==10030 and not bag._nw_combo.last_hit,"NW_BAG: saved display, fresh combo")
    bag.components.combat:GetAttacked(a,7)
    assert(bag._nw_combo.total==7,"NW_BAG: first hit after reload")
    assert(require("nw/targeting").allowed(a,bag,{targets={hostile=true}}),"NW_BAG: hostile homing target")
    local Bonus=require("nw/first_boss_reward")
    assert(a.components.nw_firstboss and b.components.nw_firstboss)
    local players=AllPlayers;AllPlayers={a,b}
    local boss=SpawnPrefab("deerclops");boss.Transform:SetPosition(0,0,0)
    boss.components.combat:SetTarget(nil)
    local receipt={}
    boss:ListenForEvent("loot_prefab_spawned",function(_,data)
        if data.loot.prefab=="nw_spellcard" then receipt[#receipt+1]=data.loot end
    end)
    local rewards=require("nw/rewards");local old=rewards.cardmult;rewards.cardmult=0
    boss.components.health:Kill()
    assert(#receipt==2,"NW_BONUS: two nearby first victories")
    for _,card in ipairs(receipt) do assert(card.source=="first_boss:deerclops");assert(card.spell_id=="imprint_hit" or card.spell_id:match("_hit$"));card:Remove() end
    assert(a.components.nw_firstboss.claimed and b.components.nw_firstboss.claimed)
    TheWorld:PushEvent("entity_death",{inst=boss});assert(#receipt==2,"NW_BONUS: duplicate death")
    local reroll=a:SaveForReroll();assert(reroll.nw_firstboss.claimed)
    a.components.nw_firstboss.claimed=false;a:LoadForReroll(reroll);assert(a.components.nw_firstboss.claimed)
    local component=a.components.nw_firstboss
    local state=component:OnSave();component.claimed=false;component:OnLoad(state);assert(component.claimed)
    rewards.cardmult=old;AllPlayers=players
    a:Remove();b:Remove();bag:Remove();boss:Remove()
    print("NW_BAG_BONUS_PASS: native factory, hit/armour/regen, 1-second combos, overflow/save, visual APIs, two-player bonus, duplicates and persisted/rerolled receipt")
end
return M
