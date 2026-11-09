"""Build an isolated DST client preview mod; optionally install and watch sources."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import time
import zipfile
from xml.etree import ElementTree as ET
from animation_atlas import validate_animation_archive

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist/live_preview'
STAGE = OUT / 'nw_live_preview'
DEFAULT_GAME = Path("E:/SteamLibrary/steamapps/common/Don't Starve Together")
DEFAULT_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")


def atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(text, encoding='utf8')
    os.replace(temp, path)


def inputs():
    files = list((ROOT / 'assets_src/spell_revision').rglob('*.png'))
    files += list((ROOT / 'assets_src/projectiles/elemental_v1').glob('*.png'))
    files += list((ROOT / 'assets_src/projectiles/basic_v1').glob('*.png'))
    files += list((ROOT / 'assets_src/projectiles/special_v1').glob('*.png'))
    files += list((ROOT / 'assets_src/projectiles/tools_v1').glob('*.png'))
    files += list((ROOT / 'assets_src/fields').rglob('*.png'))
    files += list((ROOT / 'docs/previews/spark-six').glob('*.png'))
    files += list((ROOT / 'assets_src/art_v1/originals').glob('*.png'))
    files += [ROOT / 'tools' / name for name in (
        'build_spell_world.py', 'build_spark_flight.py', 'build_elemental_flight.py',
        'build_tool_flight.py', 'build_field_stages.py', 'spore_stage_art.py', 'build_electric_arc.py', 'native_animation.py', 'build_art_assets.py', 'animation_atlas.py')]
    files += [ROOT / 'mod/scripts/nw' / name for name in (
        'trail_budget.lua', 'flight_visual.lua', 'spark_trail.lua', 'elemental_flight.lua', 'beam_path.lua', 'beam_visual.lua',
        'tool_flight.lua', 'field_stages.lua', 'field_member_visual.lua', 'electric_visual.lua')]
    files += list((ROOT / 'tools/preview_mod').rglob('*.lua'))
    return sorted(files)


def signature():
    h = hashlib.sha256()
    for p in inputs():
        h.update(str(p).encode()); h.update(p.read_bytes())
    return h.hexdigest()


def build(tools):
    started = time.perf_counter()
    revision = 'r' + str(time.time_ns())
    destination = STAGE / 'live' / revision
    destination.mkdir(parents=True)
    cache_dir = OUT / 'cache'
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / 'index.json'
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    banks = {}
    import build_art_assets
    original = build_art_assets.compile_bank

    def compile_preview(name, build_xml, anim_xml, images, ignored_tools):
        key = {'nw_spark_flight': 'spark', 'nw_spell_world': 'world',
               'nw_elemental_flight': 'elemental', 'nw_tool_flight': 'tools',
               'nw_field_stages': 'fields'}[name]
        h = hashlib.sha256(ET.tostring(build_xml) + ET.tostring(anim_xml))
        for image_name, image in sorted(images.items()):
            h.update(image_name.encode()); h.update(str(image.size).encode()); h.update(image.tobytes())
        digest = h.hexdigest()
        cached = cache.get(key, {})
        bank = cached.get('bank')
        archive = cache_dir / (str(bank) + '.zip')
        if cached.get('digest') != digest or not archive.exists():
            bank = f'nw_preview_{key}_{revision}'
            build_xml.set('name', bank)
            for anim in anim_xml.findall('anim'):
                anim.set('root', bank)
            work = OUT / 'work' / bank
            work.mkdir(parents=True)
            package = work / (bank + '.zip')
            with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as z:
                z.writestr('build.xml', ET.tostring(build_xml, encoding='utf8'))
                z.writestr('animation.xml', ET.tostring(anim_xml, encoding='utf8'))
                for image_name, image in images.items():
                    image_path = work / (image_name + '.png')
                    image.save(image_path); z.write(image_path, image_path.name)
            result = subprocess.run([
                str(tools / 'buildtools/windows/Python27/python.exe'),
                str(tools / 'tools/scripts/buildanimation.py'), str(package),
                '--outputdir', str(destination), '--scale', '1', '--force',
            ], cwd=tools, capture_output=True, timeout=90)
            (work / 'compile.log').write_bytes(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError(f'Compiler failed; see {work / "compile.log"}')
            validate_animation_archive(destination / 'anim' / (bank + '.zip'))
            archive = cache_dir / (bank + '.zip')
            shutil.copy2(destination / 'anim' / archive.name, archive)
            cache[key] = {'bank': bank, 'digest': digest}
        else:
            validate_animation_archive(archive)
            (destination / 'anim').mkdir(exist_ok=True)
            shutil.copy2(archive, destination / 'anim' / archive.name)
        with zipfile.ZipFile(archive) as z:
            assert z.read('anim.bin')[:4] == b'ANIM'
            assert z.read('build.bin')[:4] == b'BILD'
            assert bank.encode() in z.read('build.bin')
        banks[key] = bank

    build_art_assets.compile_bank = compile_preview
    try:
        for script in ('build_spark_flight.py', 'build_spell_world.py'):
            runpy.run_path(str(ROOT / 'tools' / script), run_name='__preview__')
        for script in ('build_elemental_flight.py', 'build_tool_flight.py', 'build_field_stages.py'):
            builder = runpy.run_path(str(ROOT / 'tools' / script), run_name='__preview__')
            build_xml, anim_xml, images, _ = builder['make_bank']()
            # Use the isolated compiler; do not replace production files.
            compile_preview(builder['BANK'], build_xml, anim_xml, images, tools)
    finally:
        build_art_assets.compile_bank = original
    # Native shock textures stay in the installed game; only the animation
    # matrices need an isolated bank so an open preview can reload them.
    import build_electric_arc
    banks['electric'] = f'nw_preview_electric_{revision}'
    build_electric_arc.build(banks['electric'], destination / 'anim' / (banks['electric']+'.zip'), manifest=False)
    validate_animation_archive(destination / 'anim' / (banks['electric']+'.zip'))
    module_names = {
        'budget': 'trail_budget', 'flight': 'flight_visual', 'trail': 'spark_trail', 'elemental': 'elemental_flight',
        'beam_path': 'beam_path', 'beam_visual': 'beam_visual', 'tools': 'tool_flight',
        'fields': 'field_stages', 'members': 'field_member_visual',
        'size': 'projectile_size', 'electric': 'electric_visual',
    }
    source = 'local factories,loaded={},{}\n'
    for name in module_names.values():
        text = (ROOT / 'mod/scripts/nw' / (name + '.lua')).read_text(encoding='utf8')
        for original_bank, key in (
            ('nw_spell_world', 'world'), ('nw_spark_flight', 'spark'),
            ('nw_elemental_flight', 'elemental'), ('nw_tool_flight', 'tools'),
            ('nw_field_stages', 'fields'),
            ('nw_electric_arc', 'electric'),
        ):
            text = text.replace(json.dumps(original_bank), json.dumps(banks[key]))
        source += f'factories["nw/{name}"]=function(require)\n{text}\nend\n'
    source += ('local function load(name)\n'
               ' if not factories[name] then return require(name) end\n'
               ' if not loaded[name] then loaded[name]=factories[name](load) end\n'
               ' return loaded[name]\nend\n')
    source += 'return {' + ','.join(f'{key}=load("nw/{name}")' for key, name in module_names.items()) + '}\n'
    # Syntax check the generated, actual runtime modules before publication.
    from lupa.lua51 import LuaRuntime
    LuaRuntime().eval('function(s) assert(loadstring(s)) end')(source)
    (destination / 'visual.lua').write_text(source, encoding='utf8')
    shutil.copytree(ROOT / 'tools/preview_mod', STAGE, dirs_exist_ok=True)
    for file in (ROOT / 'tools/preview_mod').rglob('*.lua'):
        LuaRuntime().eval('function(s) assert(loadstring(s)) end')(file.read_text(encoding='utf8'))
    atomic_text(cache_path, json.dumps(cache))
    manifest = f'{revision} {banks["spark"]} {banks["world"]} {banks["elemental"]} {banks["tools"]} {banks["fields"]} {banks["electric"]}\n'
    atomic_text(STAGE / 'live/current.txt', manifest)
    print(f'BUILT {revision}: {time.perf_counter()-started:.2f}s', flush=True)
    return revision, manifest


def publish(game, revision, manifest):
    if not (game / 'data').is_dir():
        raise RuntimeError(f'Game not found: {game}')
    target = game / 'mods/nw_live_preview'
    marker = target / '.nw_preview_workspace'
    if target.exists() and (not marker.exists() or marker.read_text() != str(ROOT)):
        raise RuntimeError(f'Refusing to overwrite unowned mod: {target}')
    target.mkdir(parents=True, exist_ok=True)
    marker.write_text(str(ROOT))
    for name in ('modinfo.lua', 'modmain.lua'):
        shutil.copy2(STAGE / name, target / name)
    shutil.copytree(STAGE / 'scripts', target / 'scripts', dirs_exist_ok=True)
    shutil.copytree(STAGE / 'live' / revision, target / 'live' / revision)
    # Publish only after every resource is present; a failed build keeps the old revision.
    atomic_text(target / 'live/current.txt', manifest)
    print(f'PUBLISHED {target} (client polls every 0.5s)', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install', action='store_true', help='Install/update the separate client mod')
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--game', type=Path, default=DEFAULT_GAME)
    parser.add_argument('--tools', type=Path, default=DEFAULT_TOOLS)
    args = parser.parse_args()
    previous = None
    while True:
        current = signature()
        if current != previous:
            if args.watch:
                time.sleep(.4)
                if signature() != current:
                    continue  # Wait for image editors to finish saving.
            try:
                revision, manifest = build(args.tools)
                if args.install:
                    publish(args.game, revision, manifest)
            except Exception as exc:
                print(f'ERROR: {exc}', flush=True)
                if not args.watch:
                    raise
            previous = current
        if not args.watch:
            break
        time.sleep(.5)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('\nWatcher stopped; game preview can be stopped with nw_preview_stop().')
