"""Inspect fixed-grid painted sheets, then finalize only an explicit selection.

Draft: python finalize_frames.py --draft
Final: python finalize_frames.py --final --selection selection_plan.json
Candidate: python finalize_frames.py --candidate release_alpha
  --sheet originals/release_12_alpha.png --columns 4 --count 12
Selection format: {"frames": [{"frame": "grow_000.png", "transparent": true},
{"frame": "grow_001.png", "source": "draft_frames/grow_001.png",
"alpha_cleanup_at_or_below": 32}, ...]}.
Extra alpha cleanup is opt-in per selected slot, alpha-byte-only; omitted
thresholds retain the draft's existing cleanup with no additional processing.
All 60 slots must be explicitly selected. Sources may be draft_frames or
references PNGs. This tool never aligns, fits, rotates or deforms a drawing.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SIZE = 512
PHASES = {"grow": (24, 6, 4, 60), "loop": (24, 6, 4, 60), "release": (12, 4, 3, 18)}
FONT = "C:/Windows/Fonts/msyh.ttc"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


def components(mask):
    """Four-connected alpha64 islands; retain all sizes in the report."""
    seen = np.zeros(mask.shape, dtype=bool)
    groups = []
    height, width = mask.shape
    for row, column in zip(*np.nonzero(mask)):
        if seen[row, column]:
            continue
        pending = deque([(int(column), int(row))])
        seen[row, column] = True
        count, left, top, right, bottom = 0, width, height, 0, 0
        while pending:
            x, y = pending.popleft()
            count += 1
            left, top, right, bottom = min(left, x), min(top, y), max(right, x), max(bottom, y)
            for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if 0 <= nx < width and 0 <= ny < height and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    pending.append((nx, ny))
        groups.append({"pixels": count, "bbox": [left, top, right+1, bottom+1]})
    return sorted(groups, key=lambda group: -group["pixels"])


def measure(image):
    pixels = np.asarray(image)
    mask = pixels[:, :, 3] >= 64
    yy, xx = np.nonzero(mask)
    radii = np.hypot(xx - 256, yy - 256)
    groups = components(mask)
    alpha = pixels[:, :, 3]
    return {"size": list(image.size), "pixel_sha256": hashlib.sha256(image.tobytes()).hexdigest(),
            "alpha_bounds": image.getchannel("A").getbbox(),
            "alpha64_bounds": image.getchannel("A").point(lambda value: 255 if value >= 64 else 0).getbbox(),
            "visible_pixels": int(np.count_nonzero(pixels[:, :, 3])), "alpha64_pixels": int(mask.sum()),
            "alpha_bins": {"zero": int((alpha == 0).sum()),
                           "1_to_8": int(((alpha > 0) & (alpha <= 8)).sum()),
                           "9_to_32": int(((alpha > 8) & (alpha <= 32)).sum()),
                           "33_to_63": int(((alpha > 32) & (alpha < 64)).sum()),
                           "64_to_255": int((alpha >= 64).sum())},
            "radius_alpha64": float(radii.max()) if len(xx) else 0,
            "inner_radius_alpha64": float(radii.min()) if len(xx) else 0,
            "edge_pixels_alpha64": int(mask[0].sum()+mask[-1].sum()+mask[1:-1, 0].sum()+mask[1:-1, -1].sum()),
            "components_alpha64": len(groups), "components_alpha64_at_least_30px": sum(group["pixels"] >= 30 for group in groups),
            "components": groups}


def difference(first, second):
    # Premultiplied comparison excludes invisible RGB while preserving alpha.
    arrays = []
    for image in (first, second):
        values = np.asarray(image).astype(np.float32)
        values[:, :, :3] *= values[:, :, 3:4] / 255
        arrays.append(values)
    delta = np.abs(arrays[0] - arrays[1])
    return {"mean_absolute_premultiplied_rgba": float(delta.mean()),
            "mean_absolute_alpha": float(delta[:, :, 3].mean()),
            "changed_alpha64_pixels": int(np.count_nonzero((arrays[0][:, :, 3] >= 64) != (arrays[1][:, :, 3] >= 64))),
            "identical_pixels": bool(np.array_equal(np.asarray(first), np.asarray(second)))}


def read_rgba(path):
    with Image.open(path) as image:
        if image.mode != "RGBA":
            raise ValueError(f"{path}: expected straight RGBA, found {image.mode}")
        return image.copy()


def previews(phase, drawings, rows, destination, columns=None):
    destination.mkdir(parents=True, exist_ok=True)
    columns = columns or PHASES[phase][1]
    thumb, label, margin = 256, 42, 12
    font = ImageFont.truetype(FONT, 16)
    sheet = Image.new("RGB", (columns*thumb, ((len(drawings)+columns-1)//columns)*(thumb+label)), (83, 85, 77))
    draw = ImageDraw.Draw(sheet)
    frames = []
    for index, (image, row) in enumerate(zip(drawings, rows)):
        tile = Image.new("RGBA", (SIZE, SIZE), (83, 85, 77, 255))
        tile.alpha_composite(image)
        x, y = index % columns*thumb, index // columns*(thumb+label)
        sheet.paste(tile.resize((thumb, thumb), Image.Resampling.LANCZOS).convert("RGB"), (x, y))
        draw.text((x+margin, y+thumb+2), f"{row['frame'].removesuffix('.png')}  r64={row['radius_alpha64']:.1f}", font=font, fill="white")
        draw.text((x+margin, y+thumb+21), f"islands≥30px={row['components_alpha64_at_least_30px']}  edge={row['edge_pixels_alpha64']}", font=font, fill="white")
        frames.append(tile.convert("RGB").quantize(colors=256))
    sheet.save(destination / f"{phase}-contact.png")
    ticks = PHASES[phase][3]
    mapping = [tick*len(frames)//ticks for tick in range(ticks)]
    playback = [frames[index] for index in mapping]
    durations = [10*(round((tick+1)*100/30)-round(tick*100/30)) for tick in range(ticks)]
    playback[0].save(destination / f"{phase}-painted.gif", save_all=True, append_images=playback[1:], duration=durations, loop=0)


def report(drawings, records, pending, destination, mode):
    canonical_path = ROOT / "references/master_512.png"
    canonical = read_rgba(canonical_path)
    if canonical.size != (SIZE, SIZE):
        raise ValueError("canonical reference must be 512x512")
    canonical_measurement = measure(canonical)
    canonical_radius = canonical_measurement["radius_alpha64"]
    seams = {}
    for name, first, second in (("grow_to_loop", "grow_023.png", "loop_000.png"),
                                ("loop_wrap", "loop_023.png", "loop_000.png"),
                                ("loop_to_release", "loop_023.png", "release_000.png"),
                                ("grow_to_release", "grow_023.png", "release_000.png")):
        if first in drawings and second in drawings:
            seams[name] = {"first": first, "second": second, **difference(drawings[first], drawings[second])}
    result = {"mode": mode, "pending_phases": pending, "frame_slots": len(records),
              "unique_nonempty_painted_poses": len({row["pixel_sha256"] for row in records if row["visible_pixels"]}),
              "empty_endpoints": sum(not row["visible_pixels"] for row in records),
              "spatial_processing": "fixed 512 grid crop only; no per-frame fit, center, rotation, scaling or deformation",
              "alpha_processing": "clear alpha <=8 only in derived draft PNGs; originals unchanged",
              "canonical": {"path": "references/master_512.png", "sha256": digest(canonical_path), **canonical_measurement},
              "suggested_geometry_size_for_canonical_radius_600": 600*SIZE/canonical_radius,
              "canonical_differences": {name: difference(image, canonical) for name, image in drawings.items()},
              "seams": seams, "frames": records}
    write_json(destination, result)
    return result


def draft():
    output = ROOT / "draft_frames"
    output.mkdir(exist_ok=True)
    drawings, records, pending = {}, [], []
    for phase, (count, columns, rows, _) in PHASES.items():
        source = ROOT / "originals" / f"{phase}_{count}.png"
        if not source.exists():
            pending.append(phase)
            continue
        sheet = read_rgba(source)
        if sheet.size != (columns*SIZE, rows*SIZE):
            raise ValueError(f"{source}: expected {columns*SIZE}x{rows*SIZE}, found {sheet.size}")
        phase_drawings, phase_records = [], []
        source_hash = digest(source)
        for index in range(count):
            x, y = index % columns*SIZE, index // columns*SIZE
            crop = [x, y, x+SIZE, y+SIZE]
            image = sheet.crop(crop)
            pixels = np.array(image)
            faint = (pixels[:, :, 3] > 0) & (pixels[:, :, 3] <= 8)
            removed = int(faint.sum())
            pixels[pixels[:, :, 3] <= 8] = 0
            image = Image.fromarray(pixels)
            name = f"{phase}_{index:03}.png"
            target = output / name
            image.save(target)
            row = {"frame": name, "original": source.relative_to(ROOT).as_posix(),
                   "original_sha256": source_hash, "crop": crop, "operation": "fixed-grid generated cel",
                   "alpha_cleanup_at_or_below": 8, "removed_faint_pixels": removed,
                   "sha256": digest(target), **measure(image)}
            drawings[name] = image
            records.append(row)
            phase_drawings.append(image)
            phase_records.append(row)
        previews(phase, phase_drawings, phase_records, ROOT / "previews/draft")
    return report(drawings, records, pending, ROOT / "draft_report.json", "draft: not selected for runtime")


def final(selection_path):
    plan = json.loads(selection_path.read_text(encoding="utf8"))
    choices = plan["frames"]
    expected = {f"{phase}_{index:03}.png" for phase, (count, _, _, _) in PHASES.items() for index in range(count)}
    if len(choices) != 60 or {row["frame"] for row in choices} != expected:
        raise ValueError("final selection must explicitly name each of the 60 slots exactly once")
    prior = json.loads((ROOT / "draft_report.json").read_text(encoding="utf8"))
    draft_rows = {row["frame"]: row for row in prior["frames"]}
    for candidate_report in sorted((ROOT / "candidate_reports").glob("*.json")):
        candidate = json.loads(candidate_report.read_text(encoding="utf8"))
        for row in candidate["frames"]:
            if row["frame"] in draft_rows:
                raise ValueError(f"{candidate_report}: duplicate candidate frame {row['frame']}")
            draft_rows[row["frame"]] = row
    drawings, records = {}, []
    # Validate the entire plan before touching final frames.
    for choice in choices:
        name = choice["frame"]
        if choice.get("transparent") is True:
            if "source" in choice:
                raise ValueError(f"{name}: choose source OR transparent")
            image = Image.new("RGBA", (SIZE, SIZE))
            row = {"operation": "explicitly selected transparent endpoint"}
        else:
            source = (ROOT / choice["source"]).resolve()
            if not any(source.is_relative_to((ROOT / allowed).resolve()) for allowed in ("draft_frames", "references")):
                raise ValueError(f"{name}: selected source must stay within draft_frames or references")
            image = read_rgba(source)
            if image.size != (SIZE, SIZE):
                raise ValueError(f"{source}: selected frame must be 512x512")
            if source.parent == (ROOT / "draft_frames").resolve():
                row = dict(draft_rows[source.name])
                if digest(source) != row["sha256"]:
                    raise ValueError(f"{source}: draft changed since report; regenerate draft first")
                row["selected_draft_sha256"] = row["sha256"]
            else:
                row = {}
            row.update(operation="explicitly selected source reuse", selected_source=source.relative_to(ROOT).as_posix(), selected_source_sha256=digest(source))
        if "alpha_cleanup_at_or_below" in choice:
            threshold = choice["alpha_cleanup_at_or_below"]
            if isinstance(threshold, bool) or not isinstance(threshold, int) or not 0 <= threshold <= 255:
                raise ValueError(f"{name}: alpha_cleanup_at_or_below must be an integer 0..255")
            if choice.get("transparent"):
                raise ValueError(f"{name}: transparent endpoint needs no alpha cleanup threshold")
            pixels = np.array(image)
            alpha = pixels[:, :, 3]
            clear = alpha <= threshold
            removed = int(((alpha > 0) & clear).sum())
            pixels[clear, 3] = 0
            image = Image.fromarray(pixels)
            row.update(draft_alpha_cleanup_at_or_below=row.get("alpha_cleanup_at_or_below"),
                       alpha_cleanup_at_or_below=threshold,
                       additional_alpha_cleanup_at_or_below=threshold,
                       additional_removed_faint_pixels=removed,
                       additional_cleanup_operation="Only selected alpha bytes cleared; all RGB and other RGBA bytes retained")
        row.update(frame=name, selection_reason=choice.get("reason"), **measure(image))
        drawings[name] = image
        records.append(row)
    for name in ("grow_000.png", "release_011.png"):
        if drawings[name].getchannel("A").getbbox():
            raise ValueError(f"{name}: final endpoint must be selected transparent explicitly")
    output = ROOT / "frames"
    output.mkdir(exist_ok=True)
    for row in records:
        path = output / row["frame"]
        drawings[row["frame"]].save(path)
        row["sha256"] = digest(path)
    for phase, (count, _, _, _) in PHASES.items():
        ordered = [f"{phase}_{index:03}.png" for index in range(count)]
        by_name = {row["frame"]: row for row in records}
        previews(phase, [drawings[name] for name in ordered], [by_name[name] for name in ordered], ROOT / "previews/selected")
    result = report(drawings, records, [], ROOT / "source_selection.json", "explicit final selection")
    result["alpha_processing"] = "Draft cleanup alpha<=8; additional alpha-byte-only cleanup only for slots explicitly declaring a threshold; see per-frame provenance"
    result.update(selection_plan=str(selection_path.resolve()), selection_plan_sha256=digest(selection_path))
    write_json(ROOT / "source_selection.json", result)
    return result


def candidate(name, sheet_path, columns, count, phase):
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name) or name in PHASES:
        raise ValueError("candidate name must be a distinct lowercase identifier, e.g. release_alpha")
    if columns <= 0 or count <= 0:
        raise ValueError("candidate columns and count must be positive")
    source = sheet_path.resolve() if sheet_path.is_file() else (ROOT / sheet_path).resolve()
    if not source.is_relative_to((ROOT / "originals").resolve()):
        raise ValueError("candidate sheet must be within this asset directory's originals")
    sheet = read_rgba(source)
    expected = (columns*SIZE, ((count+columns-1)//columns)*SIZE)
    if sheet.size != expected:
        raise ValueError(f"{source}: expected {expected}, found {sheet.size}")
    output = ROOT / "draft_frames"
    output.mkdir(exist_ok=True)
    drawings, records = {}, []
    original_hash = digest(source)
    for index in range(count):
        x, y = index % columns*SIZE, index // columns*SIZE
        crop = [x, y, x+SIZE, y+SIZE]
        pixels = np.array(sheet.crop(crop))
        removed = int(((pixels[:, :, 3] > 0) & (pixels[:, :, 3] <= 8)).sum())
        pixels[pixels[:, :, 3] <= 8] = 0
        image = Image.fromarray(pixels)
        filename = f"{name}_{index:03}.png"
        path = output / filename
        image.save(path)
        row = {"frame": filename, "candidate": name, "phase": phase,
               "original": source.relative_to(ROOT).as_posix(), "original_sha256": original_hash,
               "crop": crop, "operation": "fixed-grid candidate cel; not selected for runtime",
               "alpha_cleanup_at_or_below": 8, "removed_faint_pixels": removed,
               "sha256": digest(path), **measure(image)}
        drawings[filename] = image
        records.append(row)
    previews(phase, list(drawings.values()), records, ROOT / "previews/candidates" / name, columns=columns)
    reports = ROOT / "candidate_reports"
    reports.mkdir(exist_ok=True)
    result = report(drawings, records, [], reports / f"{name}.json", f"candidate {name}: not selected for runtime")
    result.update(candidate=name, phase=phase, sheet=source.relative_to(ROOT).as_posix(),
                  columns=columns, count=count,
                  first_to_last_difference=difference(next(iter(drawings.values())), list(drawings.values())[-1]))
    write_json(reports / f"{name}.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--draft", action="store_true")
    mode.add_argument("--final", action="store_true")
    mode.add_argument("--candidate", help="distinct candidate prefix; writes draft_frames/<name>_NNN.png")
    parser.add_argument("--selection", type=Path)
    parser.add_argument("--sheet", type=Path)
    parser.add_argument("--columns", type=int)
    parser.add_argument("--count", type=int)
    parser.add_argument("--phase", choices=PHASES)
    args = parser.parse_args()
    if args.final and not args.selection:
        parser.error("--final requires --selection; no automatic endpoint or seam replacements")
    if args.candidate:
        if args.sheet is None or args.columns is None or args.count is None:
            parser.error("--candidate requires --sheet, --columns and --count")
        phase = args.phase or args.candidate.split("_")[0]
        if phase not in PHASES:
            parser.error("--phase required when candidate name does not begin grow_, loop_ or release_")
        result = candidate(args.candidate, args.sheet, args.columns, args.count, phase)
    else:
        result = final(args.selection) if args.final else draft()
    print(json.dumps({"mode": result["mode"], "frame_slots": result["frame_slots"],
                      "pending_phases": result["pending_phases"],
                      "suggested_geometry_size": result["suggested_geometry_size_for_canonical_radius_600"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
