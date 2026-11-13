"""Extract painted cels without pose-dependent fitting or animation transforms."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent


def extract(sheet: Path, stage: str, first: int):
    source = Image.open(sheet).convert("RGBA")
    if source.width % 512 or source.height % 512:
        raise ValueError(f"Unexpected grid size: {source.size}")
    cols, rows = source.width // 512, source.height // 512
    frames = ROOT / "frames"
    frames.mkdir(exist_ok=True)
    report = {"sheet": str(sheet.relative_to(ROOT)),
              "sha256": hashlib.sha256(sheet.read_bytes()).hexdigest(),
              "grid": [cols, rows], "cell_size": [512, 512], "frames": []}
    preview = Image.new("RGB", (512 * cols, 540 * rows), (76, 83, 75))
    draw = ImageDraw.Draw(preview)
    for i in range(cols * rows):
        col, row = i % cols, i // cols
        box = (col * 512, row * 512, (col + 1) * 512, (row + 1) * 512)
        cel = source.crop(box)
        path = frames / f"{stage}_{first + i:03d}.png"
        cel.save(path)
        pixels = np.array(cel)
        yy, xx = np.nonzero(pixels[:, :, 3] >= 16)
        radius = np.hypot(xx - 256, yy - 256)
        entry = {"path": str(path.relative_to(ROOT)), "crop": box,
                 "alpha_extrema": cel.getchannel("A").getextrema(),
                 "radius": float(radius.max()) if len(radius) else 0,
                 "bbox": cel.getchannel("A").getbbox(),
                 "opaque_pixels": int(np.sum(pixels[:, :, 3] >= 16)),
                 "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        report["frames"].append(entry)
        background = Image.new("RGBA", cel.size, (76, 83, 75, 255))
        background.alpha_composite(cel)
        preview.paste(background.convert("RGB"), (col * 512, row * 540))
        draw.text((col * 512 + 12, row * 540 + 515),
                  f"{path.stem}  radius={entry['radius']:.1f}", fill=(245, 240, 224))
    audit = ROOT / "audit"
    audit.mkdir(exist_ok=True)
    (audit / f"{sheet.stem}.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    preview.save(audit / f"{sheet.stem}.png")
    preview.thumbnail((1536, 1536), Image.Resampling.LANCZOS)
    preview.save(audit / f"{sheet.stem}_overview.png")
    print(json.dumps({"sheet": report["sheet"], "frames": len(report["frames"]),
                      "radii": [round(item["radius"], 1) for item in report["frames"]]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sheet", type=Path)
    parser.add_argument("stage", choices=("grow", "loop", "release"))
    parser.add_argument("first", type=int)
    args = parser.parse_args()
    extract(args.sheet.resolve(), args.stage, args.first)
