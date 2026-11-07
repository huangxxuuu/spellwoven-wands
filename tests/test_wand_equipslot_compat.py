"""Check the installed extra-equipment-slots mod's real assignment/overflow hooks."""
import os
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


WORKSHOP = Path(os.environ.get(
    "DST_EQUIPSLOT_MOD",
    "E:/SteamLibrary/steamapps/workshop/content/322330/3173431824",
))


class WandEquipSlotCompatibilityTest(unittest.TestCase):
    def test_real_extra_slot_assignment_and_overflow(self):
        assign = WORKSHOP / "scripts/assign.lua"
        compat = WORKSHOP / "scripts/compat.lua"
        if not assign.exists() or not compat.exists():
            self.skipTest("Set DST_EQUIPSLOT_MOD to the installed 3173431824 mod")
        for slots in (4, 5, 6):
            for server in (True, False):
                with self.subTest(slots=slots, server=server):
                    lua = LuaRuntime(unpack_returned_tuples=True)
                    lua.globals().slot_count = slots
                    lua.globals().server = server
                    lua.execute('''
GLOBAL=_G
EQUIPSLOTS={HANDS="hands",HEAD="head",BODY="body",BACK="back"}
if slot_count>=5 then EQUIPSLOTS.NECK="neck" end
if slot_count>=6 then EQUIPSLOTS.BELLY="belly" end
TheWorld={ismastersim=true}
local config={IsServer=true}
local body={BODY_LAYER_LIST={},BODY_LAYER_DEFS={NECK={},BELLY={}},
    ApplyBodyLayerCallbacks=function(inst) inst.body_wrapped=true end}
local back={ApplyBackCallbacks=function(inst) inst.back_wrapped=true end}
local modules={modconfig=config,bodylayers=body,backslot=back,
    slots={EQUIPSLOTS_MAP={}}}
modrequire=function(name) return assert(modules[name],name) end
package.loaded.symbol_back={};package.loaded.yongbutuoxie={}
prefab_hooks={};component_hooks={}
AddPrefabPostInit=function(name,fn) prefab_hooks[name]=fn end
AddPrefabPostInitAny=function(fn) assign_hook=fn end
AddComponentPostInit=function(name,fn) component_hooks[name]=fn end
set_server=function(value) config.IsServer=value;TheWorld.ismastersim=value end

-- Public wand identity: explicit HANDS, no backpack tag, editor-only container.
-- The native-container tests separately exercise the production setup/replication.
local function item(prefab,slot,canopen)
    local inst={prefab=prefab,components={equippable={equipslot=slot}},replica={}}
    function inst:HasTag() return false end
    local container={inst=inst,canbeopened=canopen,opened=true}
    function container:CanBeOpened() return self.canbeopened end
    function container:IsOpenedBy() return self.opened end
    inst.components.container=container;inst.replica.container=container
    return inst
end
wand=item("nw_wand",EQUIPSLOTS.HANDS,false)
bag=item("backpack",EQUIPSLOTS.BODY,true)
''')
                    assignment = lua.execute(assign.read_text(encoding="utf-8-sig"))
                    assignment.InitPrefab()
                    lua.execute('''
assign_hook(wand);assign_hook(bag)
assert(wand.components.equippable.equipslot==EQUIPSLOTS.HANDS)
assert(not wand.back_wrapped and not wand.body_wrapped,
    "the wand must not get backpack/body callbacks")
assert(bag.components.equippable.equipslot==EQUIPSLOTS.BACK and bag.back_wrapped,
    "real backpacks must still be assigned to the extra back slot")
set_server(server)
''')
                    lua.globals().compat_module = lua.execute(
                        compat.read_text(encoding="utf-8-sig")
                    )
                    lua.execute('''
local repairs
for i=1,20 do
    local name,value=debug.getupvalue(compat_module.Run,i)
    if name=="compat_functions" then repairs=value;break end
end
assert(repairs,"expected the installed compatibility module's repair table")
repairs.RepairInventoryClassified()
local equipped={[EQUIPSLOTS.HANDS]=wand}
local inventory={inst={},GetEquippedItem=function(_,slot) return equipped[slot] end}
if server then
    component_hooks.inventory(inventory)
else
    inventory._parent={}
    prefab_hooks.inventory_classified(inventory)
end
assert(inventory:GetOverflowContainer()==nil,"a held wand is not a backpack")
equipped[EQUIPSLOTS.BACK]=bag
assert(inventory:GetOverflowContainer()==bag.components.container,
    "the real backpack must remain the overflow container")
bag.components.container.opened=false
assert(inventory:GetOverflowContainer()==bag.components.container,
    "the closed real backpack must remain eligible")
inventory.ignoreoverflow=true
assert(inventory:GetOverflowContainer()==nil)
''')


if __name__ == "__main__":
    unittest.main()
