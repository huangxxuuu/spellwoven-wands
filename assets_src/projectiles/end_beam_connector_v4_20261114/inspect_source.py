"""Inspect generated alpha and make neutral-background QA; no sprite edits."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).parent
image = Image.open(root / 'connector-source-01.png').convert('RGBA')
alpha = image.getchannel('A')
bounds = {}
for cutoff in (0, 2, 8, 32, 128, 240):
    bounds[str(cutoff)] = alpha.point(lambda a: 255 if a > cutoff else 0).getbbox()
hist = alpha.histogram()
left, top, right, bottom = bounds['8']
columns = []
for fraction in (0.02, 0.1, 0.2, 0.4, 0.6, 0.8, 0.95, 0.99):
    x = left + round((right-left-1)*fraction)
    ys = [y for y in range(image.height) if alpha.getpixel((x, y)) > 32]
    columns.append({'x': x, 'fraction_of_bbox_width': fraction,
                    'top': min(ys) if ys else None,
                    'bottom_inclusive': max(ys) if ys else None,
                    'height': max(ys)-min(ys)+1 if ys else 0,
                    'center_y': (max(ys)+min(ys))/2 if ys else None})
rgb_hist = image.convert('RGB').quantize(colors=12).convert('RGB').getcolors(image.width*image.height)
data = {'size': image.size, 'mode': image.mode, 'alpha_extrema': alpha.getextrema(),
        'alpha_zero_pixels': hist[0], 'alpha_255_pixels': hist[255],
        'alpha_partial_pixels': sum(hist[1:255]), 'bbox_by_alpha_greater_than': bounds,
        'columns': columns,
        'note': 'Coordinates refer to original source; bbox xyxy right/bottom exclusive. No runtime validation.'}
(root/'alpha-and-geometry.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
cut = image.crop((max(0,left-16), max(0,top-16), min(image.width,right+16), min(image.height,bottom+16)))
cut.thumbnail((900, 450), Image.Resampling.LANCZOS)
board = Image.new('RGB', (940, (cut.height+44)*3), '#ffffff')
draw = ImageDraw.Draw(board)
for row, color in enumerate(('#ffffff', '#808080', '#353d37')):
    y = row*(cut.height+44)
    board.paste(color, (0,y,940,y+cut.height+44))
    board.paste(cut, (20,y+28), cut)
    draw.text((20,y+8), color, fill='#111111' if row<2 else '#ffffff')
board.save(root/'qa-white-gray-dark.png')
print(json.dumps(data, ensure_ascii=False))
