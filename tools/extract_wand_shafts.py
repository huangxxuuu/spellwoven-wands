"""Extract the nine approved shafts. Only the grip changes length."""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ART = Path(__file__).resolve().parents[1] / 'assets_src'
CONCEPTS = ART / 'wand_concepts'
PARTS = ART / 'art_v1/runtime/nw_parts'
OUTPUT = CONCEPTS / 'shafts'
WIDTH = 48  # Extra transparent margin for the open roots of 05 and 08.
HEIGHTS = {'short': 104, 'medium': 160, 'long': 224}
# Source rows: socket cut, end of top shoulder, start of lower heel, socket cut.
# The last two names are existing, interchangeable game parts for the proof.
DESIGNS = [
    (470, 590, 1040, 1156, 'crystal_1_red', 'drop_red'),
    (428, 590, 1050, 1203, 'crystal_2_blue', 'round_blue'),
    (451, 585, 1070, 1217, 'crystal_3_green', 'diamond_green'),
    (528, 610, 1072, 1144, 'plain_1_red', 'drop_red'),
    (406, 605, 978, 1203, 'crystal_2_blue', 'round_blue'),
    (411, 580, 1060, 1204, 'plain_3_green', 'diamond_green'),
    (418, 563, 1080, 1199, 'crystal_1_red', 'drop_red'),
    (542, 624, 1030, 1182, 'plain_2_red', 'round_blue'),
    (370, 492, 1060, 1168, 'crystal_3_green', 'diamond_green'),
]


def socket(alpha, y, target_width):
    left, _, right, _ = alpha.crop((0, y, alpha.width, y + 1)).getbbox()
    center = (left + right) / 2
    return center, target_width / (right - left)


def sample_strip(source, y0, y1, start, end, height):
    # Fit the two sockets independently. Each shoulder has one uniform scale.
    # Only the grip interpolates between the two fits.
    cx, scale = start
    ex, end_scale = end
    r, er = WIDTH / (2 * scale), WIDTH / (2 * end_scale)
    quad = (cx-r, y0, ex-er, y1, ex+er, y1, cx+r, y0)
    size = (WIDTH, height)
    large = source.transform((WIDTH*4, height*4), Image.Transform.QUAD, quad,
                             Image.Resampling.BICUBIC)
    return large.resize(size, Image.Resampling.LANCZOS)


def tuck(part, at_top):
    # The current game clips overlap the socket by eight source pixels.
    # Trim the hidden plug inside that overlap so the original brass rim
    # remains visible. Leave the visible shoulder outside the overlap intact.
    scale = 4
    mask = Image.new('L', (WIDTH*scale, part.height*scale), 255)
    d = ImageDraw.Draw(mask)
    for row in range(8*scale):
        t = row/(8*scale)
        radius = (3.5+(WIDTH/2-3.5)*t*t)*scale
        y = row if at_top else mask.height-1-row
        d.line((0,y,mask.width/2-radius,y), fill=0)
        d.line((mask.width/2+radius,y,mask.width,y), fill=0)
    part.putalpha(ImageChops.multiply(part.getchannel('A'), mask.resize(part.size, Image.Resampling.LANCZOS)))


def extract(source, rows):
    y0, y1, y2, y3 = rows
    alpha = source.getchannel('A').point(lambda a: 255 if a > 50 else 0)
    top = socket(alpha, y0, 13)
    bottom = socket(alpha, y3-1, 18)
    upper = sample_strip(source, y0, y1, top, top, round((y1-y0)*top[1]))
    lower = sample_strip(source, y2, y3, bottom, bottom, round((y3-y2)*bottom[1]))
    tuck(upper, True)
    tuck(lower, False)
    grip = sample_strip(source, y1, y2, top, bottom, HEIGHTS['long']-upper.height-lower.height)
    bodies = {}
    for length, height in HEIGHTS.items():
        middle_height = height-upper.height-lower.height
        assert middle_height > 0
        body = Image.new('RGBA', (WIDTH, height))
        body.paste(upper)
        body.paste(grip.resize((WIDTH, middle_height), Image.Resampling.LANCZOS), (0, upper.height))
        body.paste(lower, (0, height-lower.height))
        bodies[length] = body
    return bodies, upper, lower


def placed_preview(body, head, tail):
    # Match game matrix offsets and draw order at source-pixel scale.
    item = Image.new('RGBA', (110, head.height+body.height+tail.height-16))
    for sprite, y in [(head, 0), (tail, head.height+body.height-16), (body, head.height-8)]:
        item.alpha_composite(sprite, ((item.width-sprite.width)//2, y))
    return item


def main():
    OUTPUT.mkdir(exist_ok=True)
    board = Image.new('RGB', (915, 1188), '#ddd3bd')
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype('arial.ttf', 18)
    for index, (*rows, head_id, tail_id) in enumerate(DESIGNS, 1):
        source = Image.open(CONCEPTS / f'{index:02}.png').convert('RGBA')
        bodies, upper, lower = extract(source, rows)
        x, y = (index-1)%3*305, (index-1)//3*396
        draw.text((x+12, y+8), f'{index:02}', font=font, fill='#573b2d')
        head = Image.open(PARTS / f'head_{head_id}.png')
        tail = Image.open(PARTS / f'tail_{tail_id}.png')
        for col, (length, body) in enumerate(bodies.items()):
            path = OUTPUT / f'body_{index:02}_{length}.png'
            body.save(path)
            saved = Image.open(path)
            left, _, right, _ = saved.getchannel('A').point(lambda a: 255 if a>40 else 0).getbbox()
            assert left>0 and right<WIDTH, (index, length, 'clipped silhouette')
            assert saved.crop((0, 0, WIDTH, upper.height)).tobytes() == upper.tobytes()
            assert saved.crop((0, saved.height-lower.height, WIDTH, saved.height)).tobytes() == lower.tobytes()
            im = placed_preview(saved, head, tail)
            board.paste(im, (x+col*95, y+376-im.height), im)
        print(f'{index:02}: locked {upper.height}px top / {lower.height}px bottom')
    board.save(CONCEPTS / 'shaft_lengths.png')


if __name__ == '__main__':
    main()
