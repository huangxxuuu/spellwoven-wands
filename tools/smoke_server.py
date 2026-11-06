"""Isolated offline server smoke test. Never reads/writes the user's clusters."""
import argparse
import re
import shutil
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--server", type=Path, default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
parser.add_argument("--seconds", type=int, default=50)
parser.add_argument("--pvp",action="store_true",help="use a separate PvP-enabled test world")
parser.add_argument("--bounds",action="store_true",help="isolated boundary suite with a separate test mod installation")
parser.add_argument("--cleanup",action="store_true",help="isolated native sleep and permanent motion cleanup suite")
parser.add_argument("--scenes",action="store_true",help="isolated naming, inspection and test scene supply suite")
parser.add_argument("--bag-bonus",action="store_true",help="native spell punching bag and first-boss bonus suite")
parser.add_argument("--fresh",action="store_true",help="create a new isolated world without overwriting prior test saves")
parser.add_argument("--revision",action="store_true",help="isolated spell revision integration suite")
parser.add_argument("--wands",action="store_true",help="native crafted wand generation, replication and save/load suite")
args = parser.parse_args()
if sum((args.bounds,args.cleanup,args.pvp,args.scenes,args.bag_bonus,args.revision,args.wands))>1:
    parser.error("--bounds, --cleanup, --scenes, --bag-bonus and --pvp are separate suites")

# LAN servers reject ports outside this engine-defined range and silently
# fall back to 10999, which may belong to the user's running world.
def available_lan_port():
    for candidate in range(11018,10997,-1):
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as probe:
            if hasattr(socket,"SO_EXCLUSIVEADDRUSE"):
                probe.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
            try:
                probe.bind(("0.0.0.0",candidate))
            except OSError:
                continue
            return candidate
    raise SystemExit("No free DST LAN test port (10998-11018); existing servers left untouched")

lan_port=available_lan_port()
print("Isolated LAN test port:",lan_port,flush=True)
test_mod = "nw_weave_wands_test" if args.wands else "nw_weave_revision_test" if args.revision else "nw_weave_bag_bonus_test" if args.bag_bonus else "nw_weave_scenes_test" if args.scenes else "nw_weave_cleanup_test" if args.cleanup else "nw_weave_bounds_test" if args.bounds else "nw_weave_dev"
target = args.server / "mods" / test_mod
marker = target / ".nw_workspace"
if target.exists() and (not marker.exists() or marker.read_text() != str(ROOT)):
    raise SystemExit(f"Refusing to overwrite unowned directory: {target}")
shutil.copytree(ROOT / "mod", target, dirs_exist_ok=True)
# Retired custom cast-input module, only inside our ownership-checked install.
obsolete=target / "scripts/nw/network.lua"
if obsolete.exists():
    obsolete.unlink()
marker.write_text(str(ROOT))
storage = ROOT / "test_worlds"
version = (args.server / "version.txt").read_text().strip()
mod_version=re.search(r'^version = "([^"]+)"',(ROOT/"mod/modinfo.lua").read_text("utf8"),re.M).group(1)
conf_dir = "nw_smoke_" + version + "_" + mod_version + ("_wands" if args.wands else "_revision" if args.revision else "_bag_bonus" if args.bag_bonus else "_scenes" if args.scenes else "_cleanup" if args.cleanup else "_bounds" if args.bounds else "_pvp" if args.pvp else "")
if args.fresh:
    conf_dir += "_run_" + str(time.time_ns())
cluster = storage / conf_dir / "Cluster_1"
master = cluster / "Master"
master.mkdir(parents=True, exist_ok=True)
(cluster / "cluster.ini").write_text(f"[GAMEPLAY]\ngame_mode = survival\nmax_players = 2\npvp = {str(args.pvp).lower()}\npause_when_empty = false\n\n[NETWORK]\ncluster_name = NW Isolated Offline Smoke\nlan_only_cluster = true\noffline_cluster = true\n\n[SHARD]\nshard_enabled = false\n", encoding="utf-8")
(master / "server.ini").write_text(f"[NETWORK]\nserver_port = {lan_port}\n\n[STEAM]\nmaster_server_port = 27997\nauthentication_port = 8797\n", encoding="utf-8")
smoke_mode = '"wands"' if args.wands else '"revision"' if args.revision else '"bag_bonus"' if args.bag_bonus else '"scenes"' if args.scenes else '"cleanup"' if args.cleanup else '"bounds"' if args.bounds else 'true'
smoke_options = ', permanent_motion_cleanup = true' if args.cleanup else ', boundary_cleanup = true' if args.bounds else ''
(master / "modoverrides.lua").write_text('return { ["' + test_mod + '"] = { enabled = true, configuration_options = { development_smoke = ' + smoke_mode + smoke_options + ' } } }\n', encoding="utf-8")
report = ROOT / "test_reports" / ("server_smoke_wands.log" if args.wands else "server_smoke_revision.log" if args.revision else "server_smoke_bag_bonus.log" if args.bag_bonus else "server_smoke_scenes.log" if args.scenes else "server_smoke_cleanup.log" if args.cleanup else "server_smoke_bounds.log" if args.bounds else "server_smoke_pvp.log" if args.pvp else "server_smoke.log")
report.parent.mkdir(exist_ok=True)
# The cooperative run covers the full suite; the second world verifies PvP specifically.
pass_marker="NW_WAND_GENERATION_PASS:" if args.wands else "NW_REVISION_PASS:" if args.revision else "NW_BAG_BONUS_PASS:" if args.bag_bonus else "NW_SCENES_PASS:" if args.scenes else "NW_CLEANUP_PASS:" if args.cleanup else "NW_BOUNDS_PASS:" if args.bounds else "NW_SCOPE_PASS:" if args.pvp else "NW_SMOKE_PASS:"
command = [str(args.server / "bin64/dontstarve_dedicated_server_nullrenderer_x64.exe"),
           "-persistent_storage_root", str(storage), "-conf_dir", conf_dir, "-cluster", "Cluster_1",
           "-shard", "Master", "-offline", "-console"]
with report.open("wb") as stream:
    process = subprocess.Popen(command, cwd=args.server / "bin64", stdout=stream, stderr=subprocess.STDOUT,
                               stdin=subprocess.PIPE, creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        deadline = time.monotonic() + args.seconds
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(.5)
            progress=report.read_text(encoding="utf-8", errors="replace")
            if any(marker in progress for marker in (pass_marker,"LUA ERROR","Server failed to start!")):
                break
        if process.poll() is None:
            try:
                process.stdin.write(b"c_shutdown(false)\n")
                process.stdin.flush()
                process.wait(timeout=5)
            except (subprocess.TimeoutExpired, BrokenPipeError, OSError):
                process.terminate()
                process.wait(timeout=5)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
text = report.read_text(encoding="utf-8", errors="replace")
passed = pass_marker in text and "LUA ERROR" not in text
if args.pvp: passed = passed and any("NW_SCOPE_PASS:" in line and "true" in line for line in text.splitlines())
print("PASS" if passed else "NOT PASSED", report)
print(text[-6500:])
raise SystemExit(0 if passed else 1)
