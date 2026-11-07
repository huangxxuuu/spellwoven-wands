-- Run only in the isolated smoke world, with the native picker and container.
local M={}
function M.run(x,z,done)
    local player=SpawnPrefab("wilson")
    player.Transform:SetPosition(x,0,z)
    local inv=player.components.inventory
    local function card(spell)
        local item=SpawnPrefab("nw_spellcard")
        item:SetSpell(spell);item.source="pile_smoke"
        return item
    end
    local axe=card("whirl")
    assert(axe.AnimState:IsCurrentAnimation(require("nw/ground_card").pose(require("nw/cards").codes.whirl,1)),"NW_PILE: wrong single-card clip")
    axe:Remove()
    local floor=card("fire")
    floor.Transform:SetPosition(x+1,0,z)
    local frost=card("frost");inv:GiveActiveItem(frost)
    local uid=floor:GetCardUID()
    local actions={}
    frost:CollectActions("USEITEM",player,floor,actions,true)
    assert(table.contains(actions,ACTIONS.NW_PILE),"NW_PILE: combine not offered")
    local act=BufferedAction(player,floor,ACTIONS.NW_PILE,frost)
    assert(act:Do(),"NW_PILE: create failed")
    assert(not act:Do(),"NW_PILE: repeated request")
    local pile=floor.components.inventoryitem.owner
    local box=pile.components.container
    assert(pile.prefab=="nw_spellpile" and box:GetItemInSlot(1)==floor and box:GetItemInSlot(2)==frost)
    assert(box:GetNumSlots()==25 and pile:HasTag("fireimmune") and not pile.components.burnable)
    local torch=SpawnPrefab("torch")
    torch.components.lighter:Light(pile,player)
    torch:Remove()
    assert(pile:IsValid() and not pile:HasTag("fire") and box:NumItems()==2)
    local nine_slot_record
    for i=3,25 do
        local item=card(i==25 and "note_c" or i%2==0 and "spark" or "arrow")
        inv:GiveActiveItem(item)
        assert(BufferedAction(player,pile,ACTIONS.NW_PILE,item):Do())
        if i==9 then nine_slot_record=pile:GetSaveRecord() end
    end
    local extra=card("heavy");inv:GiveActiveItem(extra)
    assert(not BufferedAction(player,pile,ACTIONS.NW_PILE,extra):Do() and inv:GetActiveItem()==extra)
    inv:RemoveItem(extra,true):Remove()
    local log=SpawnPrefab("log");assert(not box:GiveItem(log,nil,nil,false));log:Remove()
    TheWorld:DoTaskInTime(2*FRAMES,function()
        assert(math.floor(pile._surface:value()/require("nw/cardpile").stride)==25)
        assert(pile._surface:value()%require("nw/cardpile").stride==require("nw/cards").codes.fire)
        local old=SpawnSaveRecord(nine_slot_record)
        local oldbox=old.components.container
        assert(oldbox:GetNumSlots()==25 and oldbox:NumItems()==9 and oldbox:GetItemInSlot(1):GetCardUID()==uid)
        assert(oldbox:GiveItem(card("chain"),25,nil,false) and oldbox:GetItemInSlot(25).spell_id=="chain")
        oldbox:RemoveItemBySlot(1):Remove()
        TheWorld:DoTaskInTime(2*FRAMES,function()
            local nextcode=require("nw/cards").codes.frost
            assert(old._surface:value()%require("nw/cardpile").stride==nextcode)
            local pose=require("nw/ground_card").pose(nextcode,oldbox:NumItems(),old._layers:value(),old._separated:value())
            assert(old.AnimState:IsCurrentAnimation(pose),"NW_PILE: top face did not change")
            old:Remove()
        end)
        local copy=SpawnSaveRecord(pile:GetSaveRecord())
        for i=25,1,-1 do box:RemoveItemBySlot(i):Remove() end
        pile:Remove()
        local restored=copy.components.container
        local last=restored:GetItemInSlot(1)
        assert(restored:NumItems()==25 and last.spell_id=="fire" and last:GetCardUID()==uid and last.source=="pile_smoke")
        restored:Open(player)
        assert(restored:IsOpenedBy(player))
        for i=25,2,-1 do
            local item=restored:GetItemInSlot(i)
            restored:TakeActiveItemFromAllOfSlot(i,player)
            assert(inv:GetActiveItem()==item)
            inv:PutAllOfActiveItemInSlot(1)
            assert(inv:GetItemInSlot(1)==item)
            inv:RemoveItem(item,true):Remove()
        end
        TheWorld:DoTaskInTime(.3,function()
            assert(not copy:IsValid(),"NW_PILE: did not collapse")
            assert(last:IsValid(),"NW_PILE: last card destroyed")
            assert(not last:IsInLimbo() and not last.components.inventoryitem.owner,"NW_PILE: last card still held")
            last:Remove();player:Remove()
            print("NW_PILE_PASS: 25 slots, rejects card 26, torch immunity, nine-card save, full save/load and final card")
            done()
        end)
    end)
end
return M
