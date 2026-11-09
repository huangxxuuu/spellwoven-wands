"""Export independently generated R3 inventory artwork with one fixed body.

Only existing image_gen pixels are cropped, registered and composited here.
No world sprite is downscaled into a UI icon and no illustration is drawn.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

BASE = Path(__file__).resolve().parent
SRC = BASE / "inventory_sources"
OUT = BASE / "inventory"
REVIEW = BASE / "inventory_review"
STATES = ["empty", "half", "full", "half_lit", "full_lit"]

# R2 is the separately simplified UI design, including its grounded foundation.
# R3 replaces only the interior aperture and fuel contents. The C arm, stone
# foundation, bowl, diamond and almost all ribs/canopy retain the same pixels.
BODY_SOURCE = "r2_empty.png"
CONTENT_PATCH = (616, 544, 839, 787)
SELECTED = {
    "empty": "r3_empty_wick_generated.png",
    "half": "r3_half_unlit_generated.png",
    "full": "r3_full_unlit_generated.png",
    "half_lit": "r3_half_lit_generated.png",
    "full_lit": "r3_full_lit_generated.png",
}
PROMPTS = {
    "empty": "prompts/r3_inventory_01_empty_wick.txt",
    "half_lit": "prompts/r3_inventory_02_half_lit.txt",
    "full_lit": "prompts/r3_inventory_03_full_lit.txt",
    "half": "prompts/r3_inventory_04_half_unlit.txt",
    "full": "prompts/r3_inventory_05_full_unlit.txt",
}
GENERATED = {
    "empty": "exec-ad46cbf0-2b7d-4f01-be00-36490763474c.png",
    "half_lit": "exec-bb51956a-654d-481f-a888-e1a329326f7f.png",
    "full_lit": "exec-0d0e16b7-cbe1-4b4c-a719-a15754c0620b.png",
    "half": "exec-e79629bd-97f7-4a94-ac96-0686c8a3ba89.png",
    "full": "exec-35ea6bc4-4d18-43b4-bab8-abd98b8f6a5c.png",
}


def normalized(image):
    image = image.convert("RGBA").copy()
    alpha = image.getchannel("A").point(lambda v: 0 if v <= 8 else v)
    image.putalpha(alpha)
    # Clear hidden RGB so reference viewers cannot show transparent ghost art.
    cleared = Image.new("RGBA", image.size)
    cleared.alpha_composite(image)
    return cleared


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def equal_outside_patch(image, reference):
    difference = ImageChops.difference(image, reference)
    difference.paste((0, 0, 0, 0), CONTENT_PATCH)
    return all(channel.getbbox() is None for channel in difference.split())


def main():
    for directory in (OUT, REVIEW):
        directory.mkdir(exist_ok=True)
    fixed_body = normalized(Image.open(SRC / BODY_SOURCE))
    images = {}
    for state, filename in SELECTED.items():
        original = normalized(Image.open(SRC / filename))
        if original.size != fixed_body.size:
            raise ValueError(f"UI source canvas changed: {filename}: {original.size}")
        # Replacement, not alpha-over, also removes the unlit aperture contents.
        composed = fixed_body.copy()
        composed.paste(original.crop(CONTENT_PATCH), CONTENT_PATCH[:2])
        composed = normalized(composed)
        composed.save(SRC / f"r3_{state}.png")
        original.crop(CONTENT_PATCH).save(SRC / f"r3_contents_{state}.png")
        images[state] = composed
        assert equal_outside_patch(composed, fixed_body), state

    boxes = [im.getchannel("A").getbbox() for im in images.values()]
    crop = (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))
    scale = min(60 / (crop[2] - crop[0]), 60 / (crop[3] - crop[1]))
    size = (round((crop[2] - crop[0]) * scale),
            round((crop[3] - crop[1]) * scale))
    offset = ((64 - size[0]) // 2, (64 - size[1]) // 2)
    exports = {}
    for state, source in images.items():
        small = source.crop(crop).resize(size, Image.Resampling.LANCZOS)
        icon = Image.new("RGBA", (64, 64))
        icon.alpha_composite(small, offset)
        path = OUT / f"nw_emberlamp_{state}.png"
        icon.save(path)
        icon.resize((32, 32), Image.Resampling.LANCZOS).save(REVIEW / f"{state}_32.png")
        assert icon.getchannel("A").getextrema() == (0, 255)
        assert all(icon.getpixel(xy)[3] == 0
                   for xy in ((0, 0), (63, 0), (0, 63), (63, 63)))
        exports[state] = {
            "source": f"inventory_sources/r3_{state}.png",
            "path": path.relative_to(BASE).as_posix(),
            "size": [64, 64],
            "original_content_source": "inventory_sources/" + SELECTED[state],
            "content_layer": f"inventory_sources/r3_contents_{state}.png",
            "source_sha256": sha(SRC / f"r3_{state}.png"),
            "generated_source_sha256": sha(SRC / SELECTED[state]),
            "output_sha256": sha(path),
            "alpha_bounds": list(icon.getchannel("A").getbbox()),
        }
    shutil.copyfile(OUT / "nw_emberlamp_full_lit.png", OUT / "nw_emberlamp.png")
    assert len({sha(OUT / f"nw_emberlamp_{s}.png") for s in STATES}) == 5

    board = Image.new("RGBA", (1000, 640), "#39363d")
    draw = ImageDraw.Draw(board)
    draw.text((20, 12), "Arcane Ember Lamp R3: persistent wick / surrounding fuel / wick inside fire", fill="white")
    for i, state in enumerate(STATES):
        x = 20 + i * 196
        draw.text((x, 42), state, fill="white")
        icon = Image.open(OUT / f"nw_emberlamp_{state}.png").convert("RGBA")
        for row, colour in enumerate(("#b7b8ba", "#242128")):
            panel = Image.new("RGBA", (176, 250), colour)
            panel.alpha_composite(icon.resize((128, 128), Image.Resampling.NEAREST), (24, 8))
            panel.alpha_composite(icon, (15, 160))
            panel.alpha_composite(icon.resize((32, 32), Image.Resampling.LANCZOS), (116, 176))
            pd = ImageDraw.Draw(panel)
            label = "#242128" if row == 0 else "#dddddf"
            pd.text((14, 233), "64 px", fill=label)
            pd.text((111, 233), "32 px", fill=label)
            board.alpha_composite(panel, (x, 65 + row * 267))
    board.convert("RGB").save(REVIEW / "inventory_contact.png")
    board.convert("RGB").save(REVIEW / "r3_inventory_contact.png")

    details = Image.new("RGBA", (5 * 280, 340), "#77766f")
    dd = ImageDraw.Draw(details)
    for i, state in enumerate(STATES):
        dd.text((i * 280 + 12, 10), state, fill="white")
        region = images[state].crop((600, 530, 855, 830))
        details.alpha_composite(region, (i * 280 + 12, 32))
    details.convert("RGB").save(REVIEW / "r3_contents_detail.png")

    manifest = {
        "revision": 3,
        "category": "game_inventory_icon",
        "tool": "built-in image_gen",
        "runtime_size": [64, 64],
        "auxiliary_readability_size": [32, 32],
        "target_size_basis": "Existing nw_arcane_storage atlas and supply inventory tiles use 64 pixels.",
        "common_crop": list(crop), "resized_size": list(size),
        "common_offset": list(offset), "source_alpha_noise_threshold": 8,
        "processing": "Five separate generated UI variants supply the same cavity rectangle; one existing independent UI body and grounded base are reused. Alpha normalization, fixed crop, common scale and PNG export only.",
        "fixed_body": {
            "source": "inventory_sources/" + BODY_SOURCE,
            "mutable_content_bounds": list(CONTENT_PATCH),
            "all_pixels_outside_patch_identical": all(equal_outside_patch(im, fixed_body) for im in images.values()),
        },
        "grounded_base": {
            "source": "inventory_sources/" + BODY_SOURCE,
            "patch_bounds": [0, 990, fixed_body.width, fixed_body.height],
            "all_states_identical": all(im.crop((0, 990, im.width, im.height)).tobytes() == fixed_body.crop((0, 990, im.width, im.height)).tobytes() for im in images.values()),
            "design": "The central large stone and corner stones share a ground plane; no floating undercut.",
        },
        "approved_identity": "concepts/wick_r4/wick_comparison_full.png",
        "full_fuel_selection": {
            "source": "inventory_sources/r3_full_unlit_generated.png",
            "design": "Raised purple fuel retains a dark outer perimeter, surrounds the wick and fully buries its fixing eyelet.",
        },
        "wick": {
            "empty": "Permanent unlit wick and small fixing eyelet remain visible.",
            "half": "Low surrounding powder buries the foot and eyelet, leaving a short wick.",
            "full": "Full mound buries the eyelet and almost all wick, leaving its tip.",
            "lit": "Muted wick detail sits inside the lower flame core and is partially covered by foreground fire.",
        },
        "sources": exports,
        "alias": {"inventory/nw_emberlamp.png": "inventory/nw_emberlamp_full_lit.png"},
        "prompt_files": list(PROMPTS.values()),
        "r3_generated": [
            {"state": s, "file": "inventory_sources/" + SELECTED[s],
             "prompt": PROMPTS[s], "source": GENERATED[s]}
            for s in STATES
        ],
        "review": "inventory_review/r3_inventory_contact.png",
        "detail_review": "inventory_review/r3_contents_detail.png",
        "validation": {
            "RGBA": True, "transparent_corners": True,
            "consistent_canvas_scale_and_offset": True,
            "five_distinct_states": True, "ground_shadow_in_icons": False,
            "world_sprite_downscaled_as_icon": False,
        },
        "rebuild_command_portable_bundle": "python3 emberlamp/export_inventory.py",
    }
    (BASE / "inventory_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf8")
    print(json.dumps({"revision": 3, "crop": crop, "scaled_size": size,
                      "offset": offset, "exports": list(exports)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
