"""Render the compiled-source sprites at runtime timing for offline visual review.

This is an asset/motion review, not a screenshot of the DST renderer.
"""
import math
from functools import lru_cache

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

from build_elemental_flight import DISPLAY_SIZES, ROOT, RUNTIME, BANK

OUT = ROOT / 'docs/previews/elemental-v1'
BG = (26, 32, 35, 255)
INK = (229, 230, 224, 255)
FONT = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 20)
SMALL = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 14)
ART = {(kind, group, frame): Image.open(RUNTIME / BANK / f'{kind}_{group}_{frame}.png').convert('RGBA')
       for kind in ('fire', 'frost') for group in ('head', 'tail', 'hit') for frame in range(6)}
LUA = LuaRuntime(unpack_returned_tuples=True)
FLIGHT = LUA.execute((ROOT / 'mod/scripts/nw/elemental_flight.lua').read_text(encoding='utf8'))


@lru_cache(maxsize=None)
def trail_timing(scale):
    """Read the real runtime policy rather than maintaining a Python copy."""
    return FLIGHT.trail_timing(scale)


def stamp(canvas, kind, group, frame, position, heading=0, scale=1):
    size = tuple(max(1, round(v * scale)) for v in DISPLAY_SIZES[kind][group])
    sprite = ART[kind, group, frame].resize(size, Image.Resampling.LANCZOS)
    # Both the runtime bank and this review quantize to 32 in-plane directions.
    direction = round(heading / math.tau * 32) % 32
    sprite = sprite.rotate(-direction * 360 / 32, Image.Resampling.BICUBIC, expand=True)
    x, y = position
    canvas.alpha_composite(sprite, (round(x - sprite.width / 2), round(y - sprite.height / 2)))


def contact_sheet():
    canvas = Image.new('RGBA', (960, 600), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((28, 18), 'FIRE / FROST - runtime sprite review', font=FONT, fill=INK)
    draw.text((28, 48), '6 frames / 30 fps / 0.20 s | shared pivots, independent world-space trails', font=SMALL, fill=INK)
    for row, kind in enumerate(('fire', 'frost')):
        top = 85 + row * 250
        draw.text((28, top), kind.upper(), font=FONT, fill=(255, 183, 105) if kind == 'fire' else (140, 221, 240))
        for frame in range(6):
            x = 120 + frame * 144
            stamp(canvas, kind, 'head', frame, (x, top + 65), scale=1)
            draw.text((x - 20, top + 118), f'{round(frame / 30 * 1000)} ms', font=SMALL, fill=INK)
        draw.text((28, top + 158), 'TRAIL', font=SMALL, fill=INK)
        draw.text((480, top + 158), 'CONTACT', font=SMALL, fill=INK)
        for index, frame in enumerate((0, 2, 4)):
            stamp(canvas, kind, 'tail', frame, (135 + index * 130, top + 185))
            stamp(canvas, kind, 'hit', frame, (575 + index * 140, top + 185), scale=.75)
    canvas.convert('RGB').save(OUT / 'frames.png')


def path(age, curved):
    if not curved:
        return 92 + 245 * age, 145, 245, 0
    angle = math.pi + age * math.pi / 1.8
    return 240 + 135 * math.cos(angle), 318 + 50 * math.sin(angle), -135 * math.sin(angle) * math.pi / 1.8, 50 * math.cos(angle) * math.pi / 1.8


def review_palette():
    # A shared palette avoids GIF quantization shimmer on still backgrounds.
    palette_source = Image.new('RGB', (96 * 6, 96 * 2), BG[:3])
    for row, kind in enumerate(('fire', 'frost')):
        for frame in range(6):
            sprite = ART[kind, 'head', frame]
            palette_source.paste(sprite, (frame * 96, row * 96), sprite)
    return palette_source.quantize(colors=255)


def motion_review():
    frames = []
    palette = review_palette()
    trail_life, interval = trail_timing(1)
    for step in range(72):
        now = step / 30
        canvas = Image.new('RGBA', (960, 415), BG)
        draw = ImageDraw.Draw(canvas)
        draw.line((480, 15, 480, 397), fill=(65, 78, 83), width=1)
        for column, kind in enumerate(('fire', 'frost')):
            origin = column * 480
            draw.text((origin + 26, 18), kind.upper(), font=FONT, fill=INK)
            text = 'Embers: 12% birth velocity' if kind == 'fire' else 'Ice chips: remain at birth position'
            draw.text((origin + 26, 48), text, font=SMALL, fill=INK)
            draw.text((origin + 26, 80), 'Straight flight / contact', font=SMALL, fill=INK)
            draw.text((origin + 26, 218), 'Turning / old particles retain their direction', font=SMALL, fill=INK)
            for curved in (False, True):
                lifetime = 1.8 if curved else 1.15
                drift = .12 if kind == 'fire' else 0
                offset = (.24 if kind == 'fire' else .20) * 20
                for birth_index in range(1, math.floor(min(now, lifetime) / interval) + 1):
                    born = birth_index * interval
                    age = now - born
                    if age < 0 or age >= trail_life:
                        continue
                    x, y, vx, vy = path(born, curved)
                    speed = math.hypot(vx, vy)
                    x += drift * vx * age - offset * vx / speed
                    y += drift * vy * age - offset * vy / speed
                    stamp(canvas, kind, 'tail', min(5, int(age / trail_life * 6)), (origin + x, y), math.atan2(vy, vx), .65)
                x, y, vx, vy = path(min(now, lifetime), curved)
                heading = math.atan2(vy, vx)
                if now < lifetime:
                    stamp(canvas, kind, 'head', (int(now * 30) + column * 2) % 6, (origin + x, y), heading, .65)
                elif now < lifetime + .2:
                    stamp(canvas, kind, 'hit', min(5, int((now - lifetime) * 30)), (origin + x, y), heading, .65)
        draw.text((26, 390), 'Offline asset preview; enlarged. Gameplay damage and lifetime are unchanged.', font=SMALL, fill=(158, 174, 178))
        frames.append(canvas.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE))
    frames[0].save(OUT / 'flight.gif', save_all=True, append_images=frames[1:],
                   duration=[30, 30, 40] * 24, loop=0, disposal=2, optimize=False)


