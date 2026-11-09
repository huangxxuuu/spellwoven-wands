"""Cut fixed registration cells; no per-pose fit, scale, warp or recentering."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

BASE = Path(__file__).resolve().parent
SOURCE = BASE / 'originals/r2_extinguish.png'
LAYERS = BASE / 'layers'
PREVIEWS = BASE / 'previews'
sheet = Image.open(SOURCE).convert('RGBA')
# Identical source-cell size and identical resize for every drawing.
CELL = (397, 496)
CANVAS = (128, 160)
ANCHOR = (65, 143)
SOURCE_ANCHOR = (201, 444)
CELL_SCALE = 160 / 496
frames = []
records = []
for index in range(8):
    x = round(index % 4 * sheet.width / 4)
    y = round(index // 4 * sheet.height / 2)
    cell = sheet.crop((x, y, x + CELL[0], y + CELL[1]))
    alpha = cell.getchannel('A').point(lambda v: 0 if v <= 8 else v)
    cell.putalpha(alpha)
    # The same 397x496 -> 128x160 operation for all frames; shape, internal
    # positions, gaps and upward movement all come from the generated drawing.
    output = cell.resize(CANVAS, Image.Resampling.LANCZOS)
    path = LAYERS / ('r2_extinguish_%02d.png' % index)
    output.save(path)
    frames.append(output)
    a = np.asarray(output.getchannel('A'))
    rows,cols = np.where(a > 40)
    bounds = output.getchannel('A').point(lambda v:255 if v>40 else 0).getbbox()
    records.append({'index':index,'path':str(path.relative_to(BASE)),
                    'source_cell':[x,y,x+CELL[0],y+CELL[1]],
                    'alpha_bounds':list(bounds), 'occupied_pixels':int((a>40).sum()),
                    'bottom':bounds[3], 'centroid':[round(float(cols.mean()),2),round(float(rows.mean()),2)]})
blank = Image.new('RGBA',CANVAS)
blank.save(LAYERS/'r2_extinguish_08.png')
frames.append(blank)
records.append({'index':8,'path':'layers/r2_extinguish_08.png','transparent_terminal_frame':True})

board = Image.new('RGBA',(128*8,200),'#77766f')
for i,im in enumerate(frames[:-1]):
    board.alpha_composite(im,(128*i,30))
    ImageDraw.Draw(board).text((128*i+10,8),str(i),fill='white')
board.convert('RGB').save(PREVIEWS/'r2_extinguish_contact.png')

def opaque(im, background='#77766f'):
    out = Image.new('RGBA',im.size,background)
    out.alpha_composite(im)
    return out.convert('RGB')

review = [opaque(im) for im in frames]
review[0].save(PREVIEWS/'r2_extinguish_flame.gif',save_all=True,
               append_images=review[1:],duration=[400]+[70]*7+[700],loop=0,disposal=2)

# Context-only review reuses the existing body and dust; no production frame
# or build script is changed by this export task.
body = Image.open(LAYERS/'body.png').convert('RGBA')
dust = Image.open(LAYERS/'fuel_half.png').convert('RGBA')
shadow = Image.open(LAYERS/'ground_shadow.png').convert('RGBA')
WORLD_SCALE = .42
WORLD_ROOT = (174,194)
world_size = (round(CANVAS[0]*WORLD_SCALE),round(CANVAS[1]*WORLD_SCALE))
world_offset = (round(WORLD_ROOT[0]-ANCHOR[0]*WORLD_SCALE),
                round(WORLD_ROOT[1]-ANCHOR[1]*WORLD_SCALE))
worlds = []
for im in frames:
    out = shadow.copy()
    out.alpha_composite(im.resize(world_size,Image.Resampling.LANCZOS),world_offset)
    out.alpha_composite(body)
    out.alpha_composite(dust)
    worlds.append(opaque(out))
worlds[0].save(PREVIEWS/'r2_extinguish_lamp.gif',save_all=True,
               append_images=worlds[1:],duration=[400]+[70]*7+[700],loop=0,disposal=2)
context_board = Image.new('RGB',(256*8,320),'#77766f')
for i,im in enumerate(worlds[:-1]):context_board.paste(im,(256*i,0))
context_board.save(PREVIEWS/'r2_extinguish_lamp_contact.png')

bottoms = [r['bottom'] for r in records[:-1]]
assert all(a >= b for a,b in zip(bottoms,bottoms[1:])), bottoms
assert records[3]['bottom'] < records[0]['bottom'] - 20
assert all(im.size == CANVAS for im in frames)
manifest = {
 'asset':'emberlamp_extinguish_r2', 'category':'world_animation_part',
 'source':'originals/r2_extinguish.png','prompt':'prompts/r2_extinguish.txt',
 'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
 'source_generated_file':'exec-aa4d399f-6847-4a9f-8e19-c6320bb56f11.png',
 'source_size':list(sheet.size),'source_cell_size':list(CELL),
 'canvas':list(CANVAS),'anchor':list(ANCHOR),'source_anchor':list(SOURCE_ANCHOR),
 'steady_first_frame_bounds':records[0]['alpha_bounds'],
 'steady_first_frame_dimensions':[records[0]['alpha_bounds'][2]-records[0]['alpha_bounds'][0],records[0]['alpha_bounds'][3]-records[0]['alpha_bounds'][1]],
 'fps':30,'frame_indices':[i for i in range(9) for _ in range(2)],
 'duration_seconds':18/30,
 'frames':records,
 'registration':'All PNGs retain the full same-size cell and same anchor. No per-frame cropping to alpha bounds, resizing to different heights, shifting to bottom or recentering is allowed.',
 'world_example':{'uniform_scale':WORLD_SCALE,'root':list(WORLD_ROOT),'resized_canvas':list(world_size),'offset':list(world_offset)},
 'motion':'Root pinches, detaches into rising curled tongues, fragments thin and disappear upward. Bottom edge rises monotonically; this is not downward compression.',
 'alpha':'Only <=8 near-zero generator alpha noise removed for exports; source unchanged.',
 'checks':{'same_canvas':True,'bottom_moves_upward':True,'bottoms':bottoms,'terminal_empty':True},
 'integration':'Use the same transform for all nine frames. Parent may choose one constant scale per fuel state, never a different frame size. Match frame 0 to a normal loop pose, append terminal transparent frame.'
}
(BASE/'r2_extinguish_clip.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'canvas':CANVAS,'anchor':ANCHOR,'bottoms':bottoms,'first_bounds':records[0]['alpha_bounds'],'world_scale':WORLD_SCALE}))
