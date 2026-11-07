"""Validate shipped layer atlas, native aliases and every wand composition."""
import hashlib
from pathlib import Path
from xml.etree import ElementTree as ET
from PIL import Image, ImageDraw, ImageChops, ImageStat
from lupa.lua51 import LuaRuntime
from native_animation import texture
from animation_atlas import validate_ktex

ROOT=Path(__file__).resolve().parents[1]

def check():
    vm=LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path=(ROOT/'mod/scripts/?.lua').as_posix()+';'+vm.globals().package.path
    visual=vm.eval('require("nw/visual")')
    base=ROOT/'mod/images/inventoryimages/nw_wand_parts'
    raw=base.with_suffix('.tex').read_bytes();validate_ktex(raw,'nw_wand_parts')
    atlas=texture(raw)
    source=Image.open(ROOT/'assets_src/art_v1/runtime/nw_wand_parts.png').convert('RGBa')
    assert atlas.size==source.size==(1024,1024)
    for c,sc in zip('RGBA','RGBa'):
        assert ImageStat.Stat(ImageChops.difference(atlas.getchannel(c),source.getchannel(sc))).mean[0]<3
    tiles={}
    for e in ET.parse(base.with_suffix('.xml')).findall('./Elements/Element'):
        a=e.attrib;x=round(float(a['u1'])*1024);y=round((1-float(a['v2']))*1024)
        assert round((float(a['u2'])-float(a['u1']))*1024)==64
        assert round((float(a['v2'])-float(a['v1']))*1024)==64
        assert a['name'] not in tiles
        tiles[a['name']]=atlas.crop((x,y,x+64,y+64))
    assert len(tiles)==162+8748
    digests=set();review=Image.new('RGB',(960,480),'#d2c6aa');draw=ImageDraw.Draw(review)
    for code in range(visual.count):
        for broken in (False,True):
            assert tiles[visual.icon(code,broken)+'.tex'].tobytes()==atlas.crop((0,0,64,64)).tobytes()
            names=list(visual.icon_parts(code,broken).values());assert len(names)==3
            out=Image.new('RGBA',(64,64))
            for name in names:
                tile=tiles[name];assert tile.getchannel('A').getbbox()
                # KTEX stores premultiplied RGB.
                out.alpha_composite(Image.frombytes('RGBa',tile.size,tile.tobytes()).convert('RGBA'))
            assert out.getchannel('A').getbbox()
            digests.add(hashlib.sha256(out.tobytes()).digest())
            if code%486 in (0,13,26):
                col=code//486;row=(code%486)//9*2+int(broken)
                review.paste(out,(col*106+20,row*80),out)
                draw.text((col*106+8,row*80+64),str(code)+(' broken' if broken else ''),fill='#302a24')
    assert len(digests)==8748,'Distinct looks must not collapse to a shared full-wand image'
    assert not list(base.parent.glob('nw_wands*.tex'))
    assert not list((ROOT/'mod/anim').glob('nw_ground_cards_*.zip'))
    assert not list((ROOT/'mod/images/cards').glob('nw_card_album_*.*'))
    outdir=ROOT/'test_reports';outdir.mkdir(exist_ok=True)
    review.save(outdir/'wand_icon_parts_review.png')
    print('PASS: 162 compiled layers, 8748 distinct compositions, shared fallback and no retired resources')

if __name__=='__main__':check()
