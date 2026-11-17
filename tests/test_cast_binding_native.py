"""Exercise binding persistence through installed DST save/migration methods."""
import os
from pathlib import Path
import re
import unittest
import zipfile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))
SCRIPTS = GAME / "data/databundles/scripts.zip"


def function(source, signature):
    start = source.index(signature)
    following = re.search(r"\n(?:function |local function |return )", source[start + 1:])
    chunk = source[start:] if following is None else source[start:start + 1 + following.start()]
    return chunk[:chunk.rindex("\nend") + len("\nend")]


@unittest.skipUnless(SCRIPTS.is_file(), "requires local DST scripts (or DST_GAME)")
class NativeCastBindingTests(unittest.TestCase):
    def setUp(self):
        self.vm = LuaRuntime(unpack_returned_tuples=True)
        vm = self.vm
        vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
        with zipfile.ZipFile(SCRIPTS) as archive:
            def source(name):
                return archive.read("scripts/" + name + ".lua").decode().replace("\r", "")

            vm.execute(source("class"))
            vm.execute("EntityScript={}")
            for name in ("GetSaveRecord", "GetPersistData", "SetPersistData"):
                vm.execute(function(source("entityscript"), f"function EntityScript:{name}("))
            vm.execute(function(source("networking"), "function SerializeUserSession("))
            vm.execute(function(source("components/playerspawner"), "local function PlayerRemove(")
                       + "\nNativePlayerRemove=PlayerRemove")
            for name in ("SaveForReroll", "LoadForReroll"):
                vm.execute(function(source("prefabs/player_common"), f"local function {name}(")
                           + f"\nNative{name}={name}")
        vm.execute(r'''
IsTableEmpty=function(t) return next(t)==nil end
isbadnumber=function(n) return n~=n or n==math.huge or n==-math.huge end
BRANCH="release"
TheWorld={ismastersim=true,ismastershard=true,meta={session_identifier="save-A"}}
TheNet={GetIsServer=function() return true end}
-- Keep the serialized record instead of emulating the engine's disk/network codec.
DataDumper=function(value) return value end
function TheNet:SerializeUserSession(userid,data,newspawn)
    serialized={userid=userid,data=data,newspawn=newspawn}
end
TheShard={GetShardId=function() return "1" end,
    StartMigration=function(_,userid,world) migration={userid=userid,world=world} end}
local G={TheWorld=TheWorld,TheShard=TheShard}
local post
require("nw/cast_binding").install({GetModConfigData=function() return "mouse:1002" end,
    AddSimPostInit=function() end,AddShardModRPCHandler=function() end,
    AddModRPCHandler=function() end,AddClientModRPCHandler=function() end,
    AddPlayerPostInit=function(fn) post=fn end},G)
local seq=0
function make_player()
    seq=seq+1
    local p=setmetatable({GUID=seq,prefab="wortox",userid="user",components={inventory={ForEachItem=function() end}},
        Transform={GetWorldPosition=function() return 1,0,2 end},
        entity={HasTag=function(_,tag) return tag=="player" end},Network={GetPlayerAge=function() return 4 end},
        SaveForReroll=NativeSaveForReroll,LoadForReroll=NativeLoadForReroll}, {__index=EntityScript})
    function p:GetCurrentPlatform() end
    function p:IsValid() return not self.removed end
    function p:PushEvent() end
    function p:ListenForEvent() end
    function p:DoTaskInTime() return {Cancel=function() end} end
    function p:AddComponent(name) self.components[name]=require("components/"..name)(self) end
    function p:OnDespawn(data) self.despawned=data end
    function p:Remove() self.removed=true end
    post(p)
    return p
end
''')

    def test_native_save_and_migration_carry_component_before_removal(self):
        self.vm.execute(r'''
local source=make_player()
source.components.nw_castbinding:Initialize("mouse:1002")
assert(source.components.nw_castbinding:Set("mouse:1005",0))
NativePlayerRemove(source,false,{player=source,worldid="2",portalid=7},true)
assert(source.removed and source.despawned and migration.world=="2")
assert(serialized.userid=="user" and not serialized.newspawn)
local saved=serialized.data.data.nw_castbinding
assert(saved.default=="mouse:1002" and saved.override=="mouse:1005" and saved.revision==1)
assert(saved.token==nil,"entity lifecycle tokens must not survive migration")
local restored=make_player()
restored:SetPersistData(serialized.data.data,{})
assert(restored.components.nw_castbinding:Get()=="mouse:1005")
assert(restored.components.nw_castbinding.token~=source.components.nw_castbinding.token)
assert(not restored.components.nw_castbinding:Initialize("mouse:1001"))
assert(restored.components.nw_castbinding.default=="mouse:1002")
''')

    def test_native_reroll_whitelist_wrapped_without_losing_preferences(self):
        self.vm.execute(r'''
local source=make_player()
source.components.nw_castbinding:Initialize("mouse:1002")
assert(source.components.nw_castbinding:Set("key:107",0))
local saved=source:SaveForReroll()
assert(saved.nw_castbinding.override=="key:107")
local target=make_player()
target:LoadForReroll(saved)
assert(target.components.nw_castbinding:Get()=="key:107")
assert(target.components.nw_castbinding.default=="mouse:1002")
''')


if __name__ == "__main__":
    unittest.main()
