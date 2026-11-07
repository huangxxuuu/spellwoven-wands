"""Review the production spore XML at 30 Hz, with its real release timing."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

from preview_field_stages import Review
from preview_basic_flight import FONT, SMALL


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/previews/spore-sentry-v2"
BG = (53, 61, 54, 255)
INK = (228, 225, 205)
DIM = (173, 188, 156)


def stage_sheet(review):
    canvas = Image.new("RGBA", (1000, 600), BG)
    draw = ImageDraw.Draw(canvas)
    for row, phase in enumerate(("grow", "idle", "fire", "wilt")):
        clip = "spore_"+phase
        count = len(review.bank.clips[clip]["poses"])
        draw.text((12, row*150+3), phase.upper(), fill=INK, font=SMALL)
        indices = [round(i*(count-1)/6) for i in range(7)]
        if phase == "fire":
            indices = [0, 2, 3, 5, 6, 9, 11]
        for col, index in enumerate(indices):
            anchor = (col*142+70, row*150+142)
            draw.line((anchor[0]-25, anchor[1], anchor[0]+25, anchor[1]), fill=DIM)
            review.stamp(canvas, clip, index/30, anchor, .72)
            label = "RELEASE .20s" if phase == "fire" and index == 6 else f"{index/30:.2f}s"
            draw.text((col*142+12, row*150+24), label, fill=DIM, font=SMALL)
    canvas.convert("RGB").save(OUT / "stages.png")


def lifecycle(review):
    # The final shot completes all twelve attack frames before wilt begins.
    # This scenario mirrors the garden's three shots and .2 s release event.
    schedule = (("grow", 18), ("fire", 12), ("idle", 12),
                ("fire", 12), ("idle", 12), ("fire", 12), ("wilt", 9), (None, 15))
    frames = []
    times = []
    tick = 0
    shot = 0
    for phase, count in schedule:
        if phase == "fire":
            shot += 1
        for index in range(count):
            canvas = Image.new("RGBA", (1000, 500), BG)
            draw = ImageDraw.Draw(canvas)
            draw.text((26, 20), "SPORE SENTRY / OFFLINE PRODUCTION FRAME PREVIEW", fill=INK, font=FONT)
            draw.text((26, 56), "Flat inked poses; planted roots; grow 0.6s / fire 0.4s / wilt 0.3s", fill=DIM, font=SMALL)
            label = "COMPLETE" if phase is None else phase.upper()
            if phase == "fire":
                label += f" / SHOT {shot} / FRAME {index:02d}"
            draw.text((26, 102), label, fill=INK, font=FONT)
            if phase == "fire" and index == 6:
                draw.text((26, 141), "PROJECTILE RELEASE / 0.20s", fill=(232, 215, 158), font=FONT)
            for scale, anchor, text in ((1, (345, 407), "x1"), (1.65, (725, 407), "DETAIL x1.65")):
                draw.line((anchor[0]-66, anchor[1], anchor[0]+66, anchor[1]), fill=DIM)
                if phase is not None:
                    review.stamp(canvas, "spore_"+phase, index/30, anchor, scale)
                draw.text((anchor[0]-65, 436), text, fill=DIM, font=SMALL)
            frames.append(canvas.convert("RGB"))
            # GIF uses centiseconds; 30/30/40 ms cycles preserve 30 Hz mean.
            times.append((3, 3, 4)[tick % 3]*10)
            tick += 1
    frames[0].save(OUT / "lifecycle.gif", save_all=True, append_images=frames[1:],
                   duration=times, loop=0, optimize=True, disposal=1)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    review = Review()
    stage_sheet(review)
    lifecycle(review)
    print(OUT)


if __name__ == "__main__":
    main()
