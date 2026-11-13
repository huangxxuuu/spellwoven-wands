"""Select generated cels; no spatial motion or shape interpolation is synthesized."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SHEETS = {
    "grow": ("grow_full_v3.png", 6),
    "grow_finish": ("grow_finish.png", 4),
    "loop": ("loop_full.png", 6),
    "release": ("release_complete_v2.png", 4),
}
ALPHA_CLEANUP = 32


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    # Load every required original before changing any derived files.
    originals = {key: Image.open(ROOT / "originals" / name).convert("RGBA")
                 for key, (name, _) in SHEETS.items()}
    records = []
    review = ROOT / "previews"
    review.mkdir(exist_ok=True)
    for stage, count in (("grow", 24), ("loop", 24), ("release", 12)):
        contact = Image.new("RGB", (6 * 256, ((count + 5) // 6) * 280), (76, 83, 75))
        draw = ImageDraw.Draw(contact)
        for index in range(count):
            key, cel_index, note = stage, index, "generated cel"
            if stage == "grow" and index >= 18:
                key, cel_index, note = "loop", index, "continuous painted settling poses leading into loop"
            elif stage == "release" and index == 0:
                key, cel_index, note = "loop", 0, "exact shared seam pose"
            name, columns = SHEETS[key]
            col, row = cel_index % columns, cel_index // columns
            box = [col * 512, row * 512, (col + 1) * 512, (row + 1) * 512]
            cel = originals[key].crop(box)
            raw = np.array(cel)
            image = raw.copy()
            image[image[:, :, 3] <= ALPHA_CLEANUP] = 0
            if (stage, index) in (("grow", 0), ("release", 11)):
                image[:] = 0
                note = "transparent endpoint"
            output = Image.fromarray(image)
            path = ROOT / "frames" / f"{stage}_{index:03}.png"
            output.save(path)
            alpha = image[:, :, 3]
            yy, xx = np.nonzero(alpha >= 64)
            border = np.concatenate((alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]))
            records.append({"frame": path.name, "original": "originals/" + name,
                            "original_sha256": sha((ROOT / "originals" / name).read_bytes()),
                            "crop": box, "operation": note, "alpha_cleanup_at_or_below": ALPHA_CLEANUP,
                            "removed_faint_pixels": int(np.sum((raw[:, :, 3] > 0) & (raw[:, :, 3] <= ALPHA_CLEANUP))),
                            "sha256": sha(path.read_bytes()), "pixel_sha256": sha(image.tobytes()),
                            "visible_pixels": int(len(xx)), "edge_pixels_alpha64": int(np.sum(border >= 64)),
                            "radius_alpha64": float(np.hypot(xx - 256, yy - 256).max()) if len(xx) else 0})
            background = Image.new("RGBA", (512, 512), (76, 83, 75, 255))
            background.alpha_composite(output)
            x, y = (index % 6) * 256, (index // 6) * 280
            contact.paste(background.convert("RGB").resize((256, 256), Image.Resampling.LANCZOS), (x, y))
            draw.text((x + 8, y + 258), f"{stage}_{index:03}", fill=(235, 237, 224))
        contact.save(review / f"{stage}-painted-cels.png")
    unique = {row["pixel_sha256"] for row in records if row["visible_pixels"]}
    report = {"frame_slots": len(records), "unique_nonempty_painted_poses": len(unique),
              "empty_endpoints": sum(row["visible_pixels"] == 0 for row in records),
              "spatial_processing": "exact fixed-grid cropping only; no per-pose recenter, resize, rotation, warping or interpolation",
              "alpha_processing": "remove generated low-alpha background haze <=32; keep original RGBA sheets unchanged",
              "frames": records}
    (ROOT / "source_selection.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    print(json.dumps({key: value for key, value in report.items() if key != "frames"}))
    print("Border issues:", [(r["frame"], r["edge_pixels_alpha64"]) for r in records if r["edge_pixels_alpha64"]])


if __name__ == "__main__":
    main()
