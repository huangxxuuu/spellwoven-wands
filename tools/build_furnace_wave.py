"""Compile painted ground-plane frame sequences with hold-only timing.

No movement, deformation, fade or interpolation is synthesized by this tool.
Source frames are straight RGBA, 512 square, registered at (256, 256).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile, ZIP_DEFLATED

from PIL import Image

from animation_atlas import AnimationAtlasError, validate_animation_archive

ROOT = Path(__file__).resolve().parents[1]
BANK = "nw_furnace_wave"
FPS = 30
SOURCE_SIZE = 512
OUT = ROOT / "assets_src/disassembler_wave_perimeter_animation_20261114"
GEOMETRY_SIZE = 1201.4215895  # Measured loop_000 alpha64 radius 255.6970864 -> 600 units.
MOD_TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")
CLIPS = {"grow": (24, 60), "loop": (24, 60), "release": (12, 18)}


def timeline_mapping(source_count, ticks):
    """Sample cumulative source time; adjacent holds distribute rounding error."""
    return [tick * source_count // ticks for tick in range(ticks)]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def register_compiled_geometry(archive, scale):
    """Klei uses image pixels for vertices; scale BILD once, never ANIM.

    XML w/h only affect the pivot in this compiler. Bounds and vertices must
    therefore receive the same constant conversion after texture packing.
    """
    with ZipFile(archive) as package:
        files = {name: package.read(name) for name in package.namelist()}
    data = bytearray(files["build.bin"])
    magic, version, symbols, _ = struct.unpack_from("<4sIII", data)
    if (magic, version) != (b"BILD", 6):
        raise ValueError("geometry registration requires BILD v6")
    offset = 16

    def skip_string():
        nonlocal offset
        length, = struct.unpack_from("<I", data, offset)
        offset += 4 + length

    skip_string()
    pages, = struct.unpack_from("<I", data, offset)
    offset += 4
    for _ in range(pages):
        skip_string()
    for _ in range(symbols):
        _, frames = struct.unpack_from("<II", data, offset)
        offset += 8
        for _ in range(frames):
            bounds = struct.unpack_from("<ffff", data, offset + 8)
            struct.pack_into("<ffff", data, offset + 8, *(value * scale for value in bounds))
            offset += 32
    vertices, = struct.unpack_from("<I", data, offset)
    offset += 4
    for _ in range(vertices):
        x, y = struct.unpack_from("<ff", data, offset)
        struct.pack_into("<ff", data, offset, x * scale, y * scale)
        offset += 24
    files["build.bin"] = data
    temporary = archive.with_suffix(".geometry.tmp")
    try:
        with ZipFile(temporary, "w", ZIP_DEFLATED) as package:
            for name, payload in files.items():
                package.writestr(name, payload)
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)


class WaveBank:
    def __init__(self, source_dir=OUT, geometry_size=GEOMETRY_SIZE, texture_size=384):
        if geometry_size <= 0 or not 1 <= texture_size <= SOURCE_SIZE:
            raise ValueError("geometry-size must be positive; texture-size must be 1..512")
        self.source_dir = Path(source_dir)
        self.geometry_size, self.texture_size = geometry_size, texture_size
        self.build = ET.Element("Build", name=BANK)
        self.animations = ET.Element("Anims")
        self.images, self.sources, self.clips = {}, [], {}
        symbol = ET.SubElement(self.build, "Symbol", name="wave")
        missing = [f"{clip}_{i:03}.png" for clip, (count, _) in CLIPS.items()
                   for i in range(count) if not (self.source_dir / "frames" / f"{clip}_{i:03}.png").is_file()]
        if missing:
            raise ValueError(f"Missing {len(missing)} independently painted frames in {self.source_dir / 'frames'}: "
                             + ", ".join(missing))
        start = 0
        for clip, (count, ticks) in CLIPS.items():
            mapping = timeline_mapping(count, ticks)
            self.clips[clip] = {"source_frames": count, "frames": ticks, "fps": FPS,
                                "seconds": ticks / FPS, "loop": clip == "loop",
                                "timeline_to_source": mapping,
                                "timeline_to_build": [start + i for i in mapping]}
            for index in range(count):
                path = self.source_dir / "frames" / f"{clip}_{index:03}.png"
                with Image.open(path) as original:
                    if original.mode != "RGBA" or original.size != (SOURCE_SIZE, SOURCE_SIZE):
                        raise ValueError(f"{path}: expected straight RGBA 512x512, found {original.mode} {original.size}")
                    image = original.copy()
                bounds = image.getchannel("A").getbbox()
                if (clip, index) in (("grow", 0), ("release", count - 1)) and bounds:
                    raise ValueError(f"{path}: animation endpoint must be fully transparent")
                # One global sampling grid preserves scale and origin across
                # every drawing. Crop only AFTER sampling, never fit each pose.
                alpha = image.getchannel("A")
                histogram = alpha.histogram()
                dust_pixels = sum(histogram[1:9])
                image.putalpha(alpha.point(lambda value: 0 if value <= 8 else value))
                sampled = image.resize((texture_size, texture_size), Image.Resampling.LANCZOS)
                crop = sampled.getchannel("A").getbbox() or (texture_size // 2, texture_size // 2,
                                                            texture_size // 2 + 1, texture_size // 2 + 1)
                texture = sampled.crop(crop)
                name = f"{clip}_{index:03}"
                self.images[name] = texture
                scale = geometry_size / texture_size
                x = ((crop[0] + crop[2]) / 2 - texture_size / 2) * scale
                y = ((crop[1] + crop[3]) / 2 - texture_size / 2) * scale
                ET.SubElement(symbol, "Frame", framenum=str(start + index), duration="1", image=name,
                              x=str(x / scale), y=str(y / scale), w=str(texture.width), h=str(texture.height))
                self.sources.append({"key": name, "path": str(path.resolve()), "sha256": sha256(path),
                                     "clip": clip, "source_index": index, "build_frame": start + index,
                                     "size": list(image.size), "alpha_bounds": bounds,
                                     "alpha_cleanup_pixels": dust_pixels,
                                     "clean_alpha_bounds": image.getchannel("A").getbbox(),
                                     "texture_crop": crop, "texture_size": list(texture.size),
                                     "geometry_center": [x, y],
                                     "geometry_size": [texture.width * scale, texture.height * scale]})
            animation = ET.SubElement(self.animations, "anim", name=clip, root=BANK, framerate=str(FPS))
            for source_index in mapping:
                frame = ET.SubElement(animation, "frame", x="0", y="0", w=str(geometry_size), h=str(geometry_size))
                ET.SubElement(frame, "element", name="wave", frame=str(start + source_index),
                              layername="wave", z_index="0", m_a="1", m_b="0", m_c="0", m_d="1", m_tx="0", m_ty="0")
            start += count

    def save_sources(self):
        manifest = {"bank": BANK, "generation": "Painted cel sequences with transparent endpoints and shared seam poses; cumulative hold-only playback",
                    "orientation": "OnGround", "source_size": [512, 512], "source_origin": [256, 256],
                    "pixels_per_world_unit": 150, "gameplay_radius": 4,
                    "geometry_size": self.geometry_size, "texture_size": self.texture_size,
                    "geometry_units_per_source_pixel": self.geometry_size / SOURCE_SIZE,
                    "compiled_build_geometry_scale": self.geometry_size / self.texture_size,
                    "texture_sampling": "uniform full-canvas Lanczos then transparent crop; no per-frame fit",
                    "alpha_cleanup": "only source alpha <= 8 cleared in derived textures; original PNGs preserved",
                    "element_matrix": [1, 0, 0, 1, 0, 0],
                    "frame_slots": len(self.sources),
                    "unique_nonempty_painted_poses": len({row["sha256"] for row in self.sources if row["alpha_bounds"]}),
                    "sources": self.sources, "clips": self.clips}
        self.write_manifest(manifest)
        return manifest

    def write_manifest(self, manifest):
        self.source_dir.mkdir(parents=True, exist_ok=True)
        (self.source_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf8")


def build_bank(source_dir=OUT, geometry_size=GEOMETRY_SIZE, texture_size=384):
    return WaveBank(source_dir, geometry_size, texture_size)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", type=Path, default=MOD_TOOLS)
    parser.add_argument("--source-dir", type=Path, default=OUT)
    parser.add_argument("--geometry-size", type=float, default=GEOMETRY_SIZE)
    parser.add_argument("--texture-size", type=int, default=384)
    parser.add_argument("--no-compile", action="store_true")
    args = parser.parse_args()
    bank = build_bank(args.source_dir, args.geometry_size, args.texture_size)
    manifest = bank.save_sources()
    if not args.no_compile:
        from build_art_assets import compile_bank
        archive = ROOT / "mod/anim" / f"{BANK}.zip"
        previous_archive = archive.read_bytes() if archive.exists() else None
        try:
            compile_bank(BANK, bank.build, bank.animations, bank.images, args.tools)
            register_compiled_geometry(archive, bank.geometry_size / bank.texture_size)
            manifest["archive_validation"] = validate_animation_archive(archive, max_pages=2)
        except Exception as error:
            if previous_archive is None:
                archive.unlink(missing_ok=True)
            else:
                recovery = archive.with_suffix(".recovery.tmp")
                recovery.write_bytes(previous_archive)
                recovery.replace(archive)
            if isinstance(error, AnimationAtlasError):
                raise SystemExit(f"{error}\nPrevious archive restored. All 60 frame slots retained. Retry --texture-size 320 (or 288) with the same --geometry-size; no automatic frame reduction.") from error
            raise
        manifest.update(archive_bytes=archive.stat().st_size, archive_sha256=sha256(archive))
        with ZipFile(archive) as package:
            manifest["atlas_outputs"] = [{"name": name, "bytes": package.getinfo(name).file_size,
                                          "sha256": hashlib.sha256(package.read(name)).hexdigest()}
                                         for name in package.namelist() if name.endswith(".tex")]
        bank.write_manifest(manifest)
    print(json.dumps({"bank": BANK, "source_frames": len(bank.sources), "clips": bank.clips,
                      "output": str(bank.source_dir)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
