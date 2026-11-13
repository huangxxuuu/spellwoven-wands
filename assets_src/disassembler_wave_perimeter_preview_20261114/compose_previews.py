"""Compose static review mockups; no animation or runtime asset is modified."""
import argparse
from collections import deque
from pathlib import Path
import hashlib
import json
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "previews"
CENTER = (500, 422)
RADIUS = 430
PROJECTION = math.sin(math.radians(35))
FURNACE_WIDTH = 320
ALPHA_CUTOFF = 8
FONT = "C:/Windows/Fonts/msyh.ttc"


def components(mask):
    seen = np.zeros_like(mask, dtype=bool)
    found = []
    for row, col in zip(*np.where(mask)):
        if seen[row, col]:
            continue
        queue = deque([(int(row), int(col))])
        seen[row, col] = True
        points = []
        while queue:
            y, x = queue.popleft()
            points.append((y, x))
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                ny, nx = y + dy, x + dx
                if (0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1]
                        and mask[ny, nx] and not seen[ny, nx]):
                    seen[ny, nx] = True
                    queue.append((ny, nx))
        if len(points) >= 30:
            points = np.asarray(points)
            found.append({"pixels": len(points),
                          "bbox": [int(points[:, 1].min()), int(points[:, 0].min()),
                                   int(points[:, 1].max() + 1), int(points[:, 0].max() + 1)]})
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=("ab", "c", "d", "e", "f"), default="ab")
    args = parser.parse_args()
    variants = {
        "ab": [("a_24_arcs", "A · 疏朗短弧", "a"), ("b_36_arcs", "B · 细密短弧", "b")],
        "c": [("c_varied_staggered", "C · 错落弧片", "c")],
        "d": [("d_two_interacting_bands", "D · 双层交错弧片", "d")],
        "e": [("e_separated_bands", "E · 双层错落 · 弧片分离", "e")],
        "f": [("f_cyan_gold_only", "F · 青金双色 · 双层错落", "f")],
    }[args.variant]
    suffix = "" if args.variant == "ab" else f"-{args.variant}"
    OUT.mkdir(exist_ok=True)
    furnace_path = ROOT / "references/furnace.png"
    furnace = Image.open(furnace_path).convert("RGBA")
    furnace = furnace.crop(furnace.getchannel("A").getbbox())
    furnace = furnace.resize((FURNACE_WIDTH, round(furnace.height * FURNACE_WIDTH / furnace.width)),
                             Image.Resampling.LANCZOS)
    title = ImageFont.truetype(FONT, 27)
    small = ImageFont.truetype(FONT, 17)
    report = {"purpose": "Static design review only; user selection required before animation generation",
              "tool": "local OpenAI Images API / gpt-image-2.6-sunburst / high",
              "outer_radius_px": RADIUS, "furnace_width_px": FURNACE_WIDTH,
              "ground_projection": PROJECTION,
              "scale_note": "Approximate furnace-to-range proportion from supplied screenshots, not an engine capture",
              "furnace_sha256": hashlib.sha256(furnace_path.read_bytes()).hexdigest(),
              "derivation": "Remove alpha <= 8 background residue, uniform size registration, ground-plane projection, composite unchanged furnace. No shapes repainted by code.",
              "options": {}}
    alpha_checks = Image.new("RGB", (1024, 512 * len(variants)), "white")
    for index, (name, label, letter) in enumerate(variants):
        path = ROOT / "originals" / f"{name}.png"
        pixels = np.array(Image.open(path).convert("RGBA"))
        preserved = None
        if args.variant == "f":
            # Keep only the two exact purple-component deletions from the API edit.
            original = np.array(Image.open(OUT / "e_separated_bands-clean.png").convert("RGBA"))
            edit_mask = np.asarray(Image.open(ROOT / "references/f_exact_component_preservation_mask.png"))[:, :, 3] == 0
            pixels[~edit_mask] = original[~edit_mask]
            preserved = {"outside_mask_identical_to_e": bool(np.array_equal(pixels[~edit_mask], original[~edit_mask])),
                         "api_edit_alpha_max": int(pixels[edit_mask, 3].max()),
                         "composite": "Original E pixels restored outside the two exact purple arc components"}
        pixels[pixels[:, :, 3] <= ALPHA_CUTOFF] = 0
        image = Image.fromarray(pixels)
        image.save(OUT / f"{name}-clean.png")
        mask = pixels[:, :, 3] >= 64
        yy, xx = np.indices(mask.shape)
        radius = np.hypot(xx - (image.width - 1) / 2, yy - (image.height - 1) / 2)
        inner, outer = float(radius[mask].min()), float(radius[mask].max())
        scale = RADIUS / outer
        sprite = image.resize((round(image.width * scale), round(image.height * scale * PROJECTION)),
                              Image.Resampling.LANCZOS)
        scene = Image.new("RGBA", (1000, 740), (92, 91, 77, 255))
        scene.alpha_composite(sprite, (CENTER[0] - sprite.width // 2, CENTER[1] - sprite.height // 2))
        scene.alpha_composite(furnace, (CENTER[0] - furnace.width // 2, CENTER[1] + 9 - furnace.height))
        draw = ImageDraw.Draw(scene)
        draw.rectangle((0, 0, 1000, 70), fill=(35, 40, 36))
        draw.text((24, 12), label, font=title, fill=(239, 236, 220))
        draw.text((975, 30), "相同炉体 / 相同外半径", anchor="rm", font=small, fill=(202, 208, 190))
        draw.text((500, 710), "静态合成预览 · 只标示外围，中心留空 · 非游戏实拍", anchor="mm",
                  font=small, fill=(222, 222, 207))
        scene.convert("RGB").save(OUT / f"preview-{letter}.png")
        for column, color in enumerate(((255, 255, 255, 255), (100, 100, 100, 255))):
            tile = Image.new("RGBA", (512, 512), color)
            tile.alpha_composite(image.resize((512, 512), Image.Resampling.LANCZOS))
            alpha_checks.paste(tile.convert("RGB"), (column * 512, index * 512))
        parts = components(mask)
        metadata = json.loads(path.with_suffix(".png.json").read_text(encoding="utf8"))
        report["options"][name] = {
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "clean_source_sha256": hashlib.sha256((OUT / f"{name}-clean.png").read_bytes()).hexdigest(),
            "solid_components": len(parts), "components": parts,
            "source_inner_radius": inner, "source_outer_radius": outer,
            "inner_to_outer_radius": inner / outer,
            "solid_pixels_inside_80_percent_radius": int(mask[radius < outer * .8].sum()),
            "solid_pixels_inside_90_percent_radius": int(mask[radius < outer * .9].sum()),
            "uniform_scale": scale, "usage": metadata.get("usage"),
            "masked_edit": preserved,
        }
    alpha_checks.save(OUT / f"alpha-white-gray{suffix}.png")
    (ROOT / f"preview_record{suffix}.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(json.dumps({name: {key: value for key, value in row.items() if key != "components"}
                      for name, row in report["options"].items()}, indent=2))


if __name__ == "__main__":
    main()
