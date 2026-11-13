"""Non-art geometric reference for the image model's cel registration."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent
(root / "references").mkdir(exist_ok=True)
radii = [12, 22, 32, 42, 53, 64, 75, 86, 97, 108, 119, 130,
         141, 152, 162, 172, 182, 191, 199, 206, 212, 216, 219, 220]
for stage in ("grow", "loop", "release"):
    count = 12 if stage == "release" else 24
    cols, rows = 6, count // 6
    canvas = Image.new("RGB", (512 * cols, 512 * rows), (252, 252, 252))
    draw = ImageDraw.Draw(canvas)
    for i in range(count):
        x, y = (i % cols) * 512 + 256, (i // cols) * 512 + 256
        r = radii[i] if stage == "grow" else 220 if stage == "loop" else 220 + min(i * 2, 18)
        draw.rectangle((x-256, y-256, x+255, y+255), outline=(210,210,210), width=1)
        draw.ellipse((x-r, y-r, x+r, y+r), outline=(105,150,205), width=2)
        draw.line((x-6,y,x+6,y), fill=(220,100,100), width=1)
        draw.line((x,y-6,x,y+6), fill=(220,100,100), width=1)
        draw.text((x-244,y-244), f"{i+1:02}  radius {r}px", fill=(70,70,70))
    canvas.save(root / "references" / f"{stage}_layout.png")
