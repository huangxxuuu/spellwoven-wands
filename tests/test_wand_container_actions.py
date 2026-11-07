"""Check wand interaction flags against the installed DST action collectors."""
import os
from pathlib import Path
import unittest
import zipfile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class NativeContainerActionsTest(unittest.TestCase):
    def test_automatic_container_has_no_rummage_action(self):
        archive = GAME / "data/databundles/scripts.zip"
        if not archive.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = str(ROOT / "mod/scripts/?.lua").replace("\\", "/") + ";" + lua.globals().package.path
        lua.execute('''
package.loaded.util=true
package.loaded.vecutil=true
orderedPairs=pairs
EntityScript={}
ACTIONS={RUMMAGE={},EQUIP={},UNEQUIP={}}
EQUIPSLOTS={HANDS="hands"}
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
TheNet={IsDedicated=function() return true end}
TheWorld={ismastersim=true}
GetTableSize=function(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local netvars={}
net_bool=function(guid,name)
    local key=guid..name
    netvars[key]=netvars[key] or {v=false,
        set=function(self,v) self.v=v end,value=function(self) return self.v end}
    return netvars[key]
end
local containers={params={},MAXITEMSLOTS=0}
function containers.widgetsetup(c,p)
    local params=containers.params[p or c.inst.prefab]
    for k,v in pairs(params) do c[k]=v end
    c:SetNumSlots(#params.widget.slotpos)
end
package.loaded.containers=containers
package.loaded["nw/editing"]={near=function() return true end}
SpawnPrefab=function(name)
    assert(name=="container_classified")
    return {entity={SetParent=function() end},
        Network={SetClassifiedTarget=function() end},InitializeSlots=function() end}
end
''')
        with zipfile.ZipFile(archive) as z:
            lua.execute(z.read("scripts/class.lua").decode())
            lua.globals().NativeContainer = lua.execute(z.read("scripts/components/container.lua").decode())
            lua.globals().NativeContainerReplica = lua.execute(z.read("scripts/components/container_replica.lua").decode())
            lua.execute(z.read("scripts/componentactions.lua").decode())
        lua.execute('''
local M=require("nw/wand_container")
M.install({})
local function entity(guid,prefab)
    local inst=setmetatable({GUID=guid,prefab=prefab,entity={},components={},replica={},
        actioncomponents={},events={},tags={}}, {__index=EntityScript})
    function inst:ListenForEvent(event,fn)
        self.events[event]=self.events[event] or {}
        table.insert(self.events[event],fn)
    end
    function inst:PushEvent(event,data)
        for _,fn in ipairs(self.events[event] or {}) do fn(self,data) end
    end
    function inst:HasTag(tag) return self.tags[tag] or false end
    function inst:DoPeriodicTask(_,fn) self.tick=fn end
    function inst:StartUpdatingComponent() end
    function inst:StopUpdatingComponent() end
    function inst:SpawnChild(name)
        assert(name=="container_opener")
        return {Network={SetClassifiedTarget=function() end},Remove=function() end}
    end
    function inst:AddComponent(name)
        assert(name=="container")
        self.replica.container=NativeContainerReplica(self)
        self.components.container=NativeContainer(self)
        self:RegisterComponentActions(name)
    end
    return inst
end

local wand=entity(1,"nw_wand")
local equipped=wand
local inv={opencontainers={},GetEquippedItem=function() return equipped end,
    GetActiveItem=function() return nil end}
local owner={components={inventory=inv,health={IsDead=function() return false end}},
    replica={inventory=inv},PushEvent=function() end}
wand.components.inventoryitem={owner=owner}
wand.components.nw_wand={data={config_revision=1}}
wand.replica.equippable={IsEquipped=function() return equipped==wand end,
    ShouldPreventUnequipping=function() return false end,IsRestricted=function() return false end,
    EquipSlot=function() return EQUIPSLOTS.HANDS end}
wand:RegisterComponentActions("equippable")
M.setup(wand)
local c=wand.components.container
assert(c.canbeopened==false and not wand.replica.container:CanBeOpened(),
    "the native property setter must disable manual opening on the replica")

-- Keep a real slot occupied while opening/closing, without rebuilding its data.
local card={components={},replica={inventoryitem={SetOwner=function() end}}}
c.slots[1]=card
c._nw_data=wand.components.nw_wand.data
c._nw_revision=1
wand.tick()
assert(c:IsOpenedBy(owner) and inv.opencontainers[wand],
    "automatic editor opening must not depend on canbeopened")
local function actions(inst,kind)
    local result={}
    inst:CollectActions(kind,owner,result,true)
    return result
end
local function only_action(inst,expected)
    local result=actions(inst,"INVENTORY")
    assert(#result==1 and result[1]==expected)
end
only_action(wand,ACTIONS.UNEQUIP)
assert(#actions(wand,"SCENE")==0)

-- A separate remote replica consumes the same server-owned network flag.
TheWorld.ismastersim=false
local remote=entity(1,"nw_wand")
remote.replica.container=NativeContainerReplica(remote)
remote.replica.equippable=wand.replica.equippable
remote:RegisterComponentActions("container")
remote:RegisterComponentActions("equippable")
assert(not remote.replica.container:CanBeOpened())
only_action(remote,ACTIONS.UNEQUIP)
assert(#actions(remote,"SCENE")==0)
TheWorld.ismastersim=true

-- Unequipping closes the editor without clearing installed cards; reequipping
-- reopens it. A dropped wand has neither the inventory nor scene open action.
equipped=nil
wand:PushEvent("unequipped")
wand.tick()
assert(not c:IsOpenedBy(owner) and not inv.opencontainers[wand] and c.slots[1]==card)
only_action(wand,ACTIONS.EQUIP)
only_action(remote,ACTIONS.EQUIP)
wand.components.inventoryitem.owner=nil
wand.tick()
assert(#actions(wand,"SCENE")==0 and c.slots[1]==card)
wand.components.inventoryitem.owner=owner
equipped=wand
wand.tick()
assert(c:IsOpenedBy(owner) and c.slots[1]==card)
only_action(wand,ACTIONS.UNEQUIP)

-- Ordinary bags still receive the native open/close action in both contexts.
package.loaded.containers.params.backpack={type="pack",widget={slotpos={}}}
local bag=entity(2,"backpack")
bag:AddComponent("container")
bag.components.container:WidgetSetup("backpack")
assert(bag.replica.container:CanBeOpened())
only_action(bag,ACTIONS.RUMMAGE)
assert(actions(bag,"SCENE")[1]==ACTIONS.RUMMAGE)
bag.components.container:Open(owner)
assert(bag.components.container:IsOpenedBy(owner) and c:IsOpenedBy(owner))
only_action(bag,ACTIONS.RUMMAGE)
only_action(wand,ACTIONS.UNEQUIP)
bag.components.container:Close(owner)
assert(c:IsOpenedBy(owner) and c.slots[1]==card)
''')


if __name__ == "__main__":
    unittest.main()
