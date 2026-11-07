"""Sync the workspace mod to its owned local DST installation and verify every file."""
import argparse
import csv
import hashlib
import io
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from animation_atlas import validate_animation_archive

ROOT = Path(__file__).resolve().parents[1]
GAME_PROCESSES = {
    'dontstarve_steam.exe', 'dontstarve_steam_x64.exe',
    'dontstarve_dedicated_server_nullrenderer.exe',
    'dontstarve_dedicated_server_nullrenderer_x64.exe',
}


def running_game_processes():
    """Report live DST clients/servers without starting or stopping anything."""
    if os.name != 'nt':
        return []
    result = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True,
                            text=True, encoding='utf8', errors='replace', check=True)
    found = []
    for row in csv.reader(io.StringIO(result.stdout)):
        if len(row) >= 2 and row[0].lower() in GAME_PROCESSES:
            found.append(f'{row[0]} (PID {row[1]})')
    return found


def digest(path):
    return hashlib.sha256(path.read_bytes()).digest()


def copy_atomic(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix='.nw_install_', dir=destination.parent, delete=False) as temp:
        temporary = Path(temp.name)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def install(game):
    game = Path(game)
    target = game.resolve() / 'mods' / 'nw_weave_dev'
    marker = target / '.nw_workspace'
    if not game.is_dir():
        raise SystemExit(f'Game directory not found: {game}')
    if target.exists() and (not marker.is_file() or marker.read_text() != str(ROOT)):
        raise SystemExit(f'Refusing to overwrite an installation not owned by this workspace: {target}')
    source = ROOT / 'mod'
    # Validate the complete source before touching the owned installation.
    for archive in sorted((source / 'anim').glob('*.zip')):
        validate_animation_archive(archive)
    files = sorted(p for p in source.rglob('*') if p.is_file())
    fingerprints = {path: digest(path) for path in files}
    changed = [path for path in files if not (target / path.relative_to(source)).is_file()
               or fingerprints[path] != digest(target / path.relative_to(source))]
    obsolete = target / 'scripts/nw/network.lua'
    remove_obsolete = obsolete.is_file() and not (source / 'scripts/nw/network.lua').exists()
    if changed or remove_obsolete:
        active = running_game_processes()
        if active:
            raise SystemExit('Main mod installation deferred: DST is still running: '
                             + ', '.join(active) + '. Close the game and its local servers, then rerun this installer. '
                             'Replacing loaded animation archives can crash the texture loader; no installed files were changed.')
    # Never truncate a loaded archive, and do not rewrite identical resources.
    # Atomic copies also keep interrupted offline installs from leaving half a zip.
    for path in changed:
        copy_atomic(path, target / path.relative_to(source))
    target.mkdir(parents=True, exist_ok=True)
    marker.write_text(str(ROOT))
    if remove_obsolete:
        obsolete.unlink()
    for path in files:
        installed = target / path.relative_to(source)
        if fingerprints[path] != digest(installed):
            raise SystemExit(f'Installed file verification failed: {installed}')
    version = re.search(r'^version\s*=\s*"([^"]+)"', (target / 'modinfo.lua').read_text(encoding='utf8'), re.M)[1]
    print(f'PASS: installed {version}; verified {len(files)} files; updated {len(changed)} files; {target}')
    print('Restart the game and world to load updated Lua, assets and mod configuration options.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
    install(parser.parse_args().game)


if __name__ == '__main__':
    main()
