"""Decode the shipped Klei banks and check the ground art for every registered card."""
import io
import struct
import zipfile

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageStat

from build_art_assets import CARD_CANVAS, CARD_DEPTHS, ROOT, SOURCE, card_face, ground_face, icon


class Reader(io.BytesIO):
    def fields(self, fmt):
        fmt = "<" + fmt
        return struct.unpack(fmt, self.read(struct.calcsize(fmt)))

    def number(self):
        return self.fields("I")[0]

    def string(self):
        return self.read(self.number()).decode("ascii")


def read_bank(bank):
    with zipfile.ZipFile(ROOT / "mod/anim" / (bank + ".zip")) as archive:
        build = Reader(archive.read("build.bin"))
        anim = Reader(archive.read("anim.bin"))
        assert build.read(4) == b"BILD"
        version, symbols, _ = build.fields("III")
        assert version == 6 and build.string() == bank and build.number() == 1
        tex = archive.read(build.string())
    assert tex[:4] == b"KTEX"
    flags, = struct.unpack_from("<I", tex, 4)
    assert (flags >> 4) & 31 == 2  # BC3
    w, h, _, length = struct.unpack_from("<HHHI", tex, 8)
    offset = 8 + 10 * ((flags >> 13) & 31)
    atlas = ImageOps.flip(Image.frombytes("RGBA", (w, h), tex[offset:offset+length], "bcn", 3))
    frames = {}
    for _ in range(symbols):
        key, n = build.fields("II")
        assert n == 1
        frames[key] = build.fields("IIffffII")
    vertices = [build.fields("ffffff") for _ in range(build.number())]
    sprites = {}
    names = {}
    for _ in range(build.number()):
        key, name = build.number(), build.string()
        names[key] = name
        _, _, cx, cy, width, height, start, count = frames[key]
        sprite = Image.new("RGBA", CARD_CANVAS)
        for i in range(start, start+count, 6):
            rect = vertices[i:i+6]
            assert all(v[5] == 0 for v in rect), name
            xs = [round(v[3]*w) for v in rect]
            ys = [round((1-v[4])*h) for v in rect]
            dx = round(min(v[0] for v in rect) + CARD_CANVAS[0]/2)
            dy = round(min(v[1] for v in rect) + CARD_CANVAS[1]/2)
            sprite.paste(atlas.crop((min(xs), min(ys), max(xs), max(ys))), (dx, dy))
        sprites[name] = sprite
    assert anim.read(4) == b"ANIM"
    version, _, _, _, nclips = anim.fields("IIIII")
    assert version == 4
    clips = {}
    for _ in range(nclips):
        clip = anim.string()
        _, _, _, nframes = anim.fields("BIfI")
        assert nframes == 1
        anim.fields("ffff")
        assert anim.number() == 0
        layers = []
        for _ in range(anim.number()):
            sym, idx, _, a, b, c, d, x, y, _ = anim.fields("IIIfffffff")
            assert (idx,a,b,c,d) == (0,1,0,0,1)
            layers.append((names[sym],x,y))
        clips[clip] = layers
    return sprites, clips


def check_ground_cards():
    vm = LuaRuntime()
    vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
    codes = dict(vm.eval('require("nw/cards").codes').items())
    # Exercise the same selector used by the card, the pile and the recycle highlight.
    vm.execute("""
        ANIM_ORIENTATION={BillBoard=7}
        local state={}
        function state:SetBuild(v) self.build=v end
        function state:SetOrientation(v) assert(v==7) end
        function state:SetBankAndPlayAnimation(bank,clip)
            assert(self.build==bank)
            self.bank,self.clip=bank,clip
        end
        function select_ground(code,count)
            require("nw/ground_card").show({AnimState=state},code,count)
            return {state.bank,state.clip}
        end
    """)
    banks = {}
    review = Image.new("RGBA", (4*230,212), (201,205,195,255))
    labels = ImageDraw.Draw(review)
    for spell, code in codes.items():
        reference = ground_face(card_face(icon(spell,192),192))
        name = "face_" + spell
        for i,(pose, depth) in enumerate(CARD_DEPTHS.items()):
            n = (1,2,4,25)[i]
            selected = vm.globals().select_ground(code,n)
            bank, clip = selected[1], selected[2]
            if bank not in banks:
                banks[bank] = read_bank(bank)
            sprites, clips = banks[bank]
            assert clips[clip] == [(name,0,-depth),("edge_"+pose,0,0)], (spell,clip)
            if i == 0:
                # KTEX is premultiplied BC3. Compare the whole silhouette and the inked face.
                expected = reference.convert("RGBa")
                actual = sprites[name]
                for channel in "RGBA":
                    error = ImageChops.difference(expected.getchannel(channel if channel!="A" else "a"),
                                                  actual.getchannel(channel))
                    assert ImageStat.Stat(error,reference.getchannel("A")).mean[0] < 9, (spell,channel)
                assert ImageStat.Stat(ImageChops.difference(reference.getchannel("A"),actual.getchannel("A"))).mean[0]<2, spell
            if spell=="whirl":
                x=i*230
                review.alpha_composite(sprites["edge_"+pose],(x,28))
                review.alpha_composite(sprites[name],(x,28-depth))
                labels.text((x+80,187),("1 card","2-3 cards","4-6 cards","7-25 cards")[i],fill="#302a24")
    review.convert("RGB").save(SOURCE / "ground_card_review.png")
    print(f"PASS: {len(codes)} decoded ground faces and {len(codes)*4} registered single/pile clips")


if __name__ == "__main__":
    check_ground_cards()
