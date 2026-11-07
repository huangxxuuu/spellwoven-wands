"""Read installed DST animation art for deterministic native-art reuse/previews."""
from __future__ import annotations
import io
import math
import struct
import zipfile
from pathlib import Path
from PIL import Image

GAME = Path("E:/SteamLibrary/steamapps/common/Don't Starve Together")


class Reader:
    def __init__(self, data): self.stream = io.BytesIO(data)
    def read(self, count): return self.stream.read(count)
    def unpack(self, fmt): return struct.unpack('<' + fmt, self.read(struct.calcsize('<' + fmt)))
    def string(self): return self.read(self.unpack('I')[0]).decode('utf8')


def texture(data):
    assert data[:4] == b'KTEX'
    flags, = struct.unpack_from('<I', data, 4)
    levels = (flags >> 13) & 31
    width, height, _, length = struct.unpack_from('<HHHI', data, 8)
    pixels = data[8 + levels * 10:8 + levels * 10 + length]
    fmt = (flags >> 4) & 31
    if fmt == 4:
        image = Image.frombytes('RGBA', (width, height), pixels)
    else:
        image = Image.frombytes('RGBA', (width, height), pixels, 'bcn', {0: 1, 1: 2, 2: 3}[fmt])
    return image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)


def read_build(data):
    r = Reader(data)
    assert r.read(4) == b'BILD'
    version, count, _ = r.unpack('III')
    assert version == 6
    result = {'name': r.string(), 'atlases': [r.string() for _ in range(r.unpack('I')[0])]}
    frames = {}
    for _ in range(count):
        key, n = r.unpack('II')
        frames[key] = [r.unpack('IIffffII') for _ in range(n)]
    result['vertices'] = [r.unpack('ffffff') for _ in range(r.unpack('I')[0])]
    names = {}
    for _ in range(r.unpack('I')[0]):
        key, = r.unpack('I'); names[key] = r.string()
    result['names'], result['frames'] = names, frames
    return result


def read_animation(data):
    r = Reader(data)
    assert r.read(4) == b'ANIM'
    version, _, _, _, count = r.unpack('IIIII')
    clips = []
    for _ in range(count):
        name = r.string()
        facing, root, fps, n = r.unpack('BIfI')
        poses = []
        for _ in range(n):
            bounds = r.unpack('ffff')
            events = [r.unpack('I')[0] for _ in range(r.unpack('I')[0])]
            elements = [r.unpack('IIIfffffff') for _ in range(r.unpack('I')[0])]
            poses.append({'bounds': bounds, 'events': events, 'elements': elements})
        clips.append({'name': name, 'facing': facing, 'root': root, 'fps': fps, 'frames': poses})
    return clips


class NativeAnimation:
    def __init__(self, name, game=GAME, build_name=None):
        with zipfile.ZipFile(game / 'data/anim' / (name + '.zip')) as archive:
            self.clips = read_animation(archive.read('anim.bin'))
        with zipfile.ZipFile(game / 'data/anim' / ((build_name or name) + '.zip')) as archive:
            self.build = read_build(archive.read('build.bin'))
            self.atlases = [texture(archive.read(path)) for path in self.build['atlases']]
        self.cache = {}

    def symbol(self, key, frame=0):
        if isinstance(key, str):
            key = next(k for k, name in self.build['names'].items() if name == key)
        row = next(row for row in self.build['frames'][key] if row[0] <= frame < row[0] + row[1])
        cache_key = key, row[0]
        if cache_key in self.cache: return self.cache[cache_key]
        vertices = self.build['vertices'][row[6]:row[6] + row[7]]
        left, top = math.floor(min(v[0] for v in vertices)), math.floor(min(v[1] for v in vertices))
        right, bottom = math.ceil(max(v[0] for v in vertices)), math.ceil(max(v[1] for v in vertices))
        out = Image.new('RGBA', (right - left, bottom - top))
        # The build compiler stores each trimmed rectangle as two triangles.
        for index in range(0, len(vertices), 6):
            quad = vertices[index:index + 6]
            x0, y0 = min(v[0] for v in quad), min(v[1] for v in quad)
            x1, y1 = max(v[0] for v in quad), max(v[1] for v in quad)
            dest = (round(x0 - left), round(y0 - top), round(x1 - left), round(y1 - top))
            atlas = self.atlases[round(quad[0][5])]
            u0, v0 = min(v[3] for v in quad), min(v[4] for v in quad)
            u1, v1 = max(v[3] for v in quad), max(v[4] for v in quad)
            piece = atlas.crop((round(u0 * atlas.width), round((1 - v1) * atlas.height),
                                round(u1 * atlas.width), round((1 - v0) * atlas.height)))
            # Native atlases keep rectangle axes aligned; record any future
            # rotated packing instead of silently producing incorrect artwork.
            for vx, vy, _, u, v, _ in quad:
                assert abs((vx - x0) / max(.001, x1 - x0) - (u - u0) / max(.000001, u1 - u0)) < .001
                assert abs((vy - y0) / max(.001, y1 - y0) - (v1 - v) / max(.000001, v1 - v0)) < .001
            piece = piece.resize((dest[2] - dest[0], dest[3] - dest[1]), Image.Resampling.LANCZOS)
            out.alpha_composite(piece, dest[:2])
        result = out, (left, top)
        self.cache[cache_key] = result
        return result

    def clip(self, name, facing=None):
        return next(clip for clip in self.clips if clip['name'] == name and (facing is None or clip['facing'] == facing))

    def render_frame(self, name, index=0, facing=None):
        """Return RGBA and its top-left in native animation coordinates."""
        clip = self.clip(name, facing)
        elements = clip['frames'][index % len(clip['frames'])]['elements']
        bounds = []
        parts = []
        for key, frame, layer, a, b, c, d, tx, ty, depth in elements:
            if key not in self.build['frames']: continue
            image, (sx, sy) = self.symbol(key, frame)
            corners = [(a * x + c * y + tx, b * x + d * y + ty)
                       for x in (sx, sx + image.width) for y in (sy, sy + image.height)]
            bounds.extend(corners)
            parts.append((depth, image, sx, sy, a, b, c, d, tx, ty))
        if not bounds: return Image.new('RGBA', (1, 1)), (0, 0)
        left, top = math.floor(min(p[0] for p in bounds)), math.floor(min(p[1] for p in bounds))
        right, bottom = math.ceil(max(p[0] for p in bounds)), math.ceil(max(p[1] for p in bounds))
        out = Image.new('RGBA', (right - left, bottom - top))
        for _, image, sx, sy, a, b, c, d, tx, ty in sorted(parts, key=lambda part: part[0], reverse=True):
            det = a * d - b * c
            if abs(det) < 1e-8: continue
            transform = (d / det, -c / det, (d * (left - tx) - c * (top - ty)) / det - sx,
                         -b / det, a / det, (-b * (left - tx) + a * (top - ty)) / det - sy)
            out.alpha_composite(image.transform(out.size, Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC))
        return out, (left, top)
