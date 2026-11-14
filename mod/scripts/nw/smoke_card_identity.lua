local M={}
function M.run(x,z)
    local made={}
    local function spawn(prefab)
        local e=assert(SpawnPrefab(prefab));e.Transform:SetPosition(x,0,z)
        made[#made+1]=e;return e
    end
    local function restore(record)
        local e=assert(SpawnSaveRecord(record));made[#made+1]=e;return e
    end
    local stack=spawn("nw_spellcard");stack:SetSpell("frost");stack.components.stackable:SetStackSize(4)
    local split=stack.components.stackable:Get(2);made[#made+1]=split
    local one=split.components.stackable:Get(1);made[#made+1]=one
    assert(stack.card_uid~=split.card_uid and one.card_uid~=split.card_uid and one.card_uid~=stack.card_uid,
        "NW_IDENTITY: splitting reused an ID")
    assert(stack.components.stackable:Put(split)==nil and stack.components.stackable:Put(one)==nil)
    assert(stack.components.stackable:StackSize()==4 and not one:IsValid() and not split:IsValid(),
        "NW_IDENTITY: merge lost or duplicated cards")
    local counter=TheWorld.components.nw_identity.sequence
    local saved=stack:GetSaveRecord()
    assert(TheWorld.components.nw_identity.sequence==counter,"NW_IDENTITY: save allocated an ID")
    local uid=stack.card_uid;stack:Remove();stack=restore(saved)
    assert(stack.card_uid==uid and stack.components.stackable:StackSize()==4,"NW_IDENTITY: stack restore")
    saved.data.card_uid=""
    local legacy=restore(saved)
    assert(legacy.card_uid and legacy.card_uid~="" and legacy.spell_id=="frost","NW_IDENTITY: empty card ID restore")
    saved.data.card_uid="nw:foreign-session:2:77"
    local foreign=restore(saved)
    assert(foreign.card_uid==saved.data.card_uid,"NW_IDENTITY: shard-origin ID was lost")

    local player=spawn("wilson");local inv=player.components.inventory
    spawn("nw_workbench")
    local wand=spawn("nw_wand");local cmp=wand.components.nw_wand
    cmp:InitializePrototype();cmp.data.cards={false,false,false,false}
    cmp.data.runtime=require("nw/compiler").initial(cmp.data.cards,cmp.data.stats,1)
    inv:GiveItem(wand);inv:Equip(wand)
    local first=spawn("nw_spellcard");first:SetSpell("spark")
    local second=restore(first:GetSaveRecord());second:SetSpell("orbit")
    assert(first.card_uid==second.card_uid,"NW_IDENTITY: collision fixture")
    inv:GiveItem(first);inv:GiveItem(second)
    local E=require("nw/editing")
    assert(E.commit(player,wand,1,first,cmp.data.config_revision,false))
    assert(E.commit(player,wand,2,second,cmp.data.config_revision,false))
    local data=cmp.data
    assert(data.cards[1].card_uid~=data.cards[2].card_uid,"NW_IDENTITY: conflicting insertion")
    uid=data.cards[2].card_uid
    assert(E.commit(player,wand,2,nil,data.config_revision,true))
    local cursor=inv:GetActiveItem()
    assert(cursor and cursor.card_uid==uid,"NW_IDENTITY: removal lost identity")
    assert(E.commit(player,wand,3,cursor,data.config_revision,true))
    assert(not inv:GetActiveItem() and data.cards[3].card_uid==uid,"NW_IDENTITY: slot move lost identity")
    saved=wand:GetSaveRecord();saved.data.nw_wand.wand.cards[3].card_uid=nil
    local mana=data.runtime.mana;wand:Remove();wand=restore(saved)
    data=wand.components.nw_wand.data
    assert(data.cards[1].spell_id=="spark" and data.cards[3].spell_id=="orbit" and not data.cards[2],
        "NW_IDENTITY: missing ID discarded slots")
    assert(data.runtime.mana==mana and require("nw/compiler").compile(data),"NW_IDENTITY: missing ID failed to recover")
    for i=#made,1,-1 do if made[i]:IsValid() then made[i]:Remove() end end
    print("NW_IDENTITY_PASS: native stack split/merge/save, missing IDs, foreign origin, conflicting insertion and slot move")
end
return M
