"""Repose native shock_fx electricity; the runtime still uses its original build.

Only an animation bank is emitted. No original texture is copied or repainted.
The ANIM v4 layout matches Klei's buildanimation.py ExportAnim writer.
"""
from __future__ import annotations
import io
import json
import math
import struct
import zipfile
from pathlib import Path
from native_animation import NativeAnimation, read_animation

ROOT = Path(__file__).resolve().parents[1]
BANK = "nw_electric_arc"
DIRECTIONS = 256
LENGTH = 112


def name_hash(name):
    value = 0
    for char in name.lower():
        value = (ord(char) + value * 65599) & 0xffffffff
    return value


def endpoint_pose(native, frame):
    """Align tapered native arc endpoints, retaining its jagged curved stroke."""
    image, (ox, oy) = native.symbol("bolt_arc_side", frame)
    alpha = image.getchannel("A")
    left, top, right, bottom = alpha.point(lambda a: 255 if a > 32 else 0).getbbox()
    def tip_y(x0, x1):
        points = [(y, alpha.getpixel((x, y))) for x in range(x0, x1)
                  for y in range(top, bottom) if alpha.getpixel((x, y)) > 32]
        return sum(y * a for y, a in points) / sum(a for _, a in points) + oy
    x0, x1 = left + ox, right - 1 + ox
    y0, y1 = tip_y(left, left + 3), tip_y(right - 3, right)
    return x0, y0, x1, y1


def build(bank=BANK, destination=None, manifest=True):
    native = NativeAnimation("shock_fx")
    symbol = name_hash("bolt_arc_side")
    assert symbol in native.build["frames"]
    endpoints = {frame: endpoint_pose(native, frame) for frame in (3, 5)}
    output = io.BytesIO()
    def pack(fmt, *values): output.write(struct.pack("<" + fmt, *values))
    def string(value):
        data = value.encode("utf8"); pack("I", len(data)); output.write(data)
    output.write(b"ANIM"); pack("IIIII", 4, DIRECTIONS * 4, DIRECTIONS * 4, 0, DIRECTIONS)
    for direction in range(DIRECTIONS):
        string(f"arc_{direction}"); pack("BIfI", 255, name_hash(bank), 30, 4)
        angle = math.tau * direction / DIRECTIONS
        c, s = math.cos(angle), math.sin(angle)
        for frame, height in ((3, .30), (5, -.28), (3, -.25), (5, .32)):
            x0, y0, x1, y1 = endpoints[frame]
            sx, shear = LENGTH / (x1 - x0), -(y1 - y0) / (x1 - x0) * height
            tx, ty = -LENGTH / 2 - sx * x0, -height * y0 - shear * x0
            a, b, cc, d = c * sx - s * shear, s * sx + c * shear, -s * height, c * height
            tx, ty = c * tx - s * ty, s * tx + c * ty
            # Generous rotated bounds prevent culling the jagged off-axis arc.
            pack("ffffII", 0, 0, 180, 180, 0, 1)
            pack("IIIfffffff", symbol, frame, symbol, a, b, cc, d, tx, ty, -5)
    names = (bank, "bolt_arc_side")
    pack("I", len(names))
    for name in names: pack("I", name_hash(name)); string(name)
    data = output.getvalue()
    clips = read_animation(data)
    assert len(clips) == DIRECTIONS and all(len(c["frames"]) == 4 for c in clips)
    destination = Path(destination) if destination is not None else ROOT / "mod/anim" / (bank + ".zip")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        info = zipfile.ZipInfo("anim.bin", date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
    if manifest:
        record = {"bank": bank, "build": "shock_fx", "native_symbol": "bolt_arc_side",
                  "native_frames": [3, 5], "fps": 30, "frames": 4, "directions": DIRECTIONS,
                  "span_pixels": LENGTH, "notes": "Animation matrices only; uses installed native textures"}
        path = ROOT / "assets_src/electric_arc"
        path.mkdir(parents=True, exist_ok=True)
        (path / "manifest.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf8")
    print(f"{destination.name}: {DIRECTIONS} directions; native shock_fx build; {destination.stat().st_size} bytes")
    return destination


if __name__ == "__main__": build()