def giant_review_frame(now):
    """Same camera scale and path for all rows; only giant size/timing change."""
    canvas = Image.new('RGBA', (1200, 870), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 17), 'GIANT TRAILS - same camera scale, movement speed and contact time', font=FONT, fill=INK)
    draw.text((24, 48), f'Runtime timing from Lua | contact at 1.10 s | current time {now:.2f} s', font=SMALL, fill=INK)
    draw.text((24, 80), 'FIRE: embers drift at 12% of birth velocity', font=SMALL, fill=(255, 183, 105))
    draw.text((624, 80), 'FROST: ice chips remain at birth position', font=SMALL, fill=(140, 221, 240))
    draw.line((600, 74, 600, 820), fill=(65, 78, 83))
    contact = 1.1
    camera_scale = .2

    def position(age, center):
        phase = age / contact * math.tau
        return 94 + 310 * age, center + 18 * math.sin(phase), 310, 18 * math.tau / contact * math.cos(phase)

    for row, giant in enumerate((1, 2.5, 5, 7.5)):
        top = 112 + row * 175
        center = top + 98
        trail_life, interval = trail_timing(giant)
        draw.line((24, top - 8, 1176, top - 8), fill=(47, 60, 65))
        for column, kind in enumerate(('fire', 'frost')):
            origin = column * 600
            draw.text((origin + 24, top), f'x{giant:g}   |   {trail_life:.2f} s   |   {1 / interval:.1f} segments/s', font=SMALL, fill=INK)
            drift = .12 if kind == 'fire' else 0
            offset = (.24 if kind == 'fire' else .20) * 30 * giant
            for birth_index in range(1, math.floor(min(now, contact) / interval) + 1):
                born = birth_index * interval
                age = now - born
                if not 0 <= age < trail_life:
                    continue
                x, y, vx, vy = position(born, center)
                speed = math.hypot(vx, vy)
                x += drift * vx * age - offset * vx / speed
                y += drift * vy * age - offset * vy / speed
                stamp(canvas, kind, 'tail', min(5, int(age / trail_life * 6)), (origin + x, y),
                      math.atan2(vy, vx), camera_scale * giant)
            x, y, vx, vy = position(min(now, contact), center)
            heading = math.atan2(vy, vx)
            if now < contact:
                stamp(canvas, kind, 'head', (int(now * 30) + column * 2) % 6, (origin + x, y), heading, camera_scale * giant)
            elif now < contact + .2:
                hit_scale = .85 if kind == 'fire' else .7
                stamp(canvas, kind, 'hit', min(5, int((now - contact) * 30)), (origin + x, y), heading,
                      camera_scale * giant * hit_scale)
    draw.text((24, 837), 'Offline sprite review, not a game capture. Head/contact animation timing stays at 0.20 s.', font=SMALL, fill=(158, 174, 178))
    return canvas


def giant_motion_review():
    palette = review_palette()
    frames = [giant_review_frame(step / 30).convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE)
              for step in range(63)]
    frames[0].save(OUT / 'giant-trails.gif', save_all=True, append_images=frames[1:],
                   duration=[30, 30, 40] * 21, loop=0, disposal=2, optimize=False)
    giant_review_frame(.8).convert('RGB').save(OUT / 'giant-trails.png')
    giant_review_frame(1.4).convert('RGB').save(OUT / 'giant-trails-after-contact.png')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    contact_sheet()
    motion_review()
    giant_motion_review()
    print(OUT)
