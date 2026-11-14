local M={}
function M.run(player,wand)
    local E=require("nw/editing")
    local inv=player.components.inventory
    local cmp=wand.components.nw_wand
    local x,y,z=player.Transform:GetWorldPosition()
    local bench=SpawnPrefab("nw_workbench");bench.Transform:SetPosition(x-2,y,z)
    local cards={}
    for i=1,inv.maxslots do
        local card=SpawnPrefab("nw_spellcard");card:SetSpell("heavy")
        assert(inv:GiveItem(card,i));cards[i]=card
    end
    cmp.data.runtime.mana=37
    cmp.data.runtime.remaining_cast=3
    cmp.data.runtime.remaining_recharge=3.5
    cmp.last_time=GetTime()
    local rev=cmp.data.config_revision
    local Protocol=require("nw/edit_protocol")
    local handler=GetModRPCHandler("nw_weave","edit")
    local networkid,near=Protocol.focus(player)
    assert(networkid==wand.Network:GetNetworkID() and networkid>0 and near,"NW_EDIT: status request failed")
    assert(handler(player,1,Protocol.id(cards[1]),rev,networkid,1),"NW_EDIT: RPC full bag swap failed")
    assert(not cards[1]:IsValid(),"NW_EDIT: input card still exists")
    local returned=inv:GetItemInSlot(1)
    assert(returned.spell_id=="double" and cmp.data.cards[1].spell_id=="heavy","NW_EDIT: wrong cards")
    local ok,err=E.commit(player,wand,1,returned,rev)
    assert(not ok and err=="STALE_REVISION","NW_EDIT: duplicate request accepted")
    assert(cmp.data.runtime.mana==37 and cmp.data.runtime.remaining_recharge==3.5,"NW_EDIT: state reset")
    ok,err=E.commit(player,wand,1,nil,rev+1)
    assert(not ok and err=="INVENTORY_FULL","NW_EDIT: full bag removal accepted")
    inv:RemoveItem(cards[2],true);cards[2]:Remove()
    assert(E.commit(player,wand,1,nil,rev+1),"NW_EDIT: remove failed")
    assert(cmp.data.cards[1]==false and inv:GetItemInSlot(2).spell_id=="heavy")
    assert(E.commit(player,wand,4,returned,rev+2),"NW_EDIT: empty slot install failed")
    assert(cmp.data.cards[4].spell_id=="double" and not returned:IsValid())
    local saved=wand:GetSaveRecord()
    local clone=SpawnSaveRecord(saved)
    local restored=clone.components.nw_wand.data
    assert(restored.runtime.mana==37 and restored.runtime.remaining_recharge==3.5,"NW_EDIT: cooldown save failed")
    assert(restored.cards[1]==false and restored.cards[4].spell_id=="double","NW_EDIT: slots save failed")
    assert(clone._nw_cards:value()==wand._nw_cards:value() and clone._nw_revision:value()==rev+3,"NW_EDIT: replica slots failed")
    local stats=require("nw/hover_data").decode(clone._nw_stats:value())
    assert(stats.mana_max==120 and stats.sanity_conversion==20,"NW_EDIT: hover stats missing")
    local slots=require("nw/cards").decode(clone._nw_cards:value())
    assert(not slots[1] and slots[4]=="double","NW_EDIT: slot row save mismatch")
    assert(clone._nw_cooldown:value()==350,"NW_EDIT: cooldown replica failed")
    local savedcard=inv:GetItemInSlot(2):GetSaveRecord()
    assert(savedcard.data.spell_id=="heavy","NW_EDIT: prefab save callback lost spell id")
    local legacy=require("nw/util").copy(savedcard)
    legacy.data.spell_id="target_players_all"
    local converted=SpawnSaveRecord(legacy)
    assert(converted.spell_id=="target_players_other" and converted:GetCardUID()==legacy.data.card_uid)
    converted:Remove()
    local clonecard=SpawnSaveRecord(savedcard)
    assert(clonecard.spell_id=="heavy" and clonecard._spell:value()==require("nw/cards").codes.heavy)
    player._nw_nextedit=0
    inv:GiveActiveItem(clonecard)
    local ok=handler(player,4,Protocol.id(clonecard),cmp.data.config_revision,networkid,2,true)
    assert(ok and cmp.data.cards[4].spell_id=="heavy" and inv:GetActiveItem().spell_id=="double","NW_EDIT: cursor swap")
    local cursor=inv:GetActiveItem()
    player._nw_nextedit=0
    assert(handler(player,1,Protocol.id(cursor),cmp.data.config_revision,networkid,3,true))
    assert(cmp.data.cards[1].spell_id=="double" and not inv:GetActiveItem(),"NW_EDIT: cursor move")
    player._nw_nextedit=0
    assert(handler(player,1,0,cmp.data.config_revision,networkid,4,true))
    assert(inv:GetActiveItem().spell_id=="double" and not cmp.data.cards[1],"NW_EDIT: cursor extraction")
    inv:RemoveItem(inv:GetActiveItem(),true):Remove()
    local stack=SpawnPrefab("nw_spellcard");stack:SetSpell("frost")
    stack.components.stackable:SetStackSize(39)
    local extra=SpawnPrefab("nw_spellcard");extra:SetSpell("frost")
    assert(stack.components.stackable:Put(extra)==nil and stack.components.stackable:StackSize()==40)
    local saved=SpawnSaveRecord(stack:GetSaveRecord());stack:Remove()
    local split=saved.components.stackable:Get(2)
    assert(split.spell_id=="frost" and split.components.stackable:StackSize()==2)
    local unlike=SpawnPrefab("nw_spellcard");unlike:SetSpell("arrow")
    assert(not split.components.stackable:CanStackWith(unlike))
    unlike:Remove();saved:Remove()
    inv:GiveActiveItem(split)
    assert(E.commit(player,wand,1,split,cmp.data.config_revision,true))
    assert(inv:GetActiveItem()==split and split.components.stackable:StackSize()==1 and cmp.data.cards[1].spell_id=="frost")
    inv:RemoveItem(split,true):Remove()
    print("NW_CARD_STACK_PASS: 40, save/split identity, mismatched cards, single-slot installation")
    clone:Remove();bench:Remove()
    print("NW_EDIT_PASS: full bag swap + remove/install + stale rejection + slot/card/mana/cooldown restore + net fields")
end
return M
