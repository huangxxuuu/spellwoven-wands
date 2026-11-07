local Cards=require("nw/cards")
local C=require("nw/compiler")
local G=require("nw/generator")
local E=require("nw/editing")
EQUIPSLOTS={HANDS="hands"}
local close=true
TheSim={FindEntities=function() return close and {true} or {} end}
local created={}
local function card(id)
    local obj={spell_id=id,valid=true}
    function obj:HasTag(tag) return tag=="nw_spellcard" end
    function obj:SetSpell(value) self.spell_id=value end
    function obj:GetCardUID() return self.card_uid or "test:"..tostring(self) end
    function obj:Remove() self.valid=false end
    created[#created+1]=obj
    return obj
end
SpawnPrefab=function() return card("spark") end
local data=G.starter()
data.stats.capacity=4
data.cards={{card_uid="a",spell_id="spark"},false,false,false}
data.config_revision=1;data.runtime=C.initial(data.cards,data.stats,1)
data.runtime.mana=41;data.runtime.remaining_cast=2
local cmp={data=data,UpdateTime=function() end,Sync=function() end}
local wand={components={nw_wand=cmp}}
local slots={}
local inv={maxslots=2,GetEquippedItem=function() return wand end}
function inv:GetItemSlot(item) for i,v in pairs(slots) do if v==item then return i end end end
function inv:GetItemInSlot(i) return slots[i] end
function inv:RemoveItem(item) local i=self:GetItemSlot(item);if i then slots[i]=nil;return item end end
function inv:GiveItem(item,i)
    if not i then for k=1,self.maxslots do if not slots[k] then i=k;break end end end
    if not i or slots[i] then return false end
    slots[i]=item;return true
end
local player={components={inventory=inv,health={IsDead=function() return false end}},Transform={GetWorldPosition=function() return 0,0,0 end}}
local function reject(reason,slot,source,revision)
    local oldrev=data.config_revision;local oldmana=data.runtime.mana
    local ok,err=E.commit(player,wand,slot,source,revision)
    assert(not ok and err==reason,reason.." got "..tostring(err))
    assert(data.config_revision==oldrev and data.runtime.mana==oldmana)
end
local arrow=card("arrow");slots[1]=arrow;slots[2]=card("heavy")
close=false;reject("OUT_OF_RANGE",1,arrow,1);close=true
reject("INVALID_SLOT",0,arrow,1);reject("INVALID_SLOT",0/0,arrow,1)
reject("CARD_MISSING",1,card("arrow"),1)
reject("INVENTORY_FULL",1,nil,1)
assert(E.commit(player,wand,1,arrow,1)) -- Full inventory swap uses the consumed card's slot.
assert(not arrow.valid and slots[1].spell_id=="spark" and data.cards[1].spell_id=="arrow")
assert(data.config_revision==2 and data.runtime.mana==41 and data.runtime.remaining_cast==2)
assert(data.runtime.remaining_recharge>=data.stats.recharge)
reject("STALE_REVISION",1,slots[1],1)
assert(E.commit(player,wand,3,slots[2],2))
assert(slots[2]==nil and data.cards[2]==false and data.cards[3].spell_id=="heavy")
assert(E.commit(player,wand,1,nil,3))
assert(data.cards[1]==false and slots[2].spell_id=="arrow")
local encoded=Cards.encode(data.cards,4)
local decoded=Cards.decode(encoded)
assert(#decoded==4 and decoded[1]==false and decoded[2]==false and decoded[3]=="heavy" and decoded[4]==false)
assert(E.commit(player,wand,4,nil,4) and data.config_revision==4) -- Empty removal is a no-op.
cmp._editlock=true;reject("BUSY",3,slots[1],4);cmp._editlock=nil
inv.GetEquippedItem=function() return nil end
reject("NOT_OWNER",3,nil,4)
inv.GetEquippedItem=function() return wand end
local before=data.cards[3]
local original=inv.GiveItem
inv.GiveItem=function(self,item,i) if item.spell_id=="heavy" then return false end;return original(self,item,i) end
reject("INVENTORY_FULL",3,slots[1],4)
assert(data.cards[3]==before and slots[1].spell_id=="spark" and slots[1].valid)
assert(not created[#created].valid and not cmp._editlock)
local active=card("frost")
function inv:GetActiveItem() return active end
function inv:GiveActiveItem(item) assert(not active);active=item end
local remove=inv.RemoveItem
function inv:RemoveItem(item)
    if active==item then active=nil;return item end
    return remove(self,item)
end
close=false
local ok,err=E.commit(player,wand,3,active,4,true)
assert(not ok and err=="OUT_OF_RANGE" and active.spell_id=="frost" and data.cards[3]==before)
close=true
ok,err=E.commit(player,wand,3,nil,4,true)
assert(not ok and err=="CARD_MISSING" and data.cards[3]==before)
assert(E.commit(player,wand,3,active,4,true))
assert(data.cards[3].spell_id=="frost" and active.spell_id=="heavy" and active.card_uid==before.card_uid)
assert(E.commit(player,wand,4,active,5,true))
assert(not active and data.cards[4].spell_id=="heavy")
assert(E.commit(player,wand,4,nil,6,true) and active.card_uid==before.card_uid)
print("editing: slot codec, full-bag swap, install/remove, ownership/range, stale revision, rollback, no mana/cooldown reset")
