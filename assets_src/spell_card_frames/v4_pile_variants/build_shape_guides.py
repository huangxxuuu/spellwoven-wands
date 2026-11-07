"""Exact geometry guides for card-pile art studies; does not read or edit game art."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
AA = 3
BG = "#34312F"
PAPER = "#DDD3BE"
SIDE = "#BCAE96"
INK = "#51463F"
TEXT = "#EEE5D4"
MUTED = "#C2B6A4"
SHAPES = {
    "R": [(4,0),(48,0),(52,4),(52,52),(48,56),(4,56),(0,52),(0,4)],
    "H": [(26,0),(52,12),(52,44),(26,56),(0,44),(0,12)],
    "N": [(4,0),(18,0),(18,8),(34,8),(34,0),(48,0),(52,4),(52,52),(48,56),(4,56),(0,52),(0,4)],
}
BASES = [("R", "R"), ("H", "R"), ("R", "H"), ("H", "H")]


def font(size):
    return ImageFont.truetype("C:/Windows/Fonts/arial.ttf", round(size * AA))


def canvas(size):
    im = Image.new("RGB", (size[0] * AA, size[1] * AA), BG)
    return im, ImageDraw.Draw(im)


def label(draw, xy, text, size=22, fill=TEXT, anchor="mm"):
    draw.text(tuple(round(c * AA) for c in xy), text, font=font(size), fill=fill, anchor=anchor)


def projected(shape, cx, y0, scale, elevation):
    return [
        (
            (cx + (x-26) * scale * (0.68 + 0.32*y/56)) * AA,
            (y0 + y * scale * 0.60 - elevation) * AA,
        )
        for x, y in SHAPES[shape]
    ]


def paper_layer(draw, shape, cx, y0, scale, elevation, thickness=5):
    face = projected(shape, cx, y0, scale, elevation)
    bottom = [(x, y + thickness*AA) for x, y in face]
    # Union of thin extrusion quads, then its complete opaque face. No top mask.
    draw.polygon(bottom, fill=SIDE)
    for i, p in enumerate(face):
        j = (i+1) % len(face)
        draw.polygon([p, face[j], bottom[j], bottom[i]], fill=SIDE)
    draw.line(bottom + [bottom[0]], fill=INK, width=round(1.4*AA), joint="curve")
    draw.polygon(face, fill=PAPER)
    draw.line(face + [face[0]], fill=INK, width=round(1.8*AA), joint="curve")


def pile(draw, sequence, cx, y0, scale=4.7, thickness=5):
    # sequence is visually top-to-bottom. Physical bottom is drawn first.
    n = len(sequence)
    for index in range(n-1, -1, -1):
        elevation = (n-1-index)*thickness
        paper_layer(draw, sequence[index], cx, y0, scale, elevation, thickness)


def save(im, name):
    im = im.resize((im.width//AA, im.height//AA), Image.Resampling.LANCZOS)
    im.save(OUT/name)


def matrix():
    im, d = canvas((1440, 1250))
    label(d, (720, 40), "TOP FACE + TWO UNDERCARDS", 30)
    label(d, (720, 80), "All sheets lie flat. Sequence is top to bottom. Fixed alignment; no fan.", 20, MUTED)
    centers = [420, 810, 1200]
    for cx, top, name in zip(centers, ["R","H","N"], ["RECTANGLE", "HEXAGON", "NOTCHED RECTANGLE"]):
        label(d, (cx, 136), f"{top}  |  {name}", 20)
    for row, (u1,u2) in enumerate(BASES):
        y = 184 + row*260
        label(d, (95,y+64), f"{u1}{u2}", 30)
        label(d, (95,y+100), f"{u1} > {u2}", 20, MUTED)
        for cx, top in zip(centers, ["R","H","N"]):
            pile(d, [top,u1,u2], cx, y, scale=4.7, thickness=5)
            label(d, (cx, y+195), f"T={top} | {u1} > {u2}", 20, MUTED)
    label(d, (720,1210), "R = clipped rectangle  |  H = pointed vertical hexagon  |  N = top-notched rectangle", 20, MUTED)
    save(im, "pile_matrix_geometry.png")


def bases():
    im, d = canvas((1200,820))
    label(d, (600,40), "FOUR REUSABLE UNDERCARD BASES", 30)
    label(d, (600,80), "Two complete blank cards only. No top card. No hollow cutout.", 20, MUTED)
    for i, (u1,u2) in enumerate(BASES):
        cx=300+(i%2)*600
        y=165+(i//2)*330
        label(d, (cx,y-40), f"{u1}{u2}  |  {u1} above {u2}", 24)
        pile(d,[u1,u2],cx,y,scale=5.7,thickness=6)
        label(d,(cx,y+235),f"U1={u1}  /  U2={u2}",20,MUTED)
    label(d,(600,785),"Interior notched rectangles use R. Add the real top-card art above these layers.",20,MUTED)
    save(im,"pile_bases_geometry.png")


if __name__ == "__main__":
    matrix()
    bases()
    print(OUT/"pile_matrix_geometry.png")
    print(OUT/"pile_bases_geometry.png")
