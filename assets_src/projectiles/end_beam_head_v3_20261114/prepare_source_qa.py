"""Crop an existing connector and inspect generated stars; never draw star frames."""
from pathlib import Path
import json
from PIL import Image, ImageFilter

root = Path(__file__).resolve().parent
old = root.parent / 'end_beam_v2_20261114/source-01.png'
box = (700, 112, 900, 276)
Image.open(old).convert('RGBA').crop(box).save(root / 'connector-source.png')
(root / 'connector-source.json').write_text(json.dumps({
    'source': str(old), 'crop_xyxy_exclusive': box, 'size': [200, 164],
    'core_center_local_approx': [100, 81],
    'operation': 'Existing painted beam crop only; no new generated or procedural drawing.',
    'usage': None,
    'runtime_instruction': 'Fixed lower layer; same rendered thickness as beam. Never apply star rotation to this connector.'
}, ensure_ascii=False, indent=2), encoding='utf-8')
path = root / 'star-source-01.png'
if not path.exists():
    raise SystemExit('Connector ready. Star API result not present yet.')
im = Image.open(path).convert('RGBA')
alpha = im.getchannel('A')
hist = alpha.histogram()
rows = [0, 341, 683, 1024]
frames = []
registration = []
for index in range(12):
    col, row = index % 4, index // 4
    cell_box = (col*256, rows[row], (col+1)*256, rows[row+1])
    cell = im.crop(cell_box)
    a = cell.getchannel('A')
    bbox = a.point(lambda value: 255 if value >= 8 else 0).getbbox()
    white = [(x, y) for y in range(cell.height) for x in range(cell.width)
             if (lambda p: p[3] >= 128 and min(p[:3]) >= 220)(cell.getpixel((x, y)))]
    core = [round(sum(p[axis] for p in white)/len(white), 2) for axis in (0, 1)] if white else None
    # Locate the thick white center rather than weighting the unequal bright spikes.
    mask = Image.new('L', cell.size)
    mask.putdata([255 if p[3] >= 128 and min(p[:3]) >= 220 else 0 for p in cell.getdata()])
    inner = mask
    erosions = 0
    while True:
        trial = inner.filter(ImageFilter.MinFilter(3))
        if trial.getbbox() is None:
            break
        inner = trial
        erosions += 1
    inner_pixels = [(x,y) for y in range(cell.height) for x in range(cell.width) if inner.getpixel((x,y))]
    optical = [round(sum(p[axis] for p in inner_pixels)/len(inner_pixels), 2) for axis in (0,1)]
    global_pivot = [round(optical[0]+cell_box[0],2), round(optical[1]+cell_box[1],2)]
    safe = [max(0,bbox[0]-4)+cell_box[0], max(0,bbox[1]-4)+cell_box[1],
            min(cell.width,bbox[2]+4)+cell_box[0], min(cell.height,bbox[3]+4)+cell_box[1]]
    registration.append({'box':safe, 'pivot':global_pivot, 'frame':index+1,
                         'cell_box':cell_box, 'white_core_erosion_radius':erosions})
    frames.append({'frame': index+1, 'cell_box_xyxy_exclusive': cell_box,
                   'local_alpha8_bbox': bbox, 'white_core_centroid_local': core,
                   'global_white_core_centroid': [core[0]+cell_box[0],core[1]+cell_box[1]] if core else None,
                   'optical_white_core_pivot_global':global_pivot})
report = {'source': str(path), 'size': im.size, 'alpha_extrema': alpha.getextrema(),
          'alpha_zero': hist[0], 'alpha1': hist[1], 'alpha2': hist[2],
          'alpha8_bbox': alpha.point(lambda value: 255 if value >= 8 else 0).getbbox(), 'frames': frames}
(root / 'star-alpha-and-centers.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
(root / 'registration.json').write_text(json.dumps({
    'source':'star-source-01.png', 'coordinate_space':'source image global pixels; box xyxy right/bottom exclusive',
    'pivot_method':'Centroid of deepest eroded white core (RGB channels >=220, alpha>=128); excludes asymmetric white spike lengths.',
    'runtime_instruction':'Translate each pivot to a common anchor; use one common scale; preserve drawn breathing. Do not rotate the lower connector.',
    'frames':registration}, ensure_ascii=False, indent=2), encoding='utf-8')
board = Image.new('RGB', (3072, 1024))
for i, color in enumerate(((255,255,255),(126,126,126),(38,42,47))):
    bg = Image.new('RGBA', im.size, color+(255,))
    bg.alpha_composite(im)
    board.paste(bg.convert('RGB'), (1024*i, 0))
board.save(root / 'star-qa-white-gray-dark.png')
board.resize((1536,512), Image.Resampling.LANCZOS).save(root / 'star-qa-white-gray-dark-small.png')
print(json.dumps(report, ensure_ascii=False, indent=2))
