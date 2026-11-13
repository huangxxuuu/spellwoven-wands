"""Run the current creature-control and Boss regressions against scripts.zip.

This replaces the retired Charlie/grue test. Successful reports describe Lua
source execution, not a live renderer or multiplayer session.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, default=Path(
        "E:/SteamLibrary/steamapps/common/Don't Starve Together"))
    args = parser.parse_args()
    checks = ("check_dark_fog_control_native.py", "check_dark_fog_boss_native.py",
              "check_dark_fog_boss_extra_native.py")
    for name in checks:
        subprocess.run([sys.executable, str(ROOT / "tools" / name),
                        "--game", str(args.game)], cwd=ROOT, check=True)
    report = {
        "passed": True,
        "native_archive": str(args.game / "data/databundles/scripts.zip"),
        "checks": list(checks),
        "runtime": "Lua 5.1",
        "coverage": "creature perception/hostility and native Boss attack timing/damage parity",
        "not_verified": "live engine physics, renderer and multiplayer replication",
    }
    dest = ROOT / "test_reports/dark_fog_native_lua.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
