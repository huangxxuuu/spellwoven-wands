"""Verify lossless removal of the destructive beam minification levels."""
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from animation_atlas import AnimationAtlasError, validate_animation_archive
from beam_texture import MIP_MASK, mip0_parts, retain_archive_mip0, retain_mip0
from build_end_beam import make_bank, prepare_art
from native_animation import read_animation, read_build


def sample_texture(pixel_format=2):
    flags = (3 << 13) | (pixel_format << 4) | (1 << 2) | (1 << 20)
    entries, payloads = [], []
    for level, size in enumerate((8, 4, 2)):
        length = size * size * 4 if pixel_format == 4 else ((size + 3) // 4) ** 2 * (8 if pixel_format == 0 else 16)
        entries.append(struct.pack("<HHHI", size, size, size * 4, length))
        payloads.append(bytes([50 + level]) * length)
    return b"KTEX" + struct.pack("<I", flags) + b"".join(entries + payloads)


class BeamTexture(unittest.TestCase):
    def test_visual_sixteenths_reassemble_the_continuous_periodic_material(self):
        _, animations, images, manifest = make_bank()
        clips = {clip.attrib["name"]: clip for clip in animations}
        band, _ = prepare_art()
        periodic = Image.new("RGBA", (band.width * 3, band.height))
        for cycle in range(3):
            periodic.paste(band, (cycle * band.width, 0))
        expected_band = periodic.resize((band.width * 6, 64), Image.Resampling.LANCZOS).crop(
            (band.width * 2, 0, band.width * 4, 64))
        self.assertEqual(manifest["visual_parts_per_slice"], 16)
        self.assertEqual(manifest["visual_part_pixels"], [21, 64])
        self.assertEqual(manifest["visual_part_native_length"], 18.75)
        for index in range(16):
            expected = ImageChops.offset(expected_band, index * 84, 0)
            reconstructed = Image.new("RGBA", expected.size)
            for piece in range(4):
                original = images[f"beam_{piece}_{index}"]
                self.assertEqual(original.size, (168, 64))
                self.assertEqual(original.tobytes(), ImageChops.offset(band, index * 42, 0).crop(
                    (piece * 168, 0, (piece + 1) * 168, 64)).tobytes())
                self.assertEqual(len(clips[f"beam_{piece}"]), 16)
                for part in range(16):
                    image = images[f"beam_{piece}_part_{part}_{index}"]
                    self.assertEqual(image.size, (21, 64))
                    left = piece * 336 + part * 21
                    self.assertEqual(image.tobytes(), expected.crop((left, 0, left + 21, 64)).tobytes())
                    reconstructed.paste(image, (left, 0))
                    pose = clips[f"beam_{piece}_part_{part}"][index]
                    self.assertEqual((pose.attrib["w"], pose.attrib["h"]), ("18.75", "64"))
                    self.assertAlmostEqual(float(pose[0].attrib["m_a"]) * 21, 18.75)
                    self.assertEqual(clips[f"beam_{piece}_part_{part}"].attrib["framerate"], "30")
                    self.assertEqual(len(clips[f"beam_{piece}_part_{part}"]), 16)
            self.assertEqual(reconstructed.tobytes(), expected.tobytes(), f"all 64 parts at frame {index}")

    def test_compiled_parts_keep_native_size_and_animation_phase(self):
        with zipfile.ZipFile(ROOT / "mod/anim/nw_end_beam.zip") as archive:
            compiled = {clip["name"]: clip for clip in read_animation(archive.read("anim.bin"))}
            build = read_build(archive.read("build.bin"))
        self.assertEqual(len(compiled), 4 + 4 * 16 + 1)
        for piece in range(4):
            self.assertIn(f"beam_{piece}", compiled)
            for part in range(16):
                clip = compiled[f"beam_{piece}_part_{part}"]
                self.assertEqual(clip["fps"], 30)
                self.assertEqual(len(clip["frames"]), 16)
                for index, pose in enumerate(clip["frames"]):
                    self.assertEqual(len(pose["elements"]), 1)
                    symbol, _, _, scale_x, _, _, scale_y, _, _, _ = pose["elements"][0]
                    self.assertEqual(build["names"][symbol], f"beam_{piece}_part_{part}_{index}")
                    self.assertAlmostEqual(scale_x * 21, 18.75, places=5)
                    self.assertEqual(scale_y, 1)
        self.assertLessEqual(validate_animation_archive(ROOT / "mod/anim/nw_end_beam.zip")["atlas_count"], 2)

    def test_header_table_payload_and_idempotence(self):
        for fmt in (0, 1, 2, 4):
            with self.subTest(pixel_format=fmt):
                before = sample_texture(fmt)
                after = retain_mip0(before)
                flags, entry, payload = mip0_parts(before)
                result_flags, result_entry, result_payload = mip0_parts(after)
                self.assertEqual(result_flags & ~MIP_MASK, flags & ~MIP_MASK)
                self.assertEqual((result_flags >> 13) & 31, 1)
                self.assertEqual(result_entry, entry)
                self.assertEqual(result_payload, payload)
                self.assertEqual(len(after), 18 + len(payload))
                self.assertEqual(retain_mip0(after), after)

    def test_invalid_input_is_rejected(self):
        for data in (b"bad!", sample_texture()[:-1], sample_texture() + b"tail"):
            with self.assertRaises(AnimationAtlasError):
                retain_mip0(data)

    def test_archive_preserves_non_texture_members_and_metadata(self):
        # Use the real BILD/ANIM structure and every real atlas, but add lower
        # levels to its unchanged mip0 so this remains meaningful after shipping.
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "beam.zip"
            with zipfile.ZipFile(ROOT / "mod/anim/nw_end_beam.zip") as original:
                members = {info.filename: original.read(info) for info in original.infolist()}
                for name, data in members.items():
                    if not name.endswith(".tex"):
                        continue
                    flags, entry, payload = mip0_parts(data)
                    width, height, _, _ = struct.unpack("<HHHI", entry)
                    width, height = max(1, width // 2), max(1, height // 2)
                    fmt = (flags >> 4) & 31
                    length = width * height * 4 if fmt == 4 else ((width + 3) // 4) * ((height + 3) // 4) * (8 if fmt == 0 else 16)
                    members[name] = (b"KTEX" + struct.pack("<I", (flags & ~MIP_MASK) | (2 << 13))
                                     + entry + struct.pack("<HHHI", width, height, width * 4, length)
                                     + payload + bytes(length))
                with zipfile.ZipFile(target, "w") as archive:
                    archive.comment = b"preserve archive comment"
                    for info in original.infolist():
                        archive.writestr(info, members[info.filename])
            with zipfile.ZipFile(target) as archive:
                before_info = [(i.filename, i.date_time, i.compress_type, i.external_attr) for i in archive.infolist()]
            retain_archive_mip0(target)
            first = target.read_bytes()
            with zipfile.ZipFile(target) as archive:
                self.assertEqual(archive.comment, b"preserve archive comment")
                self.assertEqual([(i.filename, i.date_time, i.compress_type, i.external_attr) for i in archive.infolist()], before_info)
                for name, before in members.items():
                    after = archive.read(name)
                    if name.endswith(".tex"):
                        self.assertEqual(mip0_parts(before)[1:], mip0_parts(after)[1:])
                    else:
                        self.assertEqual(after, before, name)
            retain_archive_mip0(target)
            self.assertEqual(target.read_bytes(), first)
            validate_animation_archive(target)

    def test_both_shipped_banks_have_only_mip0(self):
        for bank in ("nw_end_beam", "nw_end_beam_head"):
            path = ROOT / f"mod/anim/{bank}.zip"
            validate_animation_archive(path)
            with zipfile.ZipFile(path) as archive:
                textures = [name for name in archive.namelist() if name.endswith(".tex")]
                self.assertTrue(textures)
                for name in textures:
                    self.assertEqual((mip0_parts(archive.read(name))[0] >> 13) & 31, 1)


if __name__ == "__main__":
    unittest.main()
