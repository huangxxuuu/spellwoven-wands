"""Create review-only views of the generated dark-fog subject and existing card frame."""
from pathlib import Path
import json
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from compose_spell_cards import fitted_subject, simple_plate


def main():
    source = HERE / (sys.argv[1] if len(sys.argv) > 1 else "dark-source-01.png")
    out = HERE / "review"
    out.mkdir(exist_ok=True)
    im = Image.open(source).convert("RGBA")
    rgba = np.asarray(im)
    alpha = rgba[:, :, 3]
    solid = rgba[alpha >= 240, :3]
    stats = {
        "source": source.relative_to(ROOT).as_posix(),
        "size": list(im.size),
        "alpha_range": list(map(int, im.getchannel("A").getextrema())),
        "visible_bbox": list(im.getchannel("A").point(lambda v: 255 if v >= 8 else 0).getbbox()),
        "fully_transparent_fraction": float(np.mean(alpha == 0)),
        "opaque_rgb_median": np.median(solid, axis=0).tolist(),
        "opaque_rgb_p90": np.percentile(solid, 90, axis=0).tolist(),
        "opaque_pixels_near_black_fraction": float(np.mean(solid.max(axis=1) <= 64)),
    }
    for name, color in (("white", "white"), ("gray", "#808080")):
        bg = Image.new("RGBA", im.size, color)
        bg.alpha_composite(im)
        bg.convert("RGB").save(out / f"subject_{name}.png")

    layers = ROOT / "assets_src/spell_cards_composed/v1/layers"
    paper = Image.open(layers / "modifier.paper.png").convert("RGBA")
    rim = Image.open(layers / "modifier.rim.png").convert("RGBA")
    safe = Image.open(layers / "modifier.safe.png").convert("L")
    subject, album_fit = fitted_subject(source, safe, False)
    card = paper.copy()
    card.alpha_composite(subject)
    card.alpha_composite(rim)
    card.save(out / "dark_card_1024.png")
    small, inner = simple_plate("modifier")
    subject, icon_fit = fitted_subject(
        source, inner.resize((1024, 1024), Image.Resampling.NEAREST).filter(ImageFilter.MinFilter(17)), False
    )
    small.alpha_composite(subject.resize(small.size, Image.Resampling.LANCZOS))
    for size in (128, 64, 32):
        small.resize((size, size), Image.Resampling.LANCZOS).save(out / f"dark_icon_{size}.png")
    stats.update(album_fit=album_fit, inventory_fit=icon_fit)

    sheet = Image.new("RGB", (960, 900), "#D7D5D0")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 22)
    label = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
    draw.text((24, 16), "暗雾 · 黑色暗影瘴气卡面", fill="#262626", font=font)
    for x, name in ((24, "white"), (504, "gray")):
        thumb = Image.open(out / f"subject_{name}.png").resize((432, 432), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (x, 64))
    draw.text((24, 505), "透明边缘检查：白底 / 灰底", fill="#262626", font=label)
    thumb = card.resize((320, 320), Image.Resampling.LANCZOS)
    sheet.paste(thumb, (24, 548), thumb)
    draw.text((360, 548), "现有六边形修饰卡框", fill="#262626", font=label)
    for x, size in ((368, 128), (540, 64), (656, 32)):
        icon = Image.open(out / f"dark_icon_{size}.png")
        for y, color in ((600, "#F7F7F7"), (752, "#363636")):
            draw.rectangle((x - 8, y - 8, x + size + 8, y + size + 8), fill=color)
            sheet.paste(icon, (x, y), icon)
        draw.text((x, 575), f"{size}px", fill="#262626", font=label)
    sheet.save(out / "review_sheet.png")
    (out / "metrics.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == "__main__":
    main()
