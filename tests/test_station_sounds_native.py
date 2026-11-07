"""Exercise station transitions through DST's actual crafting indicator callback."""
import os
from pathlib import Path
import unittest
import zipfile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(os.environ.get("DST_GAME", "E:/SteamLibrary/steamapps/common/Don't Starve Together"))


class StationSoundsTest(unittest.TestCase):
    def test_station_transitions_are_silent(self):
        archive = GAME / "data/databundles/scripts.zip"
        if not archive.exists():
            self.skipTest("Set DST_GAME to an installed DST directory")
        with zipfile.ZipFile(archive) as z:
            source = z.read("scripts/widgets/redux/craftingmenu_pinbar.lua").decode()
        start = source.index("self.open_menu_button.SetCraftingState = function")
        end = source.index("self.open_menu_button.OnControl = function", start)
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + lua.globals().package.path
        lua.execute('''
sounds={}
TheFocalPoint={SoundEmitter={PlaySound=function(_,sound) sounds[#sounds+1]=sound end}}
animate_glow=function() end
local icon={Show=function(self) self.shown=true end,Hide=function(self) self.shown=false end}
self={open_menu_button={prototype=icon},owner={replica={builder={
    GetCurrentPrototyper=function() return station end}}}}
''')
        lua.execute(source[start:end])
        lua.execute('''
require("nw/station_sounds").install(self)
local button=self.open_menu_button
local bench={prefab="nw_workbench"}
local engraver={prefab="nw_engraver"}
local science={prefab="researchlab"}
local function update(source,prototype,recipes,expected)
    station=source
    local before=#sounds
    button:SetCraftingState(prototype,recipes)
    assert(#sounds-before==expected,"unexpected transition sound")
    assert(button.can_prototype==prototype)
    assert(button.prototype.shown==prototype,"research icon must remain correct")
end
update(nil,false,false,0)
-- Empty hands: this hook is independent of wand ownership or equipment.
update(bench,true,true,0)
update(nil,false,true,0)
update(bench,false,true,0)
update(nil,false,true,0)
update(engraver,true,true,0)
update(nil,false,true,0)
update(engraver,false,true,0)
update(nil,false,true,0)
-- Switching between the two mod stations is silent in both directions.
update(bench,true,true,0)
update(engraver,false,true,0)
update(bench,true,true,0)
update(nil,false,false,0)
-- Ordinary research stations and later ingredient pickups retain their sounds.
update(science,true,true,1)
assert(sounds[#sounds]=="dontstarve/HUD/research_available")
update(science,true,true,1)
assert(sounds[#sounds]=="dontstarve/HUD/recipe_ready")
update(bench,true,true,0)
update(bench,true,true,1)
update(science,true,true,0)
update(nil,false,false,0)
update(nil,false,true,1)
update(engraver,true,true,0)
update(engraver,true,true,1)
update(science,true,true,0)
update(science,true,true,1)
''')


if __name__ == "__main__":
    unittest.main()
