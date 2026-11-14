local M={}
function M.run(x,z)
    local made={}
    local function spawn(id)
        local e=assert(SpawnPrefab(id));e.Transform:SetPosition(x,0,z);made[#made+1]=e;return e
    end
    local player=spawn("wilson");local inv=player.components.inventory
    spawn("nw_workbench")
    local wand=spawn("nw_wand");local cmp=wand.components.nw_wand
    cmp:InitializePrototype();inv:Equip(wand)
    local E=require("nw/editing")
    local function load(id)
        local d=cmp.data;d.cards={require("nw/wand_factory").card(id,"debug"),false,false,false}
        d.runtime=require("nw/compiler").initial(d.cards,d.stats,1)
        d.config_revision=d.config_revision+1;cmp:Sync()
        return d.cards[1]
    end
    local function shift() return E.commit(player,wand,1,nil,cmp.data.config_revision,false) end
    local function card(id,count)
        local e=spawn("nw_spellcard");e:SetSpell(id);e.components.stackable:SetStackSize(count);return e
    end
    local main=card("spark",39);inv:GiveItem(main,1)
    for i=2,inv.maxslots do
        local e=spawn("rocks");e.components.stackable:SetStackSize(e.components.stackable.maxsize);inv:GiveItem(e,i)
    end
    assert(inv:IsFull())
    load("spark");assert(shift() and main.components.stackable:StackSize()==40 and not cmp.data.cards[1],
        "NW_TRANSFER: full main inventory must merge a matching card")
    local bag=spawn("backpack");inv:Equip(bag);local box=bag.components.container
    local original=load("spark")
    assert(shift() and box:GetItemInSlot(1).card_uid==original.card_uid,"NW_TRANSFER: empty backpack space was ignored")
    local bagstack=box:GetItemInSlot(1);made[#made+1]=bagstack
    bagstack.components.stackable:SetStackSize(39)
    for i=2,box:GetNumSlots() do
        local e=spawn("rocks");e.components.stackable:SetStackSize(e.components.stackable.maxsize);box:GiveItem(e,i)
    end
    load("spark");assert(shift() and bagstack.components.stackable:StackSize()==40,"NW_TRANSFER: full backpack must merge")
    original=load("spark");local revision=cmp.data.config_revision
    local previous=inv.ignorefull
    local ok,why=shift()
    assert(not ok and why=="INVENTORY_FULL" and cmp.data.cards[1]==original and cmp.data.config_revision==revision,
        "NW_TRANSFER: full destination lost source card")
    assert(not inv:GetActiveItem() and inv.ignorefull==previous,"NW_TRANSFER: failed shift changed cursor/flags")

    bagstack:SetSpell("frost");bagstack.components.stackable:SetStackSize(39)
    load("frost");local input=card("fire",2);inv:GiveActiveItem(input)
    assert(E.commit(player,wand,1,input,cmp.data.config_revision,true),"NW_TRANSFER: stacked cursor replacement failed")
    assert(cmp.data.cards[1].spell_id=="fire" and inv:GetActiveItem()==input and input.components.stackable:StackSize()==1
        and bagstack.components.stackable:StackSize()==40,"NW_TRANSFER: replacement split/merge lost cards")
    input.components.stackable:SetStackSize(2);original=load("frost");revision=cmp.data.config_revision
    ok,why=E.commit(player,wand,1,input,revision,true)
    assert(not ok and why=="INVENTORY_FULL" and cmp.data.cards[1]==original
        and inv:GetActiveItem()==input and input.components.stackable:StackSize()==2,"NW_TRANSFER: full replacement rollback")
    for i=#made,1,-1 do if made[i]:IsValid() then made[i]:Remove() end end
    print("NW_TRANSFER_PASS: main/backpack merge, backpack slot, full rejection, cursor stack replacement and rollback")
end
return M
