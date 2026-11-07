"""Exercise the bridge against installed DST container.lua, not a copied model."""
import os
from pathlib import Path
import unittest
import zipfile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class NativeContainerTest(unittest.TestCase):
    def test_native_transfers_and_persistence(self):
        archive = GAME / "data/databundles/scripts.zip"
        if not archive.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = str(ROOT / "mod/scripts/?.lua").replace("\\", "/") + ";" + lua.globals().package.path
        lua.execute('''
Class=function(ctor)
    local c={};c.__index=c
    return setmetatable(c,{__call=function(_,...) local s=setmetatable({},c);ctor(s,...);return s end})
end
makereadonly=function() end;removesetter=function() end
GetGameModeProperty=function() return false end
GetTableSize=function(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
EQUIPSLOTS={HANDS="hands"}
TheNet={IsDedicated=function() return true end}
TheWorld={components={nw_identity={Observe=function() end}}}
local containers={params={},MAXITEMSLOTS=0}
function containers.widgetsetup(c,p)
    for k,v in pairs(containers.params[p]) do c[k]=v end
    c:SetNumSlots(#c.widget.slotpos)
end
package.loaded.containers=containers
''')
        with zipfile.ZipFile(archive) as z:
            lua.globals().NativeContainer = lua.execute(z.read("scripts/components/container.lua").decode())
        lua.execute('''
local M=require("nw/wand_container")
M.install({})
local Cards=require("nw/cards")
local near=true
package.loaded["nw/editing"]={near=function() return near end}
local seq=0
SpawnPrefab=function()
    seq=seq+1
    local item={components={},card_uid="card:"..seq}
    function item:HasTag(tag) return tag=="nw_spellcard" end
    function item:SetSpell(id) self.spell_id=id end
    function item:GetCardUID() return self.card_uid end
    function item:Remove() self.removed=true end
    item._spell={value=function() return Cards.codes[item.spell_id] end}
    item.components.inventoryitem={cangoincontainer=true,
        OnPutInInventory=function(self,owner) self.owner=owner end,
        OnRemoved=function(self) self.owner=nil end}
    return item
end
local callbacks={}
local inst={components={},replica={container={WidgetSetup=function() end,
    AddOpener=function() end,RemoveOpener=function() end}},
    _nw_capacity={value=function() return 2 end}}
function inst:ListenForEvent(event,fn) callbacks[event]=callbacks[event] or {};table.insert(callbacks[event],fn) end
function inst:PushEvent(event,data) for _,fn in ipairs(callbacks[event] or {}) do fn(self,data) end end
function inst:AddComponent() self.components.container=NativeContainer(self) end
function inst:DoPeriodicTask(_,fn) self.tick=fn end
function inst:StartUpdatingComponent() end
function inst:StopUpdatingComponent() end
local active
local inv={opencontainers={},GetEquippedItem=function() return inst end,
    GetActiveItem=function() return active end,
    GiveActiveItem=function(_,item) active=item end,
    RemoveItem=function(_,item) assert(active==item);active=nil;return item end}
local dead=false
local owner={components={inventory=inv,health={IsDead=function() return dead end}},PushEvent=function() end}
inst.components.inventoryitem={owner=owner}
local d=require("nw/generator").starter()
d.stats.capacity=2;d.cards={{spell_id="spark",card_uid="old:1",source="legacy"},false}
d.runtime=require("nw/compiler").initial(d.cards,d.stats,1)
d.runtime.mana=17;d.runtime.remaining_cast=2;d.config_revision=1
local w={data=d,UpdateTime=function() end,Sync=function() M.sync(inst) end}
inst.components.nw_wand=w
M.setup(inst);M.sync(inst)
local c=inst.components.container
assert(c.canbeopened==false,"spell slots must not offer RUMMAGE or backpack overflow")
local original=c:GetItemInSlot(1)
assert(original.card_uid=="old:1" and original.source=="legacy")
assert(c:OnSave()==nil and c.excludefromcrafting)
M.sync(inst);assert(c:GetItemInSlot(1)==original,"sync must retain entities")
inst.tick();assert(c:IsOpenedBy(owner) and inv.opencontainers[inst])
c:TakeActiveItemFromAllOfSlot(1,owner)
assert(active==original and d.cards[1]==false and not original.removed)
c:PutAllOfActiveItemInSlot(2,owner)
assert(active==nil and c:GetItemInSlot(2)==original and d.cards[2].card_uid=="old:1")
active=SpawnPrefab();active:SetSpell("arrow")
local arrow=active
c:SwapActiveItemWithSlot(2,owner)
assert(active==original and c:GetItemInSlot(2)==arrow and d.cards[2].spell_id=="arrow")
c:PutAllOfActiveItemInSlot(1,owner)
local extra=SpawnPrefab();extra:SetSpell("frost")
assert(not c:GiveItem(extra,nil,nil,false) and c:GetItemInSlot(3)==nil,"full capacity must not spill into hidden slots")
assert(not c:GiveItem(extra,1,nil,false) and c:GetItemInSlot(3)==nil)
assert(not c:CanTakeItemInSlot(extra,3))
assert(d.runtime.mana==17 and d.runtime.remaining_cast==2)
assert(d.runtime.remaining_recharge>=d.stats.recharge)
near=false
c:TakeActiveItemFromAllOfSlot(1,owner)
assert(active==nil and c:GetItemInSlot(1)==original)
assert(c:RemoveItemBySlot(1)==nil,"drop must recheck range")
assert(not c:GiveItem(extra,1,nil,false))
inst.tick();assert(not c:IsOpenedBy(owner))
near=true;dead=true;inst.tick();assert(not c:IsOpenedBy(owner))
dead=false;inst.tick();assert(c:IsOpenedBy(owner))
-- Native move to a full destination restores the same entity.
local dest={components={container={IsOpenedBy=function() return true end,
    CanTakeItemInSlot=function() return true end,GiveItem=function() return false end}}}
c:MoveItemFromAllOfSlot(1,dest,owner)
assert(c:GetItemInSlot(1)==original and d.cards[1].card_uid=="old:1")
local received
dest.components.container.GiveItem=function(_,item) received=item;return true end
c:MoveItemFromAllOfSlot(1,dest,owner)
assert(received==original and d.cards[1]==false and c:GetItemInSlot(1)==nil)
-- Reload projects only the saved spell records, preserving IDs and holes.
local saved=require("nw/util").copy(d)
w.data=saved;M.sync(inst)
assert(c:GetItemInSlot(1)==nil and c:GetItemInSlot(2).card_uid==arrow.card_uid)
inst:PushEvent("onremove")
assert(c:GetItemInSlot(2).removed)
''')


if __name__ == "__main__":
    unittest.main()
