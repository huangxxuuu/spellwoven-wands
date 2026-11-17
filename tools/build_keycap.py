"""Package generated v5 contours into fixed ends and stretchable UI centres."""
import hashlib
import json
from pathlib import Path
import subprocess
from xml.etree import ElementTree as ET

from PIL import Image

from animation_atlas import validate_ktex
from native_animation import texture

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets_src/ui/keycap/v5"
DEST = ROOT / "mod/images"
CONVERTER = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools/tools/bin/TextureConverter.exe")
HEIGHT, LEFT, RIGHT = 128, 32, 48
# Common source Y bounds preserve the generated baseline and stroke scale.
PROFILES = (
    ("small", (44,363,399,641), 164, 1, ((200,450),(200,578),(351,498))),
    ("medium", (421,363,856,641), 200, 1.5, ((620,450),(620,580),(810,500))),
    ("wide", (892,363,1477,641), 269, 1.75, ((1150,450),(1200,580),(1430,500))),
)


def build():
    source_path = SOURCE / "keycaps_v5.png"
    source = Image.open(source_path)
    assert source.mode == "RGBA" and source.size == (1536,1024)
    atlas = Image.new("RGBA", (512,512))
    xml = ET.Element("Atlas")
    ET.SubElement(xml,"Texture",filename="nw_keycap.tex")
    entries = ET.SubElement(xml,"Elements")
    rows = []
    for index,(name,box,width,ratio,samples) in enumerate(PROFILES):
        tile = source.crop(box).resize((width,HEIGHT),Image.Resampling.LANCZOS)
        tile.save(SOURCE / f"runtime_{name}.png")
        x,y = 4,4+index*(HEIGHT+8)
        atlas.alpha_composite(tile,(x,y))
        pieces = (("left",0,LEFT),("center",LEFT,width-RIGHT),("right",width-RIGHT,width))
        for part,start,end in pieces:
            ET.SubElement(entries,"Element",name=f"keycap_{name}_{part}.tex",
                          u1=str((x+start)/512),u2=str((x+end)/512),v1=str(1-(y+HEIGHT)/512),v2=str(1-y/512))
        points = []
        for sx,sy in samples:
            assert source.getpixel((sx,sy))[3] == 0, f"{name}: filled source face"
            tx,ty = round((sx-box[0])*width/(box[2]-box[0])),round((sy-box[1])*HEIGHT/(box[3]-box[1]))
            assert tile.getpixel((tx,ty))[3] == 0, f"{name}: filled runtime face"
            points.append((x+tx,y+ty))
        rows.append(dict(name=name,source_crop=box,runtime_size=[width,HEIGHT],
                         display_width_ratio=ratio,atlas_position=[x,y],face_samples=points))
    png = SOURCE / "runtime_atlas.png"
    atlas.save(png)
    ET.ElementTree(xml).write(DEST / "nw_keycap.xml",encoding="utf-8",xml_declaration=True)
    subprocess.run([str(CONVERTER),"--swizzle","--format","bc3","--platform","opengl","--premultiply",
                    "-i",str(png),"-o",str(DEST / "nw_keycap.tex")],check=True,capture_output=True,timeout=60)
    data = (DEST / "nw_keycap.tex").read_bytes()
    validate_ktex(data,"nw_keycap")
    compiled = texture(data,unpremultiply=True)
    for row in rows:
        for point in row["face_samples"]:
            assert compiled.getpixel(tuple(point))[3]==0, f"{row['name']}: compiled face lost alpha"
    # Preview the compiled slices using the same fixed ends as the Lua widget.
    preview = Image.new("RGBA",(600,156),"#5a5d59")
    for index,row in enumerate(rows):
        x,y = row["atlas_position"]
        width,_ = row["runtime_size"]
        tile = compiled.crop((x,y,x+width,y+HEIGHT))
        height = 40
        end_left,end_right = round(LEFT*height/HEIGHT),round(RIGHT*height/HEIGHT)
        target = round(164*height/HEIGHT*row["display_width_ratio"])
        slices = ((0,LEFT,end_left),(LEFT,width-RIGHT,target-end_left-end_right),(width-RIGHT,width,end_right))
        for row_index in (0,1):
            px,py = 48+index*180,18+row_index*72
            if row_index:
                preview.paste("#d4cabb",(index*200,80,index*200+200,156))
            for start,end,out_width in slices:
                piece = tile.crop((start,0,end,HEIGHT)).resize((out_width,height),Image.Resampling.LANCZOS)
                preview.alpha_composite(piece,(px,py));px+=out_width
    preview.save(SOURCE / "compiled_preview.png")
    report = dict(source="assets_src/ui/keycap/v5/keycaps_v5.png",
                  source_sha256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
                  atlas_size=[512,512],source_height=HEIGHT,left_width=LEFT,right_width=RIGHT,
                  profiles=rows,compiled_sha256=hashlib.sha256(data).hexdigest(),
                  note="Source widths differ from requested proportions. UI centre stretching supplies 1/1.5/1.75 base widths; ends keep their stroke scale.")
    (SOURCE / "build_report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("PASS v5 generated alpha, three profiles / nine slices, compiled face transparency and fixed-end 1:1.5:1.75 preview")


if __name__=="__main__":
    build()
