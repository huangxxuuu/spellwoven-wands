"""Create source-only alpha and neutral background QA; no runtime assets changed."""
import json
from pathlib import Path

from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent
source = Image.open(root / 'source-01.png').convert('RGBA')
alpha = source.getchannel('A')
hist = alpha.histogram()
rows = []
active = None
for y in range(source.height):
    occupied = alpha.crop((0, y, source.width, y + 1)).getbbox() is not None
    if occupied and active is None:
        active = y
    if active is not None and (not occupied or y == source.height - 1):
        end = y if not occupied else y + 1
        local = alpha.crop((0, active, source.width, end)).getbbox()
        rows.append([local[0], active, local[2], end])
        active = None
report = {
    'source': str(root / 'source-01.png'),
    'size': list(source.size),
    'mode': source.mode,
    'alpha_bbox': list(alpha.getbbox()),
    'alpha_zero_pixels': hist[0],
    'alpha_partial_pixels': sum(hist[1:255]),
    'alpha_opaque_pixels': hist[255],
    'occupied_row_groups_xyxy_exclusive': rows,
}
(root / 'alpha-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
preview = Image.new('RGB', (source.width * 3, source.height), 'white')
for index, color in enumerate(((255, 255, 255), (126, 126, 126), (38, 42, 47))):
    bg = Image.new('RGBA', source.size, color + (255,))
    bg.alpha_composite(source)
    preview.paste(bg.convert('RGB'), (index * source.width, 0))
preview.save(root / 'qa-white-gray-dark.png')
preview.resize((1536, 512), Image.Resampling.LANCZOS).save(root / 'qa-white-gray-dark-small.png')
print(json.dumps(report, ensure_ascii=False, indent=2))
