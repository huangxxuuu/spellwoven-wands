"""Extract installed DST references and review the compiled material footprints."""
from io import BytesIO
import hashlib
import json
from pathlib import Path
import zipfile
from xml.etree import ElementTree as ET

from PIL import Image, ImageDraw, ImageFont
import resvg_py
from native_animation import GAME, NativeAnimation, read_build, read_animation, texture

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'test_reports/material_ground_shadows'
OUT.mkdir(parents=True, exist_ok=True)
PARTS = ROOT / 'assets_src/supplies/ground_shadows'
PARTS.mkdir(parents=True, exist_ok=True)
SPECS = [('hounds_tooth', 'idle'), ('halloween_potions', 'bravery_large'),
         ('halloween_potions', 'sanity_large'), ('halloween_potions', 'health_small')]
MATERIALS = [('nw_dust', '奥术粉尘'), ('nw_beast_core', '野兽核心'),
             ('nw_overlord_core', '霸主核心'), ('nw_blank', '空白法术卡')]
font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
small = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 14)
sheet = Image.new('RGB', (1120, 810), '#ac9b78')
draw = ImageDraw.Draw(sheet)
manifest = {'game': str(GAME), 'native': [], 'materials': [],
            'preview': 'Decoded compiled frames; no in-game lighting or camera projection.'}
draw.text((20, 10), '原版拆包：主体与地影位于同一 symbol', font=font, fill='#211b20')
for i, (bank, clip) in enumerate(SPECS):
    native = NativeAnimation(bank)
    im, origin = native.render_frame(clip)
    im.save(OUT / f'{bank}_{clip}.png')
    e = native.clip(clip)['frames'][0]['elements'][0]
    symbol, pivot = native.symbol(e[0], e[1])
    symbol.save(OUT / f'{bank}_{clip}_symbol.png')
    scale = min(160 / im.height, 220 / im.width)
    thumb = im.resize((round(im.width * scale), round(im.height * scale)), Image.Resampling.LANCZOS)
    sheet.paste(thumb, (i * 280 + (280-thumb.width)//2, 210-thumb.height), thumb)
    draw.text((i*280+28, 219), f'{bank}\n{clip}  ({scale:.2f}×)', font=small, fill='#211b20')
    manifest['native'].append({'archive': str(GAME/'data/anim'/f'{bank}.zip'),
                              'clip': clip, 'origin': origin, 'symbol': native.build['names'][e[0]],
                              'element': e, 'symbol_origin': pivot,
                              'layer_count': len(native.clip(clip)['frames'][0]['elements'])})

native = NativeAnimation.__new__(NativeAnimation)
with zipfile.ZipFile(ROOT/'mod/anim/nw_supplies.zip') as archive:
    native.build = read_build(archive.read('build.bin'))
    native.clips = read_animation(archive.read('anim.bin'))
    native.atlases = [texture(archive.read(p)) for p in native.build['atlases']]
native.cache = {}
draw.text((20, 278), '本次编译成品：1× / 2×；主体原尺寸、原落点', font=font, fill='#211b20')
for i, (name, label) in enumerate(MATERIALS):
    im, origin = native.render_frame(name)
    im.save(OUT / f'{name}_compiled.png')
    for scale, base in [(1, 462), (2, 770)]:
        thumb = im.resize((im.width*scale, im.height*scale), Image.Resampling.NEAREST)
        # Keep the same ground y=0 across all columns.
        sheet.paste(thumb, (i*280+140+origin[0]*scale, base+origin[1]*scale), thumb)
    draw.text((i*280+80, 310), label, font=font, fill='#211b20')
    source = ET.parse(ROOT/'assets_src/supplies'/f'{name}.svg').getroot()
    for child in list(source):
        if child.get('id') != 'ground-shadow': source.remove(child)
    shadow = Image.open(BytesIO(resvg_py.svg_to_bytes(svg_string=ET.tostring(source, encoding='unicode'))))
    shadow.save(PARTS/f'{name}_shadow.png')
    before = OUT/'before'/f'{name}.svg'
    if before.exists():
        source = ET.parse(ROOT/'assets_src/supplies'/f'{name}.svg').getroot()
        source.remove(next(c for c in source if c.get('id') == 'ground-shadow'))
        source.attrib.update(viewBox='0 0 64 64', width='128', height='128')
        body = Image.open(BytesIO(resvg_py.svg_to_bytes(svg_string=ET.tostring(source, encoding='unicode'))))
        old = Image.open(BytesIO(resvg_py.svg_to_bytes(svg_path=str(before))))
        assert body.tobytes() == old.tobytes(), name+' body changed'
    bbox = im.getchannel('A').getbbox()
    original = Image.open(ROOT/'assets_src/art_v1/runtime/nw_supplies'/f'{name}.png')
    source_box = original.getchannel('A').getbbox()
    assert source_box[0] > 0 and source_box[1] > 0 and source_box[2] < 144 and source_box[3] < 144, name+' clipped source'
    # The compiler trims transparent blocks. Compare in animation coordinates,
    # not against the trimmed rectangle's edge (which may touch visible ink).
    expected_box = tuple(v + (-72 if j%2 == 0 else -124) for j, v in enumerate(source_box))
    compiled_box = tuple(v + origin[j%2] for j, v in enumerate(bbox))
    assert all(abs(a-b) <= 1 for a,b in zip(expected_box, compiled_box)), name+' compiled footprint changed'
    manifest['materials'].append({'name': name, 'origin': origin, 'size': im.size,
                                  'alpha_bounds': bbox, 'body_unchanged': before.exists()})
hashes = OUT/'before/inventory_hashes.json'
if hashes.exists():
    for path, expected in json.loads(hashes.read_text()).items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == expected, path+' changed'
    manifest['inventory_binary_unchanged'] = True
manifest['full_game_tests'] = 'not run'
sheet.save(OUT/'compiled_comparison.png')
(OUT/'verification.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')
print('PASS: compiled frames, unclipped footprints, unchanged bodies and inventory resources')
print(OUT/'compiled_comparison.png')
