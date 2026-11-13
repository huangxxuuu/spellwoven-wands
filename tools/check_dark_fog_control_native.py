"""Offline control regression against authoritative DST combat/retarget source.

This exercises real Lua functions with simulated entity/terrain services. It is
not a running-game physics, stategraph-animation or multiplayer acceptance test.
"""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, default=Path(
        "E:/SteamLibrary/steamapps/common/Don't Starve Together"))
    args = parser.parse_args()
    with zipfile.ZipFile(args.game / "data/databundles/scripts.zip") as bundle:
        sources = {name: bundle.read("scripts/" + name).decode("utf8") for name in (
            "components/combat.lua", "prefabs/hound.lua", "prefabs/pigman.lua")}
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
    vm.execute('''
        -- Class construction/property replication aren't needed: fixtures supply
        -- component data; every combat method below comes from the game bundle.
        function Class() return {} end
        package.preload["util/sourcemodifierlist"] = function() return {} end
        package.preload["components/spdamageutil"] = function() return {} end
    ''')
    vm.globals().NativeCombat = vm.execute(sources["components/combat.lua"])
    vm.execute((ROOT / "tests/test_dark_fog_control.lua").read_text(encoding="utf8"))

    hound = sources["prefabs/hound.lua"]
    hound = hound[hound.index('local RETARGET_CANT_TAGS ='):hound.index('local function KeepTarget(')]
    pig = sources["prefabs/pigman.lua"]
    pig = pig[pig.index('local function NormalRetargetFn('):pig.index('local function NormalKeepTargetFn(')]
    vm.globals().NativeHoundRetarget = vm.execute(hound + "\nreturn retargetfn")
    vm.globals().NativePigRetarget = vm.execute('local RETARGET_MUST_TAGS = { "_combat" }\n' + pig + "\nreturn NormalRetargetFn")
    vm.execute('''
        TUNING = { HOUND_TARGET_DIST=20, HOUND_FOLLOWER_TARGET_DIST=20,
            HOUND_FOLLOWER_AGGRO_DIST=20, PIG_TARGET_DIST=16 }
        function IsFranken(guy) return guy.franken end
        local candidates = {}
        function FindEntity(inst, radius, predicate, must, cant, oneof)
            for _, candidate in ipairs(candidates) do
                local matches = inst:IsNear(candidate, radius)
                for _, tag in ipairs(must or {}) do matches = matches and candidate:HasTag(tag) end
                for _, tag in ipairs(cant or {}) do matches = matches and not candidate:HasTag(tag) end
                if oneof then
                    local any = false
                    for _, tag in ipairs(oneof) do any = any or candidate:HasTag(tag) end
                    matches = matches and any
                end
                if matches and (not predicate or predicate(candidate, inst)) then return candidate end
            end
        end
        local fixture = DarkFogNativeFixtures
        local create, tick = fixture.entity, fixture.tick
        local Control = require("nw/dark_fog_control")
        local hunter, far, close = create("hound"), create("player",12), create("player",2)
        far.tags.player = true; close.tags.player = true
        hunter.components.combat.targetfn = NativeHoundRetarget
        candidates = {far, close}
        assert(NativeHoundRetarget(hunter) == far)
        tick(hunter, 100); tick(hunter, 100.1)
        assert(hunter.components.combat.target == close)
        -- Original follower exclusion survives the near-range filter.
        Control.leave(hunter)
        hunter.components.combat:SetTarget(nil)
        hunter.components.follower = { GetLeader=function() return close end }
        candidates = {close}; tick(hunter, 101); tick(hunter, 101.1)
        assert(hunter.components.combat.target == nil)
        Control.leave(hunter)

        local pig, neutral, monster = create("pigman"), create("pigman",1), create("spider",2)
        monster.tags.monster = true
        pig.components.follower = { GetLeader=function() return nil end }
        pig.components.combat.targetfn = NativePigRetarget
        candidates = {neutral}; tick(pig, 110); tick(pig, 110.1)
        assert(pig.components.combat.target == nil, "CanTarget does not create pig hostility")
        far.tags.monster = true
        candidates = {far, neutral, monster}; tick(pig, 110.4)
        assert(pig.components.combat.target == monster)
        Control.leave(pig)
        -- Native follower exclusion for Abigail, plus minigame player exclusion.
        pig.components.combat:SetTarget(nil)
        pig.components.follower.GetLeader = function() return close end
        monster.tags.abigail = true; candidates = {monster}
        tick(pig, 111); tick(pig, 111.1); assert(pig.components.combat.target == nil)
        Control.leave(pig)
        monster.tags.abigail = nil; monster.tags.player = true
        pig.components.minigame_spectator = {}
        tick(pig, 112); tick(pig, 112.1); assert(pig.components.combat.target == nil)
        Control.leave(pig)
        print("native fog control: actual Combat, hound follower and pig hostility selection passed")
    ''')
    report = {
        "status": "passed",
        "scope": "offline Lua 5.1, native combat methods and hound/pig retarget functions",
        "live_game_verified": False,
        "native_sha256": {name: hashlib.sha256(source.encode()).hexdigest() for name, source in sources.items()},
    }
    output = ROOT / "test_reports/dark_fog_control_native.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    print(output)


if __name__ == "__main__":
    main()
