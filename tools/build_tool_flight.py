"""Compile native tool cutouts and the orange orb into an isolated flight bank."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from xml.etree import ElementTree as ET
from PIL import Image
from build_art_assets import ROOT, RUNTIME, compile_bank, frame
from native_animation import NativeAnimation

BANK = 'nw_tool_flight'
SOURCE = ROOT / 'assets_src/projectiles/tools_v1'
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
DIRECTIONS = 128
FPS = 30
# Authored points on the original high resolution tool, not bounding-box pivots.
TOOLS = {
    'fishingrod': {'bank': 'fishingrod', 'symbol': 'fishingrod01',
                   'pivot': (78, 133), 'rear': (49, 246), 'tip': (113, 9), 'length': 180},
    'trident': {'bank': 'trident', 'symbol': 'trident_1',
                'pivot': (51, 128), 'rear': (18, 16), 'tip': (103, 263), 'length': 180},
    'farm_hoe': {'bank': 'quagmire_hoe', 'symbol': 'hoe01',
                 'pivot': (38, 143), 'rear': (43, 234), 'tip': (38, 54), 'length': 180},
    'yoth_lance': {'bank': 'yoth_lance', 'symbol': 'swap_lance',
                   'pivot': (48, 304), 'rear': (49, 594), 'tip': (46, 6), 'length': 250},
}
ORANGE_PIVOTS = ((244, 220), (240, 220), (236, 220), (250, 205), (244, 205), (240, 205))
TAIL_PIVOTS = ((375, 365), (360, 365), (343, 365))
TAIL_EXTENTS = ((768, 768), (724, 768), (714, 768))


def extract_native():
    """Explicit rebuild option; routine compiles use the checked-in source PNGs."""
    SOURCE.mkdir(parents=True, exist_ok=True)
    report = {}
    for key, spec in TOOLS.items():
        native = NativeAnimation(spec['bank'])
        image, origin = native.symbol(spec['symbol'], 0)
        image.save(SOURCE / (key + '-native.png'))
        report[key] = {'archive': 'anim/' + spec['bank'] + '.zip', 'build': native.build['name'],
                       'symbol': spec['symbol'], 'frame': 0, 'native_top_left': origin, 'pixels': image.size}
    report['oceanfishingrod'] = extract_ocean_hook()
    (SOURCE / 'native-sources.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')


def extract_ocean_hook():
    """Keep the actual native hook and animated line in the project sources."""
    SOURCE.mkdir(parents=True, exist_ok=True)
    native = NativeAnimation('oceanfishing_hook')
    report = {'archive': 'anim/oceanfishing_hook.zip', 'build': native.build['name'], 'symbols': {}}
    for symbol, count in (('hook', 1), ('line_loop', 8)):
        for index in range(count):
            image, origin = native.symbol(symbol, index)
            name = f'oceanfishingrod-{symbol}-{index}.png'
            image.save(SOURCE / name)
            report['symbols'][name] = {'symbol': symbol, 'frame': index, 'native_top_left': origin, 'pixels': image.size}
    return report


def ocean_hook_sprites():
    # The old spin_loop is a screen-fixed casting pose, not a directional
    # projectile. Put the native hook at the contact anchor, with its eye
    # behind it, and attach each native line pose to that same eye.
    hook = Image.open(SOURCE / 'oceanfishingrod-hook-0.png').convert('RGBA')
    sprites = []
    for index in range(8):
        line = Image.open(SOURCE / f'oceanfishingrod-line_loop-{index}.png').convert('RGBA')
        alpha = line.getchannel('A')
        bottom = alpha.point(lambda a: 255 if a > 32 else 0).getbbox()[3]-1
        points = [(x, y, alpha.getpixel((x, y))) for y in range(max(0, bottom-2), bottom+1)
                  for x in range(line.width) if alpha.getpixel((x, y)) > 32]
        endpoint_x = sum(x*a for x, _, a in points)/sum(a for _, _, a in points)
        endpoint_y = sum(y*a for _, y, a in points)/sum(a for _, _, a in points)
        # Rotate the long line axis into -X. Its moving endpoint stays pinned
        # to the hook eye instead of letting the complete hook sway sideways.
        rotated = line.transpose(Image.Transpose.ROTATE_90)
        sprite = Image.new('RGBA', (512, 192))
        eye_x, eye_y = 256-51, 96+10
        sprite.alpha_composite(rotated, (round(eye_x-endpoint_y), round(eye_y-(line.width-1-endpoint_x))))
        sprite.alpha_composite(hook, (256-67, 96-34))
        sprites.append(sprite)
    return sprites


def orient_tool(image, spec):
    px, py = spec['pivot']
    dx, dy = spec['tip'][0] - spec['rear'][0], spec['tip'][1] - spec['rear'][1]
    distance = math.hypot(dx, dy)
    c, s = dx / distance, dy / distance
    flip = -1 if spec.get('flip') else 1
    extent = math.ceil(max(math.hypot(x - px, y - py)
                          for x in (0, image.width) for y in (0, image.height))) + 4
    pixels = 256
    step = extent * 2 / pixels
    # Output +X points towards the tip; the collision anchor stays at centre.
    transform = (c * step, -s * flip * step, px - pixels / 2 * step * (c - s * flip),
                 s * step, c * flip * step, py - pixels / 2 * step * (s + c * flip))
    sprite = image.transform((pixels, pixels), Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC)
    bbox = sprite.getchannel('A').point(lambda a: 255 if a > 14 else 0).getbbox()
    scale = spec['length'] / (bbox[2] - bbox[0])
    return sprite, (pixels * scale, pixels * scale)


def registered(cell, pivot, extent, pixels):
    # The same fixed source-coordinate extent is used for every pose.
    px, py = pivot
    ex, ey = (extent, extent) if isinstance(extent, (int, float)) else extent
    return cell.transform((pixels, pixels), Image.Transform.AFFINE,
                          (ex / pixels, 0, px - ex / 2, 0, ey / pixels, py - ey / 2), Image.Resampling.BICUBIC)


def direction_transform(kind, group, angle, sx, sy):
    c, s = math.cos(angle), math.sin(angle)
    if kind == 'farm_hoe' and group == 'head' and c < -1e-9: sy = -sy
    return c * sx, s * sx, -s * sy, c * sy


def make_bank():
    build, animations = ET.Element('Build', name=BANK), ET.Element('Anims')
    images, groups = {}, {}
    for key, spec in TOOLS.items():
        image = Image.open(SOURCE / (key + '-native.png')).convert('RGBA')
        sprite, display = orient_tool(image, spec)
        groups[key] = {'head': {'sprites': [sprite], 'display_size': display}}
    groups['oceanfishingrod'] = {'head': {'sprites': ocean_hook_sprites(), 'display_size': (640, 240)}}
    atlas = Image.open(SOURCE / 'orange_bolt-atlas.png').convert('RGBA')
    cells = [atlas.crop((round(i % 3 * atlas.width / 3), round(i // 3 * atlas.height / 3),
                         round((i % 3 + 1) * atlas.width / 3), round((i // 3 + 1) * atlas.height / 3)))
             for i in range(9)]
    heads = [registered(cell, pivot, 512, 128) for cell, pivot in zip(cells[:6], ORANGE_PIVOTS)]
    strip = Image.open(SOURCE / 'orange_bolt-tail-v2.png').convert('RGBA')
    tail_cells = [strip.crop((round(i * strip.width / 3), 0, round((i + 1) * strip.width / 3), strip.height))
                  for i in range(3)]
    tails = []
    for index, opacity in zip((0, 0, 1, 1, 2, 2), (1, .94, .78, .60, .35, .08)):
        tail = registered(tail_cells[index], TAIL_PIVOTS[index], TAIL_EXTENTS[index], 96)
        tail.putalpha(tail.getchannel('A').point(lambda a: round(a * opacity)))
        tails.append(tail)
    groups['orange_bolt'] = {'head': {'sprites': heads, 'display_size': (160, 160)},
                             'tail': {'sprites': tails, 'display_size': (56, 220)}}
    manifest = {'bank': BANK, 'directions': DIRECTIONS, 'fps': FPS, 'kinds': {}}
    for kind, entries in groups.items():
        record = manifest['kinds'][kind] = {'directions': DIRECTIONS, 'groups': {}}
        for group, info in entries.items():
            sprites, display = info['sprites'], info['display_size']
            names = []
            for i, image in enumerate(sprites):
                name = f'{kind}_{group}_{i:02}'
                names.append(name); images[name] = image
                frame(build, name, name, image.size)
            record['groups'][group] = {'frames': len(sprites), 'period': len(sprites) / FPS,
                                       'display_size': display, 'pixels': sprites[0].size,
                                       'orientation': 'upright_left' if kind == 'farm_hoe' else 'directional',
                                       'symbols': names}
            for direction in range(DIRECTIONS):
                prefix = kind + ('_tail' if group == 'tail' else '')
                clip = ET.SubElement(animations, 'anim', name=f'{prefix}_dir_{direction}', root=BANK, framerate=str(FPS))
                for name, image in zip(names, sprites):
                    a, b, c, d = direction_transform(kind, group, direction * math.tau / DIRECTIONS,
                                                      display[0] / image.width, display[1] / image.height)
                    bound = max(display) * 1.5
                    pose = ET.SubElement(clip, 'frame', x='0', y='0', w=str(bound), h=str(bound))
                    ET.SubElement(pose, 'element', name=name, frame='0', layername=name, z_index='0',
                                  m_a=str(a), m_b=str(b), m_c=str(c), m_d=str(d), m_tx='0', m_ty='0')
    manifest['images'] = len(images)
    manifest['clips'] = len(animations)
    return build, animations, images, manifest


def prepare():
    build, animations, images, manifest = make_bank()
    folder = RUNTIME / BANK
    folder.mkdir(parents=True, exist_ok=True)
    for name, image in images.items(): image.save(folder / (name + '.png'))
    ET.ElementTree(build).write(folder / 'build.xml', encoding='utf8', xml_declaration=True)
    ET.ElementTree(animations).write(folder / 'animation.xml', encoding='utf8', xml_declaration=True)
    (folder / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf8')
    return build, animations, images, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract-native', action='store_true')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    if args.extract_native: extract_native()
    build, animations, images, manifest = prepare()
    if not args.prepare_only: compile_bank(BANK, build, animations, images, MOD_TOOLS)
    print(f'{BANK}: {manifest["images"]} PNG, {manifest["clips"]} directional clips')


if __name__ == '__main__': main()
