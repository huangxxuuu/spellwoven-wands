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
from pathlib import Path, PureWindowsPath
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


def retired_assets(target, source):
    """Exact retired names only; never delete unrelated locally installed files."""
    names = ['scripts/nw/network.lua', 'scripts/nw/projectile_height.lua',
             'scripts/nw/height_motion.lua', 'scripts/nw/smoke_height.lua']
    names += [f'anim/nw_ground_cards_{i}.zip' for i in range(2)]
    names += [f'images/cards/nw_card_album_{i}.{ext}' for i in range(4) for ext in ('xml', 'tex')]
    names += [f'images/inventoryimages/nw_wands{suffix}.{ext}'
              for suffix in ('', *('_'+str(i) for i in range(2, 10))) for ext in ('xml', 'tex')]
    result = []
    for name in names:
        path = target / name
        if path.is_file() and not (source / name).exists():
            if not path.resolve().is_relative_to(target.resolve()) or path.is_symlink():
                raise SystemExit(f'Refusing to remove redirected retired asset: {path}')
            result.append(path)
    return result


def install_files(source, target, selected):
    """Resolve the whole copy plan before making any destination changes."""
    if selected is None:
        files = sorted(p for p in source.rglob('*') if p.is_file())
    else:
        files = []
        for name in selected:
            name = str(name)
            relative = Path(name.replace('\\', '/'))
            windows = PureWindowsPath(name)
            if relative.is_absolute() or windows.drive or windows.root or '..' in relative.parts:
                raise SystemExit(f'Refusing invalid mod-relative file: {name}')
            path = source / relative
            if path not in files:
                files.append(path)
    for path in files:
        destination = target / path.relative_to(source)
        if not path.resolve().is_relative_to(source.resolve()) or not path.is_file():
            raise SystemExit(f'Refusing missing, non-file or redirected source: {path}')
        if not destination.resolve().is_relative_to(target):
            raise SystemExit(f'Refusing redirected destination: {destination}')
        if destination.exists() and not destination.is_file():
            raise SystemExit(f'Refusing non-file destination: {destination}')
        if any(parent.exists() and not parent.is_dir() for parent in destination.parents):
            raise SystemExit(f'Refusing non-directory destination parent: {destination}')
    return files


def install(game, files=None):
    game = Path(game)
    target = game.resolve() / 'mods' / 'nw_weave_dev'
    marker = target / '.nw_workspace'
    if not game.is_dir():
        raise SystemExit(f'Game directory not found: {game}')
    if not target.resolve().is_relative_to(target) or marker.is_symlink():
        raise SystemExit(f'Refusing redirected installation or ownership marker: {target}')
    if target.exists() and (not marker.is_file() or marker.read_text() != str(ROOT)):
        raise SystemExit(f'Refusing to overwrite an installation not owned by this workspace: {target}')
    source = ROOT / 'mod'
    selected = files is not None
    files = install_files(source, target, files)
    # Validate all selected archives before touching the owned installation.
    archives = [path for path in files if path.suffix.lower() == '.zip'
                and path.relative_to(source).parts[0] == 'anim']
    for archive in archives:
        validate_animation_archive(archive)
    fingerprints = {path: digest(path) for path in files}
    changed = [path for path in files if not (target / path.relative_to(source)).is_file()
               or fingerprints[path] != digest(target / path.relative_to(source))]
    obsolete = [] if selected else retired_assets(target, source)
    if changed or obsolete:
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
    for path in obsolete:
        path.unlink()
    for path in files:
        installed = target / path.relative_to(source)
        if fingerprints[path] != digest(installed):
            raise SystemExit(f'Installed file verification failed: {installed}')
    if selected:
        print(f'PASS: selected {len(files)} files; verified {len(files)} files; updated {len(changed)} files; removed 0 retired files; {target}')
    else:
        version = re.search(r'^version\s*=\s*"([^"]+)"', (target / 'modinfo.lua').read_text(encoding='utf8'), re.M)[1]
        print(f'PASS: installed {version}; verified {len(files)} files; updated {len(changed)} files; removed {len(obsolete)} retired files; {target}')
    print('Restart the game and world to load updated Lua, assets and mod configuration options.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
    parser.add_argument('--file', action='append', dest='files', metavar='MOD_RELATIVE_PATH',
                        help='install only this file; repeat to select more files; disables retired-file removal')
    args = parser.parse_args()
    install(args.game, args.files)


if __name__ == '__main__':
    main()
