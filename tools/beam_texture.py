"""Keep painted beam cores at mip0 without recompressing their BC3 texels.

The animation compiler always generates isotropic mips. A beam quad can be
extremely short along X while retaining its height, so those mips also average
away its thin vertical white core. Restrict only these banks to the top level.
This trades minification filtering for possible aliasing at small screen sizes;
it does not establish the cause of any particular in-game screenshot.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import struct
import tempfile
import zipfile

from animation_atlas import validate_animation_archive, validate_ktex

MIP_MASK = 31 << 13
TEXTURE_POLICY = {
    "mip_levels": 1,
    "method": "retain compiler mip0 table and compressed payload verbatim; remove lower mips",
    "reason": "avoid isotropic mip averaging of the white core on extremely short beam quads",
    "tradeoff": "full-resolution sampling may alias or shimmer at small screen sizes",
    "validation_limit": "not an in-game GPU LOD comparison or proof of screenshot root cause",
}


def mip0_parts(data: bytes) -> tuple[int, bytes, bytes]:
    """Validate first, then locate the top-level table entry and stored payload."""
    validate_ktex(data, "beam texture")
    flags, = struct.unpack_from("<I", data, 4)
    levels = (flags >> 13) & 31
    length, = struct.unpack_from("<I", data, 14)
    start = 8 + levels * 10
    return flags, data[8:18], data[start:start + length]


def retain_mip0(data: bytes) -> bytes:
    """Change only mipcount/table layout/tail; never decode or recompress pixels."""
    flags, entry, payload = mip0_parts(data)
    result = b"KTEX" + struct.pack("<I", (flags & ~MIP_MASK) | (1 << 13)) + entry + payload
    validate_ktex(result, "single-level beam texture")
    return result


def retain_archive_mip0(path: Path) -> dict:
    """Atomically replace textures, preserving every other member and ZipInfo."""
    path = Path(path)
    validate_animation_archive(path)
    records, textures = [], []
    with zipfile.ZipFile(path) as archive:
        comment = archive.comment
        for info in archive.infolist():
            data = archive.read(info)
            result = retain_mip0(data) if info.filename.endswith(".tex") else data
            records.append((info, result))
            if info.filename.endswith(".tex"):
                flags, entry, payload = mip0_parts(data)
                textures.append({"member": info.filename,
                                 "previous_mip_levels": (flags >> 13) & 31,
                                 "mip_levels": 1,
                                 "mip0_table_hex": entry.hex(),
                                 "mip0_sha256": hashlib.sha256(payload).hexdigest(),
                                 "before_bytes": len(data), "after_bytes": len(result)})
    if any(item["previous_mip_levels"] != 1 for item in textures):
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=path.parent, suffix=".zip", delete=False) as handle:
                temporary = Path(handle.name)
            with zipfile.ZipFile(temporary, "w") as archive:
                archive.comment = comment
                for info, data in records:
                    archive.writestr(info, data)
            validate_animation_archive(temporary)
            temporary.replace(path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return {"policy": TEXTURE_POLICY, "textures": textures,
            "archive_validation": validate_animation_archive(path)}
