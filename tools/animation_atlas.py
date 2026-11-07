"""Reject compiled animation builds the default DST shader cannot sample.

The normal anim shader selects atlas 0 for sampler < .5 and atlas 1 for every
other value. A compiler-successful third page therefore renders unrelated art.
Inspect the final BILD vertex data, including archives restored from a cache.
"""
from __future__ import annotations

import math
from pathlib import Path
import struct
import zipfile


class AnimationAtlasError(ValueError):
    """An animation archive cannot be rendered by the supported shader."""


def validate_ktex(data: bytes, label: str) -> None:
    """Check the actual texture header and every declared mip payload."""
    def fail(message):
        raise AnimationAtlasError(f"{label}: {message}")

    if len(data) < 8 or data[:4] != b"KTEX":
        fail("invalid KTEX header")
    flags, = struct.unpack_from("<I", data, 4)
    levels, pixel_format = (flags >> 13) & 31, (flags >> 4) & 31
    if levels == 0 or len(data) < 8 + levels * 10:
        fail("missing or truncated KTEX mip table")
    end = 8 + levels * 10
    previous = None
    for level in range(levels):
        width, height, pitch, length = struct.unpack_from("<HHHI", data, 8 + level * 10)
        if width == 0 or height == 0 or pitch == 0 or length == 0:
            fail(f"invalid KTEX mip {level} dimensions/payload")
        if previous and (width, height) != (max(1, previous[0] // 2), max(1, previous[1] // 2)):
            fail(f"invalid KTEX mip {level} dimensions")
        if pixel_format in (0, 1, 2):
            expected = ((width + 3) // 4) * ((height + 3) // 4) * (8 if pixel_format == 0 else 16)
        elif pixel_format == 4:
            expected = width * height * 4
        else:
            fail(f"unsupported KTEX pixel format {pixel_format}")
        if length != expected:
            fail(f"invalid KTEX mip {level} byte length {length}, expected {expected}")
        end += length
        previous = width, height
    if end != len(data):
        fail(f"KTEX payload length mismatch: declared {end} bytes, found {len(data)}")


def validate_animation_archive(path: Path, max_pages: int = 2) -> dict:
    path = Path(path)

    def fail(message):
        raise AnimationAtlasError(f"{path.name}: {message}")

    with zipfile.ZipFile(path) as archive:
        files = set(archive.namelist())
        if "build.bin" not in files:
            if "anim.bin" not in files or archive.read("anim.bin")[:4] != b"ANIM":
                fail("missing animation/build data")
            # Animation-only banks intentionally use a separate native build.
            return {"archive": str(path), "atlas_count": 0, "vertex_count": 0,
                    "animation_only": True}

        data = archive.read("build.bin")
        offset = 0

        def unpack(fmt):
            nonlocal offset
            length = struct.calcsize("<" + fmt)
            if offset + length > len(data):
                fail("truncated build.bin")
            values = struct.unpack_from("<" + fmt, data, offset)
            offset += length
            return values

        def string():
            nonlocal offset
            length, = unpack("I")
            if offset + length > len(data):
                fail("truncated build string")
            result = data[offset:offset + length].decode("utf8")
            offset += length
            return result

        magic, version, symbols, _ = unpack("4sIII")
        if magic != b"BILD" or version != 6:
            fail("expected a BILD v6 build")
        name = string()
        pages, = unpack("I")
        if pages > max_pages:
            fail(f"{pages} atlas pages exceed the supported {max_pages}; "
                 "extra pages sample the wrong artwork")
        atlases = [string() for _ in range(pages)]
        for atlas in atlases:
            if atlas not in files:
                fail(f"missing declared atlas {atlas}")
            validate_ktex(archive.read(atlas), f"{path.name}:{atlas}")
        for _ in range(symbols):
            _, frames = unpack("II")
            # Frame number/duration, bounds, and vertex start/count.
            for _ in range(frames):
                unpack("IIffffII")
        vertices, = unpack("I")
        for index in range(vertices):
            *_, sampler = unpack("ffffff")
            if not math.isfinite(sampler) or not sampler.is_integer() or not 0 <= sampler < pages:
                fail(f"vertex {index} has sampler {sampler!r} outside declared integer pages 0..{pages-1}")
        return {"archive": str(path), "build": name, "atlas_count": pages,
                "vertex_count": vertices, "animation_only": False}
