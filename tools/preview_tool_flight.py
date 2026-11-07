"""Offline native-tool orientation, giant-size and orange trail review."""
from __future__ import annotations
import math
from PIL import Image, ImageDraw, ImageFont, ImageOps
from build_art_assets import ROOT
from build_tool_flight import make_bank
from native_animation import NativeAnimation

OUT = ROOT / 'test_reports/tool-flight'
BACKGROUND = (43, 37, 32, 255)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    _, _, images, manifest = make_bank()
    font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 22)

    def sprite(kind, group='head', index=0, angle=0, scale=1):
        info = manifest['kinds'][kind]['groups'][group]
        image = images[info['symbols'][index % info['frames']]]
        width, height = info['display_size']
        image = image.resize((round(width * scale), round(height * scale)), Image.Resampling.LANCZOS)
        if info['orientation'] == 'upright_left' and math.cos(angle) < -1e-9:
            image = ImageOps.flip(image)
        return image.rotate(-math.degrees(angle), Image.Resampling.BICUBIC, expand=True)

    def paste(canvas, image, x, y):
        canvas.alpha_composite(image, (round(x - image.width / 2), round(y - image.height / 2)))

    for scale, name in ((1, 'normal'), (2.5, 'giant')):
        cell_width, row_height = (460, 210) if scale == 1 else (840, 420)
        canvas = Image.new('RGBA', (cell_width * 2, row_height * len(manifest['kinds']) + 60), BACKGROUND)
        draw = ImageDraw.Draw(canvas)
        draw.text((18, 12), f'Native tool flight  {scale:g}x | right / left', font=font, fill='white')
        for row, kind in enumerate(manifest['kinds']):
            y = 60 + row_height * row + row_height / 2
            draw.text((12, 60 + row_height * row), kind, font=font, fill=(200, 197, 179))
            for column, angle in enumerate((0, math.pi)):
                x = cell_width * column + cell_width / 2
                if kind == 'orange_bolt':
                    for k in range(8, -1, -1):
                        distance = (.28 + k * .14) * 150 * scale
                        paste(canvas, sprite(kind, 'tail', min(5, k // 2), angle, scale),
                              x - math.cos(angle) * distance, y - math.sin(angle) * distance)
                paste(canvas, sprite(kind, angle=angle, scale=scale), x, y)
        canvas.convert('RGB').save(OUT / (name + '-left-right.png'))

    frames = []
    for tick in range(60):
        canvas = Image.new('RGBA', (1100, 600), BACKGROUND)
        draw = ImageDraw.Draw(canvas)
        draw.text((18, 14), 'Orange orb: short connected segments / 1x and 2.5x', font=font, fill='white')
        for scale, cy in ((1, 190), (2.5, 420)):
            angle = tick / 60 * math.tau
            radius = 220
            x, y = 600 + radius * math.cos(angle), cy + 45 * math.sin(angle)
            for k in range(20, -1, -1):
                old = angle - k * .04 * scale
                px, py = 600 + radius * math.cos(old), cy + 45 * math.sin(old)
                heading = math.atan2(45 * math.cos(old), -radius * math.sin(old))
                age = k / 20
                paste(canvas, sprite('orange_bolt', 'tail', min(5, int(age * 6)), heading, scale), px, py)
            heading = math.atan2(45 * math.cos(angle), -radius * math.sin(angle))
            paste(canvas, sprite('orange_bolt', index=tick, angle=heading, scale=scale), x, y)
        frames.append(canvas.convert('RGB'))
    frames[0].save(OUT / 'orange-turn.gif', save_all=True, append_images=frames[1:], duration=33, loop=0)

    banks = ('dumbbell', 'dumbbell_golden', 'dumbbell_marble', 'dumbbell_gem',
             'dumbbell_heat', 'dumbbell_redgem', 'dumbbell_bluegem')
    canvas = Image.new('RGBA', (1000, 7 * 170), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    for row, bank in enumerate(banks):
        native = NativeAnimation(bank)
        draw.text((10, row * 170 + 3), bank + ' native land', font=font, fill='white')
        for column, index in enumerate((0, 7, 14, 20)):
            image, origin = native.render_frame('land', index)
            image = ImageOps.contain(image, (210, 130), Image.Resampling.LANCZOS)
            paste(canvas, image, column * 250 + 125, row * 170 + 100)
    canvas.convert('RGB').save(OUT / 'native-land-stages.png')
    print(OUT)


if __name__ == '__main__': main()
