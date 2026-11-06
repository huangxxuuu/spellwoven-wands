"""Sync the workspace mod to its owned local DST installation and verify every file."""
import argparse
import hashlib
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game', type=Path, default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
args = parser.parse_args()
target = args.game.resolve() / 'mods' / 'nw_weave_dev'
marker = target / '.nw_workspace'
if not args.game.is_dir():
    raise SystemExit(f'Game directory not found: {args.game}')
if target.exists() and (not marker.is_file() or marker.read_text() != str(ROOT)):
    raise SystemExit(f'Refusing to overwrite an installation not owned by this workspace: {target}')
source = ROOT / 'mod'
shutil.copytree(source, target, dirs_exist_ok=True)
marker.write_text(str(ROOT))
# This retired input module must not remain in the development installation.
obsolete = target / 'scripts/nw/network.lua'
if obsolete.is_file() and not (source / 'scripts/nw/network.lua').exists():
    obsolete.unlink()
files = [p for p in source.rglob('*') if p.is_file()]
for path in files:
    installed = target / path.relative_to(source)
    if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(installed.read_bytes()).digest():
        raise SystemExit(f'Installed file verification failed: {installed}')
version = re.search(r'^version\s*=\s*"([^"]+)"', (target / 'modinfo.lua').read_text(encoding='utf8'), re.M)[1]
print(f'PASS: installed {version}; verified {len(files)} files; {target}')
print('Restart the game and world to load updated Lua, assets and mod configuration options.')
