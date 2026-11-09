"""Compile approved storage art into a standalone review package.

This script never writes to mod/ or an installed game. Input PNGs are already
authored at runtime resolution; packaging preserves their size and RGBA pixels.
See assets_src/arcane_storage_final/clip_manifest_schema.json for the contract.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

if sys.version_info < (3,9):
    raise SystemExit('Python 3.9 or newer is required.')

try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit('Pillow is required. Run: python3 -m pip install Pillow')

from animation_atlas import validate_animation_archive, validate_ktex
from native_animation import NativeAnimation, read_animation, read_build, texture

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT if any((ROOT / name / 'clip_manifest.json').is_file()
                      for name in ('dustbox', 'emberlamp'))
          else ROOT / 'assets_src/arcane_storage_final')
TOOLS = Path(os.environ.get('DST_MOD_TOOLS', "E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools"))
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
CURRENT_ART_REVISION = 'r3'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def named(value, label):
    require(isinstance(value, str) and NAME.fullmatch(value), f"{label}: invalid name {value!r}")
    return value


def source_path(root, relative):
    require(isinstance(relative, str), "asset path must be a string")
    path = (root / relative.replace('\\', '/')).resolve()
    require(path.is_relative_to(root.resolve()), f"asset escapes its source directory: {relative}")
    require(path.suffix.lower() == ".png" and path.is_file(), f"missing PNG: {path}")
    return path


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def package_revision():
    """Keep downloaded releases on their own revision when repackaging them."""
    index = SOURCE/'portable_manifest.json'
    revision = (json.loads(index.read_text(encoding='utf8')).get('art_revision', 'r2')
                if index.is_file() else CURRENT_ART_REVISION)
    require(isinstance(revision, str) and re.fullmatch(r'r[1-9][0-9]*', revision),
            f'Invalid art revision: {revision!r}')
    return revision


def atomic_copy(source, destination):
    """Publish an alias only after its complete contents have been copied."""
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=destination.name+'.',
                                     suffix='.tmp', delete=False) as opened:
        temporary = Path(opened.name)
    try:
        shutil.copyfile(source, temporary)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def bundle_path(root, relative):
    """Resolve portable index paths without allowing host-specific escape paths."""
    require(isinstance(relative, str), 'bundle path must be a string')
    relative = relative.replace('\\', '/')
    require(not relative.startswith('/') and ':' not in relative and
            '..' not in relative.split('/'), f'invalid bundle path: {relative}')
    path = (root / relative).resolve()
    require(path.is_relative_to(root.resolve()), f'bundle path escapes root: {relative}')
    return path


def check_toolchain(tools):
    require(sys.platform == 'win32',
            'Native recompilation currently uses the Windows Klei toolchain. '
            'On macOS/Linux use the default standalone command to verify/package the supplied runtime, '
            'or --preview-only for edited artwork. Recompile changed native assets on Windows with --recompile --tools PATH.')
    required = ['buildtools/windows/Python27/python.exe', 'tools/scripts/buildanimation.py',
                'tools/bin/TextureConverter.exe']
    missing = [name for name in required if not (tools/name).is_file()]
    require(not missing, 'Klei toolchain not found at '+str(tools)+'. Set --tools PATH or DST_MOD_TOOLS. '
            'For a downloaded bundle use the default command (no --recompile). Missing: '+', '.join(missing))


def portable_index(package, names, reports, inventory):
    """Bind supplied binaries to their exact manifests and rendered PNG inputs."""
    inputs, outputs = {}, {}
    for name in names:
        manifest = SOURCE/name/'clip_manifest.json'
        bank = json.loads(manifest.read_text(encoding='utf-8-sig'))['bank']
        report = next(row for row in reports if row['bank'] == bank)
        require(report.get('manifest_sha256') == sha256(manifest),
                f'{name}: manifest changed since compilation; use --recompile')
        inputs[f'{name}/clip_manifest.json'] = sha256(manifest)
        for relative, check in report['source_png_checks'].items():
            relative = relative.replace('\\', '/')
            path = source_path(SOURCE/name,relative)
            require(sha256(path) == check['sha256'], f'{path}: changed since compilation')
            inputs[f'{name}/{relative}'] = check['sha256']
        data = json.loads(manifest.read_text(encoding='utf-8-sig'))
        for element, relative in data['icons'].items():
            relative = relative.replace('\\', '/')
            path = source_path(SOURCE/name,relative)
            digest = report['inventory_png_checks'][element]['sha256']
            require(sha256(path) == digest, f'{path}: icon changed since compilation')
            inputs[f'{name}/{relative}'] = digest
        outputs[f'runtime/anim/{bank}.zip'] = sha256(package/'anim'/f'{bank}.zip')
        outputs[f'animation_source/{bank}.zip'] = sha256(package/'source'/f'{bank}.zip')
    for suffix in ('png','xml','tex'):
        relative = 'images/inventoryimages/nw_arcane_storage.'+suffix
        outputs['runtime/'+relative] = sha256(package/relative)
    outputs['validation/report.json'] = sha256(package/'validation/report.json')
    result = {'version':1,'art_revision':package_revision(),'assets':names,'inputs':inputs,'outputs':outputs,
              'purpose':'Verify precompiled runtime before packaging on any OS; source changes require native recompilation.'}
    (package/'portable_manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    return result


def reuse_compiled(package, names):
    """Package the downloaded, unchanged compiled runtime without invoking an SDK."""
    index_path = SOURCE/'portable_manifest.json'
    require(index_path.is_file(), 'Missing portable_manifest.json. Download the fixed portable bundle; '
            'older R2 bundles only contained repository-specific build scripts.')
    index = json.loads(index_path.read_text(encoding='utf8'))
    require(index.get('version') == 1, 'Unsupported portable index version')
    require(set(names) == set(index['assets']),
            'The supplied inventory atlas is shared. Repackage all bundled assets, '
            'or use --preview-only/--recompile for an --asset subset.')
    # Verify everything before creating or overwriting outputs. Never silently
    # ship old binaries after PNG/animation edits or a damaged archive.
    for section in ('inputs','outputs'):
        for relative, digest in index[section].items():
            path = bundle_path(SOURCE,relative)
            require(path.is_file(), f'Missing bundled file: {relative}. Re-extract the portable ZIP.')
            require(sha256(path) == digest,
                    f'Bundled {section} changed: {relative}. '
                    'Use --preview-only for edited art, or --recompile with the Klei toolchain. '
                    'If no edit was intended, re-extract the portable ZIP.')
    report = json.loads((SOURCE/'validation/report.json').read_text(encoding='utf8'))
    for asset in report['assets']:
        validate_animation_archive(SOURCE/'runtime/anim'/f"{asset['bank']}.zip")
    validate_ktex((SOURCE/'runtime/images/inventoryimages/nw_arcane_storage.tex').read_bytes(),
                  'nw_arcane_storage.tex')
    package.mkdir(parents=True,exist_ok=True)
    for relative in index['outputs']:
        if relative.startswith('runtime/'):
            dest = package/relative[len('runtime/'):]
        elif relative.startswith('animation_source/'):
            dest = package/'source'/relative[len('animation_source/'):]
        else:
            continue
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(bundle_path(SOURCE,relative),dest)
    shutil.copytree(SOURCE/'validation',package/'validation',dirs_exist_ok=True)
    return report


def inspect_png(path, canvas):
    with Image.open(path) as opened:
        require(opened.mode == "RGBA", f"{path}: expected authored RGBA, got {opened.mode}")
        im = opened.copy()
    require(im.size == tuple(canvas), f"{path}: {im.size} differs from declared canvas {canvas}")
    alpha = im.getchannel("A")
    low, high = alpha.getextrema()
    require(low == 0 and high > 0, f"{path}: expected nonempty artwork and transparent background")
    visible = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    require(visible is not None, f"{path}: artwork is practically invisible")
    require(visible[0] > 0 and visible[1] > 0 and visible[2] < im.width and visible[3] < im.height,
            f"{path}: visible artwork touches canvas edge: {visible}")
    require(all(alpha.getpixel(p) == 0 for p in ((0, 0), (im.width-1, 0),
                                               (0, im.height-1), (im.width-1, im.height-1))),
            f"{path}: corners must be fully transparent")
    return im, {"size": list(im.size), "alpha_extrema": [low, high], "visible_bbox": list(visible),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def load_manifest(path):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    require(data.get("version") == 1, f"{path}: expected manifest version 1")
    bank = named(data.get("bank"), "bank")
    canvas = data.get("canvas")
    require(isinstance(canvas, list) and len(canvas) == 2 and
            all(isinstance(v, int) and v > 0 for v in canvas), f"{bank}: invalid canvas")
    anchor = data.get("anchor")
    require(isinstance(anchor, list) and len(anchor) == 2 and
            all(isinstance(v, (int, float)) and math.isfinite(v) and 0 <= v <= canvas[i]
                for i, v in enumerate(anchor)), f"{bank}: invalid pixel anchor")
    clips = data.get("clips")
    require(isinstance(clips, dict) and clips, f"{bank}: no animation clips")
    clips = dict(clips)
    aliases = data.get("aliases", {})
    require(isinstance(aliases, dict), f"{bank}: aliases must be a mapping")
    for name, target in aliases.items():
        named(name, "animation alias")
        require(name not in clips and target in clips, f"{bank}: invalid alias {name} -> {target}")
        clips[name] = clips[target]
    pictures, reports = {}, {}
    for name, clip in clips.items():
        named(name, "animation")
        fps = clip.get("fps")
        require(isinstance(fps, (int, float)) and math.isfinite(fps) and 0 < fps <= 120,
                f"{bank}/{name}: invalid fps")
        require(isinstance(clip.get("frames"), list) and clip["frames"], f"{bank}/{name}: no frames")
        for relative in clip["frames"]:
            if relative not in pictures:
                pictures[relative], reports[relative] = inspect_png(source_path(path.parent, relative), canvas)
    icons, icon_reports = {}, {}
    for name, relative in data.get("icons", {}).items():
        named(name, "inventory element")
        icons[name], icon_reports[name] = inspect_png(source_path(path.parent, relative), (64, 64))
    require(icons, f"{bank}: no inventory icons")
    return data, clips, pictures, icons, reports, icon_reports


def write_xml(path, element):
    ET.indent(element)
    ET.ElementTree(element).write(path, encoding="utf-8", xml_declaration=True)


def compile_bank(manifest, package, tools):
    data, clips, pictures, icons, png_report, icon_report = load_manifest(manifest)
    bank = data["bank"]
    width, height = data["canvas"]
    # Build coordinates describe the image centre relative to its ground anchor.
    pivot = (width / 2 - data["anchor"][0], height / 2 - data["anchor"][1])
    stage = package / "source" / bank
    stage.mkdir(parents=True, exist_ok=True)
    build = ET.Element("Build", name=bank)
    animations = ET.Element("Anims")
    digest_symbols, path_symbols = {}, {}
    for path, picture in pictures.items():
        digest = hashlib.sha256(picture.tobytes()).hexdigest()
        if digest not in digest_symbols:
            symbol = f"pose_{len(digest_symbols):03}"
            digest_symbols[digest] = symbol
            picture.save(stage / (symbol + ".png"))
            node = ET.SubElement(build, "Symbol", name=symbol)
            ET.SubElement(node, "Frame", framenum="0", duration="1", image=symbol,
                          x=str(pivot[0]), y=str(pivot[1]), w=str(width), h=str(height))
        path_symbols[path] = digest_symbols[digest]
    for name, clip in clips.items():
        node = ET.SubElement(animations, "anim", name=name, root=bank, framerate=str(clip["fps"]))
        for path in clip["frames"]:
            pose = ET.SubElement(node, "frame", x=str(pivot[0]), y=str(pivot[1]),
                                 w=str(width), h=str(height))
            ET.SubElement(pose, "element", name=path_symbols[path], frame="0", layername="body",
                          z_index="0", m_a="1", m_b="0", m_c="0", m_d="1", m_tx="0", m_ty="0")
    write_xml(stage / "build.xml", build)
    write_xml(stage / "animation.xml", animations)
    source_zip = package / "source" / (bank + ".zip")
    with zipfile.ZipFile(source_zip, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in list(digest_symbols.values()):
            archive.write(stage / (name + ".png"), name + ".png")
        for name in ("build.xml", "animation.xml"):
            archive.write(stage / name, name)
    result = subprocess.run([
        str(tools / "buildtools/windows/Python27/python.exe"),
        str(tools / "tools/scripts/buildanimation.py"), str(source_zip),
        "--outputdir", str(package), "--scale", "1", "--force"],
        cwd=tools, capture_output=True, timeout=180)
    log = package / "validation" / (bank + "_compiler.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_bytes(result.stdout + result.stderr)
    require(result.returncode == 0, f"{bank}: compiler failed; see {log}")
    target = package / "anim" / (bank + ".zip")
    compiled = validate_animation_archive(target)
    with zipfile.ZipFile(target) as archive:
        actual_clips = read_animation(archive.read("anim.bin"))
        actual = {clip["name"]: clip for clip in actual_clips}
        actual_build = read_build(archive.read("build.bin"))
        renderer = NativeAnimation.__new__(NativeAnimation)
        renderer.clips, renderer.build, renderer.cache = actual_clips, actual_build, {}
        renderer.atlases = [texture(archive.read(name)) for name in actual_build["atlases"]]
    require(actual_build["name"] == bank, f"{bank}: compiled build changed name")
    require(set(actual) == set(clips), f"{bank}: compiled animation names differ")
    for name, clip in clips.items():
        require(len(actual[name]["frames"]) == len(clip["frames"]), f"{bank}/{name}: frame count mismatch")
        require(abs(actual[name]["fps"] - clip["fps"]) < .001, f"{bank}/{name}: frame rate mismatch")
        require(all(len(frame["elements"]) == 1 for frame in actual[name]["frames"]),
                f"{bank}/{name}: compiled frame missing artwork")
    # Check the coordinate bounds stored by the compiler as well as source JSON.
    for frames in actual_build["frames"].values():
        for row in frames:
            require(abs(row[2] - pivot[0]) < .001 and abs(row[3] - pivot[1]) < .001,
                    f"{bank}: compiled anchor differs from authored anchor")
    # Reconstruct representative frames from the actual compiled bank so the
    # review also exposes atlas packing, compression and coordinate mistakes.
    review_names = list(data["clips"])
    cell_w, cell_h = max(240, width + 24), max(220, height + 50)
    review = Image.new("RGBA", (cell_w * 3, math.ceil(len(review_names) / 3) * cell_h), "#77766f")
    drawing = ImageDraw.Draw(review)
    for i, name in enumerate(review_names):
        x, y = i % 3 * cell_w, i // 3 * cell_h
        drawing.text((x+10, y+10), name, fill="white")
        index = len(clips[name]["frames"]) // 2
        sprite, (left, top) = renderer.render_frame(name, index)
        px = x + (cell_w-width)//2 + round(data["anchor"][0]) + left
        py = y + 35 + round(data["anchor"][1]) + top
        review.alpha_composite(sprite, (px, py))
    review.convert("RGB").save(package / "validation" / (bank + "_compiled_review.png"))
    compiled['archive'] = f'runtime/anim/{bank}.zip'
    report = {"bank": bank, "manifest": manifest.relative_to(SOURCE).as_posix(),
              "source_revision": data.get('revision', data.get('art_revision')),
              "manifest_sha256": sha256(manifest),
              "canvas": data["canvas"], "ground_anchor_pixels": data["anchor"],
              "build_pivot": list(pivot), "shadow": data.get("shadow"),
              "compiled_archive": compiled, "unique_images": len(digest_symbols),
              "visible_bottom_range_pixels": [min(row["visible_bbox"][3] for row in png_report.values()),
                                                max(row["visible_bbox"][3] for row in png_report.values())],
              "clips": {name: {"fps": clip["fps"], "frames": len(clip["frames"]),
                                "duration_seconds": len(clip["frames"]) / clip["fps"]}
                        for name, clip in clips.items()},
              "source_png_checks": png_report, "inventory_png_checks": icon_report}
    return report, icons


def inventory_atlas(icons, package, tools):
    count = len(icons)
    columns = min(8, 2 ** math.ceil(math.log2(max(1, count))))
    rows = 2 ** math.ceil(math.log2(math.ceil(count / columns)))
    sheet = Image.new("RGBA", (columns * 64, rows * 64))
    atlas = ET.Element("Atlas")
    ET.SubElement(atlas, "Texture", filename="nw_arcane_storage.tex")
    entries = ET.SubElement(atlas, "Elements")
    for i, (name, icon) in enumerate(icons.items()):
        x, y = i % columns * 64, i // columns * 64
        sheet.alpha_composite(icon, (x, y))
        ET.SubElement(entries, "Element", name=name + ".tex", u1=str(x / sheet.width),
                      u2=str((x+64) / sheet.width), v1=str(1 - (y+64) / sheet.height),
                      v2=str(1 - y / sheet.height))
    target = package / "images/inventoryimages"
    target.mkdir(parents=True, exist_ok=True)
    png = target / "nw_arcane_storage.png"
    sheet.save(png)
    write_xml(target / "nw_arcane_storage.xml", atlas)
    result = subprocess.run([str(tools / "tools/bin/TextureConverter.exe"), "--swizzle",
                             "--format", "bc3", "--platform", "opengl", "--premultiply",
                             "-i", str(png), "-o", str(target / "nw_arcane_storage.tex")],
                            capture_output=True, timeout=90)
    (package / "validation/inventory_compiler.log").write_bytes(result.stdout + result.stderr)
    require(result.returncode == 0, "inventory texture compiler failed")
    validate_ktex((target / "nw_arcane_storage.tex").read_bytes(), "nw_arcane_storage.tex")
    # Show actual-size 64 and 32 px output against both light and dark UI fields.
    review = Image.new("RGB", (600, max(1, count) * 96 + 35), "#797979")
    draw = ImageDraw.Draw(review)
    draw.text((12, 10), "64 px / 32 px: light and dark backgrounds", fill="white")
    for i, (name, icon) in enumerate(icons.items()):
        y = 35 + i * 96
        draw.text((8, y+32), name, fill="white")
        for x, colour in ((260, "#d3c9b7"), (425, "#26262c")):
            draw.rectangle((x, y, x+155, y+86), fill=colour)
            review.paste(icon, (x+6, y+10), icon)
            small = icon.resize((32, 32), Image.Resampling.LANCZOS)
            review.paste(small, (x+104, y+26), small)
    review.save(package / "validation/inventory_64_32_review.png")
    return {"atlas": "images/inventoryimages/nw_arcane_storage.xml", "element_size": [64, 64],
            "atlas_size": list(sheet.size), "elements": list(icons), "format": "BC3 premultiplied RGBA"}


def write_viewer(package, names):
    """A local-file review page: inline metadata avoids browser fetch/CORS."""
    assets = []
    for name in names:
        data = json.loads((SOURCE / name / "clip_manifest.json").read_text(encoding="utf-8-sig"))
        for clip in data['clips'].values():
            clip['frames'] = [path.replace('\\', '/') for path in clip['frames']]
        data['icons'] = {name: path.replace('\\', '/') for name, path in data['icons'].items()}
        data["directory"] = "../" + name + "/"
        data["label"] = {"dustbox": "粉尘收纳盒", "emberlamp": "奥术余烬灯"}[name]
        assets.append(data)
    payload = json.dumps(assets, ensure_ascii=False).replace("</", "<\\/")
    html = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>收纳盒与余烬灯 · __REVISION__ 动画检查</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#1f2023;color:#efebe4;font:15px/1.6 system-ui,"Microsoft YaHei",sans-serif}
main{max-width:1160px;margin:0 auto;padding:32px 24px}h1{font-size:27px;margin:0 0 8px}p{color:#c1bcb3;margin:0 0 22px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(350px,1fr));gap:24px}.card{width:100%;max-width:560px;background:#2c2c31;border:1px solid #49464d;border-radius:14px;overflow:hidden}
h2{font-size:19px;padding:16px 20px;margin:0}canvas{display:block;width:100%;height:auto;background:#77766f}.controls{padding:16px 20px;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
select,button{font:inherit;color:#f4ecdf;background:#3c3740;border:1px solid #746775;border-radius:7px;padding:7px 10px}button{cursor:pointer}select{max-width:100%}
label{white-space:nowrap}.meta{padding:0 20px 16px;color:#bab3bf;font-size:13px}.error{color:#ffb8a4}.icons{padding:0 20px 18px;display:flex;gap:12px;flex-wrap:wrap}.icons img{width:64px;height:64px;background:#66615b;border-radius:4px}
</style><main><h1>收纳盒与余烬灯 · __REVISION__ 动画检查</h1>
<p>分别放大查看空、半满、满三档及各段动画。地面版保留贴地阴影，物品栏图标使用透明背景。</p>
<div class="grid" id="grid"></div></main><script>
const assets=__ASSETS__;
const labels={empty:'空',half:'半满',full:'满',closed:'合盖静止',opened:'开盖静止',open:'开盖',close:'合盖',off:'未点燃',on:'点燃静止',ignite:'点燃',extinguish:'熄灭',burn:'燃烧循环',burning:'燃烧循环',loop:'循环',idle:'静止',turn:'',pre:'开始',post:'结束'};
const title=name=>name.split('_').map(part=>labels[part]??part).filter(Boolean).join(' · ');
const imageCache=new Map();
function picture(path){if(!imageCache.has(path)){const im=new Image();const promise=new Promise((resolve,reject)=>{im.onload=()=>resolve(im);im.onerror=()=>reject(new Error('无法读取 '+path));});im.src=path;imageCache.set(path,promise);}return imageCache.get(path);}
for(const data of assets){
 const card=document.createElement('section');card.className='card';
 card.innerHTML='<h2></h2><canvas width="520" height="390"></canvas><div class="controls"><select aria-label="动画"></select><button>暂停</button><button>重播</button><label><input type="checkbox" checked>循环</label><select aria-label="检查背景"><option value="#77766f">中性底</option><option value="#d3c9b7">浅底</option><option value="#26262c">深底</option></select></div><div class="meta"></div><div class="icons"></div>';
 document.getElementById('grid').appendChild(card);card.querySelector('h2').textContent=data.label;
 const canvas=card.querySelector('canvas'),ctx=canvas.getContext('2d'),[clips,bg]=card.querySelectorAll('select'),[pause,restart]=card.querySelectorAll('button'),loop=card.querySelector('input'),meta=card.querySelector('.meta');
 for(const name of Object.keys(data.clips)){const o=document.createElement('option');o.value=name;o.textContent=title(name);clips.appendChild(o);}
 for(const preferred of ['opened_half','burn_half','on_half','idle_half','off_half']){if(data.clips[preferred]){clips.value=preferred;break;}}
 let frames=[],started=performance.now(),paused=false,pauseAt=0,loadId=0,error='';
 async function load(){const id=++loadId;frames=[];error='';try{const next=await Promise.all(data.clips[clips.value].frames.map(path=>picture(data.directory+path)));if(id===loadId){frames=next;started=performance.now();pauseAt=0;meta.className='meta';}}catch(e){error=e.message;meta.textContent=error;meta.className='meta error';}}
 clips.onchange=load;pause.onclick=()=>{paused=!paused;if(paused){pauseAt=performance.now()-started;pause.textContent='播放';}else{started=performance.now()-pauseAt;pause.textContent='暂停';}};
 restart.onclick=()=>{started=performance.now();pauseAt=0;};
 for(const [name,path] of Object.entries(data.icons)){const im=document.createElement('img');im.src=data.directory+path;im.alt=name;im.title=name;card.querySelector('.icons').appendChild(im);}
 function tick(now){const [w,h]=data.canvas;const scale=Math.min(1.75,480/w,340/h);const ox=(canvas.width-w*scale)/2,oy=canvas.height-24-data.anchor[1]*scale;
 ctx.fillStyle=bg.value;ctx.fillRect(0,0,canvas.width,canvas.height);
 if(data.shadow?.mode==='dynamic'){ctx.fillStyle='rgba(19,17,23,.30)';ctx.beginPath();ctx.ellipse(ox+data.anchor[0]*scale,oy+data.anchor[1]*scale,w*.29*scale,Math.max(7,w*.048*scale),0,0,Math.PI*2);ctx.fill();}
 if(frames.length){const clip=data.clips[clips.value],time=Math.max(0,paused?pauseAt:now-started);let index=Math.floor(time/1000*clip.fps);index=loop.checked?index%frames.length:Math.min(index,frames.length-1);ctx.drawImage(frames[index],ox,oy,w*scale,h*scale);meta.textContent=`${index+1} / ${frames.length} 帧 · ${clip.fps} fps`;}
 else if(!error){meta.textContent='载入透明帧…';}requestAnimationFrame(tick);}
 load();requestAnimationFrame(tick);
}
</script></html>'''
    revision = package_revision()
    html = html.replace('__ASSETS__', payload).replace('__REVISION__', revision.upper())
    for name in ('review.html', f'review_{revision}.html'):
        (package/name).write_text(html, encoding='utf8')


def write_bundle(package, names, reports, inventory):
    revision = package_revision()
    portable_index(package,names,reports,inventory)
    requirements = package/'requirements.txt'
    requirements.write_text('Pillow>=10\nnumpy>=1.24\n',encoding='utf8')
    guide = package/'BUILD.txt'
    export_steps = ['  python3 tools/build_dustbox_jewellery_art.py']
    if revision == 'r2':
        export_steps.append('  python3 emberlamp/export_r2_extinguish.py')
    export_steps.extend(['  python3 tools/build_emberlamp_art.py',
                         '  python3 emberlamp/export_inventory.py',
                         '  python3 tools/package_arcane_storage_art.py --preview-only'])
    guide.write_text(f'''{revision.upper()} 独立素材包构建（Windows / macOS / Linux，Python 3.9或更新版本）

在解压目录执行：
  python3 -m pip install -r requirements.txt
  python3 tools/package_arcane_storage_art.py

默认命令校验源帧、动画清单和随包已编译资源的SHA256，再输出package/。
这个步骤不调用Windows程序，不依赖游戏安装目录，也不重新编译ANIM或TEX。
查看动画：package/review_{revision}.html（review.html为同内容入口）。
新打包文件：package/arcane_storage_art_{revision}_portable.zip。
arcane_storage_art_{revision}.zip与arcane_storage_art_bundle.zip是相同内容的下载别名。
其他版本的命名ZIP与预览页保持不变；bundle别名始终指向本次输出。
包内runtime/本身已包含编译好的游戏资源；只查看动画可直接打开review/review_{revision}.html。
脚本按自身位置识别文件，支持从其他工作目录使用脚本绝对路径执行。

修改美术后：
{chr(10).join(export_steps)}

PNG导出和预览支持跨平台。若运行帧、图标或动画清单发生变化，默认打包会拒绝沿用旧编译资源。
本包的原生编译流程使用Windows版Klei工具链。在有该工具链的Windows环境中执行：
  python tools/package_arcane_storage_art.py --recompile --tools "实际的mod_tools目录"
也可设置DST_MOD_TOOLS环境变量。--recompile会重新生成ANIM/BILD/TEX，而不是复用旧文件。

其他参数：
  --validate-only 只检查当前PNG与清单，不写输出。
  --source PATH 显式指定包含dustbox/emberlamp的目录；通常无需设置。
  --asset dustbox / --asset emberlamp 可用于单物预览、校验或重新编译。
  默认复用模式保留两件物品共享的图标图集，需完整保留随包的两件物品。

完整仓库仍可直接运行tools/package_arcane_storage_art.py；在仓库内默认使用原生编译流程。
两个PNG导出脚本同时兼容仓库与解压目录。重打包不会修改mod/或安装到游戏。
''',encoding='utf8')
    lines = [
        f"粉尘收纳盒与奥术余烬灯：{revision.upper()} 美术交付包", "",
        "本包包含透明源图、分层素材、状态帧、动画预览、物品栏图标及官方工具编译的动画和纹理。",
        "这是独立的美术包；未修改 mod 脚本、未安装到游戏，未执行实机玩法验收。",
        "空／半满／满是美术状态。无限容器的数量到状态映射由后续接入逻辑定义，满态不代表容量上限。",
        "地面阴影依据各 clip_manifest.json 的 shadow 配置接入；已合成地影的世界帧不再叠加 DynamicShadow。物品栏图标不含地影。", "",
        "目录：", "  dustbox/、emberlamp/：生成源图、Prompt、分层、世界帧、图标及清单。",
        "  runtime/anim/：可供 AnimState 使用的原生动画包。",
        "  runtime/images/inventoryimages/：64 像素图标图集；使用 nw_arcane_storage.xml 的元素名称。",
        "  animation_source/：官方编译器输入 ZIP，内含 build.xml、animation.xml 和逐帧 PNG。",
        "  tools/：分层／动画／打包脚本及读取校验工具，支持仓库与独立解压目录。",
        "  validation/：编译日志、资源检查报告、64／32 像素浅深底预览。",
        f"  review/review_{revision}.html：解压后直接打开即可逐项查看动画；review.html为同内容入口。", "",
        "动画：",
    ]
    for report in reports:
        lines.append(f"  bank/build: {report['bank']}; canvas: {report['canvas']}; anchor: {report['ground_anchor_pixels']}")
        for name, clip in report["clips"].items():
            lines.append(f"    {name}: {clip['frames']} frames @ {clip['fps']} fps")
    lines.extend(["", "图标元素：", *["  " + name + ".tex" for name in inventory["elements"]], "",
        "独立包（macOS / Linux / Windows）：",
                  "  python3 -m pip install -r requirements.txt",
                  "  python3 tools/package_arcane_storage_art.py",
                  "默认校验并打包随包已编译资源；原生重新编译使用 --recompile 及Windows Klei工具链。",
                  "完整说明见BUILD.txt。", "",
                  "各图像的真正透明 Alpha 在 PNG 源图中保留。编译结果已检查 ANIM/BILD、KTEX、图集页数、动画名称、帧数、帧率及锚点。"])
    readme = package / "README.txt"
    readme.write_text("\n".join(lines) + "\n", encoding="utf8")
    bundle = package/f'arcane_storage_art_{revision}_portable.zip'
    # Keep the previous download intact if writing this archive is interrupted.
    with tempfile.NamedTemporaryFile(dir=package, prefix=bundle.name+'.',
                                     suffix='.tmp', delete=False) as opened:
        temporary = Path(opened.name)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.write(readme, 'README.txt')
            archive.write(guide,'BUILD.txt')
            archive.write(requirements,'requirements.txt')
            archive.write(package/'portable_manifest.json','portable_manifest.json')
            for name in ('review.html', f'review_{revision}.html'):
                archive.write(package/name,'review/'+name)
            archive.write(SOURCE/'clip_manifest_schema.json','clip_manifest_schema.json')
            for report in reports:
                source_zip = package/'source'/(report['bank']+'.zip')
                archive.write(source_zip,'animation_source/'+source_zip.name)
            for script in ('build_dustbox_jewellery_art.py','build_emberlamp_art.py',
                           'package_arcane_storage_art.py','animation_atlas.py','native_animation.py'):
                archive.write(ROOT/'tools'/script,'tools/'+script)
            for name in names:
                for path in sorted((SOURCE/name).rglob('*')):
                    if path.is_file() and '_rejected' not in path.stem and '__pycache__' not in path.parts:
                        archive.write(path,path.relative_to(SOURCE).as_posix())
            # Keep partial builds isolated from stale banks left by an earlier run.
            for report in reports:
                bank = report['bank']
                archive.write(package/'anim'/f'{bank}.zip',f'runtime/anim/{bank}.zip')
            for suffix in ('png','xml','tex'):
                relative = f'images/inventoryimages/nw_arcane_storage.{suffix}'
                archive.write(package/relative,'runtime/'+relative)
            selected_banks = [row['bank'] for row in reports]
            for path in sorted((package/'validation').iterdir()):
                if path.is_file() and (path.name == 'report.json' or
                        path.name.startswith(('inventory_',f'viewer_{revision}')) or
                        any(path.name.startswith(bank+'_') for bank in selected_banks)):
                    archive.write(path,'validation/'+path.name)
        temporary.replace(bundle)
    finally:
        temporary.unlink(missing_ok=True)
    for name in (f'arcane_storage_art_{revision}.zip','arcane_storage_art_bundle.zip'):
        atomic_copy(bundle,package/name)
    return bundle


def main():
    global SOURCE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", choices=("dustbox", "emberlamp"), action="append",
                        help="Build one asset while the other is still being authored")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--validate-only", action="store_true", help="Check source PNGs without compiling")
    mode.add_argument('--preview-only',action='store_true',help='Validate current art and generate a viewer without native compilation')
    mode.add_argument('--recompile',action='store_true',help='Recompile native assets using the Windows Klei toolchain')
    mode.add_argument('--reuse-compiled',action='store_true',help='Verify and repackage the supplied portable runtime without a compiler')
    parser.add_argument('--source',type=Path,help='Directory containing dustbox/ and emberlamp/; detected automatically by default')
    parser.add_argument("--tools", type=Path, default=TOOLS)
    args = parser.parse_args()
    SOURCE = (args.source or SOURCE).resolve()
    names = args.asset or [name for name in ('dustbox','emberlamp')
                           if (SOURCE/name/'clip_manifest.json').is_file()]
    require(names, f'No asset manifests found in {SOURCE}. Use --source PATH to the directory containing dustbox/ and emberlamp/.')
    package = SOURCE / "package"
    for name in names:
        require((SOURCE/name/'clip_manifest.json').is_file(), f'Missing manifest: {SOURCE/name}/clip_manifest.json')
    if args.validate_only or args.preview_only:
        for name in names:
            data, clips, pictures, asset_icons, _, _ = load_manifest(SOURCE/name/'clip_manifest.json')
            print(f"Validated {name}: {len(clips)} clips, {len(pictures)} PNG frames, {len(asset_icons)} icons")
        if args.preview_only:
            package.mkdir(parents=True,exist_ok=True)
            write_viewer(package,names)
            print(f'Preview only (native assets were not recompiled): {package / ("review_"+package_revision()+".html")}')
        return
    standalone = (SOURCE/'runtime').is_dir() or (SOURCE/'portable_manifest.json').is_file()
    if args.reuse_compiled or (standalone and not args.recompile):
        # Load/validate manifests before the cached-resource hash check, so
        # malformed or path-escaping source entries never reach the viewer.
        for name in names:
            load_manifest(SOURCE/name/'clip_manifest.json')
        result = reuse_compiled(package,names)
        result['status'] = 'verified_precompiled_repack'
        result['native_recompiled_this_run'] = False
        result['art_revision'] = package_revision()
        (package/'validation/report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
        write_viewer(package,names)
        bundle = write_bundle(package,names,result['assets'],result['inventory'])
        print('Verified supplied native assets; no compiler or game installation used.')
        print(f'Preview: {package / ("review_"+package_revision()+".html")}')
        print(f'Bundle: {bundle}')
        return
    check_toolchain(args.tools)
    reports, icons = [], {}
    for name in names:
        manifest = SOURCE / name / "clip_manifest.json"
        require(manifest.is_file(), f"missing manifest: {manifest}")
        report, asset_icons = compile_bank(manifest, package, args.tools)
        require(not set(icons).intersection(asset_icons), "duplicate inventory element names")
        icons.update(asset_icons)
        reports.append(report)
        print(f"Compiled {name}: {len(report['clips'])} clips; {report['compiled_archive']['atlas_count']} atlas page(s)")
    inventory = inventory_atlas(icons, package, args.tools)
    result = {"status": "compiled_and_structurally_validated", "installed": False,
              "art_revision": package_revision(),
              "native_recompiled_this_run": True,
              "runtime_gameplay_validation": "not performed; art-only staged package",
              "assets": reports, "inventory": inventory}
    (package / "validation/report.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf8")
    write_viewer(package, names)
    bundle = write_bundle(package, names, reports, inventory)
    print(f"Standalone package: {package}")
    print(f"All art bundle: {bundle}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError,OSError) as error:
        raise SystemExit(f'Error: {error}')
