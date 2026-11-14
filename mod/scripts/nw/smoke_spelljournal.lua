local M={}
function M.run()
    local C=require("nw/compiler")
    local F=require("nw/wand_factory")
    local Hooks=require("nw/spelljournal")
    local Damage=require("nw/journal_damage")
    local made={}
    local x,z=0,0
    for _,e in pairs(Ents) do if e:HasTag("multiplayer_portal") then x,_,z=e.Transform:GetWorldPosition();break end end
    local function spawn(id,dx,dz)
        local e=assert(SpawnPrefab(id));e.Transform:SetPosition(x+(dx or 0),0,z+(dz or 0))
        made[#made+1]=e;return e
    end
    local player=spawn("wilson")
    player.components.health:SetInvincible(true);player.entity:SetCanSleep(false)
    local inv=player.components.inventory
    local journal=assert(player.components.nw_spelljournal)
    local card=spawn("nw_spellcard");card:SetSpell("arrow");inv:GiveItem(card)
    assert(journal:GetCard("arrow").collected,"NW_JOURNAL: inventory pickup")
    local bag=spawn("backpack");inv:Equip(bag)
    local frost=spawn("nw_spellcard");frost:SetSpell("frost");bag.components.container:GiveItem(frost)
    assert(journal:GetCard("frost").collected,"NW_JOURNAL: backpack pickup")
    local dropped=inv:Unequip(EQUIPSLOTS.BODY);inv:DropItem(dropped,true,true)
    local fire=spawn("nw_spellcard");fire:SetSpell("fire");bag.components.container:GiveItem(fire)
    assert(not journal:GetCard("fire").collected,"NW_JOURNAL: ground bag is not owned")
    inv:Equip(bag)
    assert(journal:GetCard("fire").collected,"NW_JOURNAL: prefilled bag")
    local wand=spawn("nw_wand");local cmp=wand.components.nw_wand
    cmp:InitializePrototype()
    cmp.data.stats.capacity=12;cmp.data.stats.mana_max=1200;cmp.data.stats.spread=0
    cmp.data.cards={F.card("pierce_all","journal"),F.card("spark_hit","journal"),F.card("damage_up","journal"),F.card("arrow","journal")}
    cmp.data.runtime=C.initial(cmp.data.cards,cmp.data.stats,1)
    cmp.data.config_revision=cmp.data.config_revision+1;cmp:Sync()
    inv:Equip(wand)
    assert(journal:GetCard("spark_hit").collected,"NW_JOURNAL: cards within acquired wand")
    local preview=assert(cmp:PreviewCast())
    assert(journal.casts==0,"NW_JOURNAL: preview counted")
    local payload_damage=preview.blocks[2].projectiles[1].damage
    spawn("nw_target_dummy",3,0);spawn("nw_target_dummy",6,0)
    assert(not cmp:Cast(player,Vector3(x,0,z)) and journal.casts==0,"NW_JOURNAL: invalid cast counted")
    assert(cmp:Cast(player,Vector3(x+8,0,z)) and journal.casts==1,"NW_JOURNAL: accepted cast")
    assert(journal:GetCard("arrow").casts==1 and journal:GetCard("damage_up").casts==1,"NW_JOURNAL: payload/modifier usage")
    local target=spawn("nw_spell_punchingbag",0,4)
    local before=journal.damage
    require("nw/spell_effects").direct(player,target,{id="spark",damage=10,flags={}},1,0)
    assert(math.abs(journal.damage-before-10)<.01,"NW_JOURNAL: direct damage")
    local armour=spawn("armorwood");target.components.inventory:Equip(armour)
    before=journal.damage
    require("nw/spell_effects").direct(player,target,{id="spark",damage=100,flags={}},1,0)
    assert(math.abs(journal.damage-before-20)<.01,"NW_JOURNAL: armour mitigation")
    target.components.inventory:Unequip(EQUIPSLOTS.BODY):Remove()
    local weapon=spawn("spear_wathgrithr");Damage.tag(weapon,player,{id="edge_spear_wathgrithr"})
    before=journal.damage
    player.components.combat.ignorehitrange=true
    player.components.combat:DoAttack(target,weapon,nil,nil,nil,10)
    player.components.combat.ignorehitrange=false
    assert(journal.damage>before and journal:GetCard("edge_spear_wathgrithr").damage>0,"NW_JOURNAL: native DoAttack adapter")
    local blasttarget=spawn("nw_target_dummy",0,4)
    local bomb=spawn("nw_gunpowder",0,4)
    bomb:Launch(player,{id="gunpowder",flags={},spread=0},x,z+4,1,0,function() end)
    bomb.components.explosive:OnBurnt(blasttarget)
    assert((journal:GetCard("gunpowder").damage or 0)>0,"NW_JOURNAL: native explosion")
    wand.components.named:SetName("收藏的星火")
    wand:AddTag("nw_customname");Hooks.renamed(wand,player)
    assert(journal:GetTopWands("mana_max")[1].name=="收藏的星火","NW_JOURNAL: renamed snapshot")
    local save=journal:OnSave()
    journal:OnLoad(save)
    assert(journal:GetCard("arrow").casts==1 and journal:GetTopWands("mana_max")[1].name=="收藏的星火")
    local reroll=player:SaveForReroll()
    assert(reroll.nw_spelljournal.casts==1,"NW_JOURNAL: reroll save")
    local copy=spawn("wilson");copy:LoadForReroll(reroll)
    assert(copy.components.nw_spelljournal:GetCard("arrow").casts==1,"NW_JOURNAL: reroll load")
    local restored=SpawnSaveRecord(player:GetSaveRecord());made[#made+1]=restored
    assert(restored.components.nw_spelljournal:GetCard("arrow").casts==1,"NW_JOURNAL: native save/load")
    TheWorld:DoTaskInTime(1,function()
        assert(journal:GetCard("arrow").casts==1,"NW_JOURNAL: projectile/payload replay counted again")
        assert((journal:GetCard("arrow").damage or 0)>=2*payload_damage-.01,
            "NW_JOURNAL: piercing payload must deal damage more than once")
        assert(not journal:GetCard("damage_up").damage,"NW_JOURNAL: modifier owns damage")
        local record=journal:GetDamageRecord()
        assert(record.at and record.at.unix>0 and record.at.world_day>=1 and record.wand.wand_uid==cmp.data.wand_uid,
            "NW_JOURNAL: timestamp and held wand")
        local other=spawn("nw_wand");other.components.nw_wand:InitializePrototype()
        other.components.named:SetName("达成时的新法杖");inv:Equip(other)
        local score=journal:GetDamageRecord(10).damage+journal.max_hit+1
        local durable=spawn("nw_target_dummy",0,7);durable.components.health:SetMaxHealth(score*10)
        require("nw/spell_effects").direct(player,durable,{id="spark",damage=score,flags={}},1,0)
        for _,seconds in ipairs({0,1,5,10}) do
            local best=journal:GetDamageRecord(seconds~=0 and seconds or nil)
            assert(best.wand and best.wand.wand_uid==other.components.nw_wand.data.wand_uid and best.at.unix>0,
                "NW_JOURNAL: achievement must use equipped B")
        end
        other.components.named:SetName("之后改名");Hooks.renamed(other,player)
        assert(journal:GetDamageRecord().wand.name=="达成时的新法杖","NW_JOURNAL: historical name changed")
        inv:Unequip(EQUIPSLOTS.HANDS)
        local snapshot=journal:OnSave()
        journal:OnLoad(snapshot)
        score=journal:GetDamageRecord(10).damage+journal.max_hit+1
        durable.components.health:SetMaxHealth(score*10)
        require("nw/spell_effects").direct(player,durable,{id="spark",damage=score,flags={}},1,0)
        for _,seconds in ipairs({0,1,5,10}) do
            local best=journal:GetDamageRecord(seconds~=0 and seconds or nil)
            assert(best.wand==nil and best.at.unix>0,"NW_JOURNAL: unequipped wand was retained")
        end
        local state=journal:OnSave();journal:OnLoad(state)
        assert(journal:GetDamageRecord().at.unix==state.max_hit_record.at.unix and not journal:GetDamageRecord().wand)
        local rerolled=spawn("wilson");rerolled:LoadForReroll(player:SaveForReroll())
        assert(rerolled.components.nw_spelljournal:GetDamageRecord(5).at.unix==state.best_damage_records[5].at.unix)
        for _,e in ipairs(made) do if e:IsValid() then e:Remove() end end
        print("NW_JOURNAL_PASS: collection, piercing dedup, damage, achievement time/equipped snapshots, swap/unequip, save and reroll")
    end)
end
return M
