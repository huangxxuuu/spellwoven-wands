"""Author and compile a hinged coffer in the existing supplies SVG art style.

Run before build_supplies.py, which includes the two inventory icons.
The ground shadow is DST DynamicShadow, never painted into inventory art.
"""
from io import BytesIO
from pathlib import Path
from xml.etree import ElementTree as ET

from PIL import Image, ImageDraw
import resvg_py
from build_art_assets import ROOT, compile_bank, frame

SOURCE = ROOT / "assets_src/dustbox"
BANK = "nw_dustbox"
TOOLS = Path("E:/SteamLibrary/steamapps/common/Don't Starve Mod Tools/mod_tools")


def points(vertices):
    return " ".join(f"{x:.2f},{y:.2f}" for x, y in vertices)


def svg(opening):
    # Lid rotates around the same rear hinge. The base never moves between poses.
    closed = [(19, 71), (66, 55), (113, 73), (65, 93)]
    opened = [(19, 71), (66, 55), (74, 13), (26, 27)]
    lid = [(x+(u-x)*opening, y+(v-y)*opening) for (x,y),(u,v) in zip(closed,opened)]
    cx, cy = (sum(v[i] for v in lid)/4 for i in (0,1))
    inset = [(cx+(x-cx)*.80, cy+(y-cy)*.71) for x,y in lid]
    def bilinear(u,v):
        a,b,c,d=lid
        return tuple((1-v)*((1-u)*a[i]+u*b[i])+v*((1-u)*d[i]+u*c[i]) for i in (0,1))
    seams = []
    for u in (.25,.68):
        a,b=bilinear(u,.17),bilinear(u,.84)
        seams.append(f'<path d="M{a[0]:.2f},{a[1]:.2f} L{b[0]:.2f},{b[1]:.2f}"/>')
    bolts = ''.join(f'<circle cx="{x:.2f}" cy="{y:.2f}" r="1.35" fill="#eac287" stroke-width=".8"/>' for x,y in inset)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 128 128">
<g stroke="#271f29" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round">
<!-- Dark, gold-rimmed recess and the permanent base. -->
<path fill="#bc9363" d="M18 71 66 54 113 72 112 102 65 120 19 103z"/>
<path fill="#423344" d="m23 72 43-13 41 14-42 16z"/>
<path fill="#211d2c" d="m29 73 37-11 35 12-36 12z"/>
<path fill="#9267a8" stroke-width="1.3" d="m36 77 9-6 8 3 12-7 7 5 11-3 11 7-29 9z"/>
<path fill="#d0a6df" stroke="none" d="m49 76 5-3 3 2-5 3zm16-4 4-1 2 3-5 3zm12 4 6-3 3 2-7 3z"/>
<path fill="#786051" d="m19 75 46 17v28l-46-17z"/>
<path fill="#50424c" d="m65 92 48-19-1 29-47 18z"/>
<path fill="#aa8057" d="m19 75 7 3v22l39 14v6l-46-17zm46 17 7-3v24l40-16v5l-47 18z"/>
<path fill="none" stroke="#382b30" stroke-width="1.4" d="m30 89 18 6m-16 7 17 6m30-13 23-9m-22 17 20-7m-64-8 6 5m42-7 9-5"/>
<!-- Purple crystal/dust sigil, readable at inventory scale. -->
<path fill="#d3ab72" d="m45 85 12 5 3 13-11 5-11-10z"/>
<path fill="#846297" stroke-width="1.4" d="m46 89 8 3 2 9-7 3-7-7z"/>
<path fill="#f0d1f0" stroke="none" d="m48 91 2 4 4 2-4 1-1 4-2-5-3-2 4-1z"/>
<path fill="#c09a69" stroke-width="1.4" d="m22 69 8-2 1 5-8 3zm35-11 8-3 3 4-8 3z"/>
<!-- Single hinged panel, exported as nine coherent animation poses. -->
<polygon points="{points(lid)}" fill="#b38a5d"/>
<polygon points="{points(inset)}" fill="{'#625062' if opening > .5 else '#7b5d52'}" stroke-width="1.6"/>
<g fill="none" stroke="#392c35" stroke-width="1.2">{''.join(seams)}</g>
{bolts}
<path fill="none" stroke="#e0b77b" stroke-width="1.2" d="m23 105 33 12m20-5 32-13"/>
</g></svg>'''


def main():
    SOURCE.mkdir(parents=True,exist_ok=True)
    build=ET.Element("Build",name=BANK)
    animations=ET.Element("Anims")
    images={}
    for i in range(9):
        # Smoothstep keeps both endpoints still, matching the stationary holds.
        t=i/8
        source=svg(t*t*(3-2*t))
        name=f"pose_{i:02}"
        (SOURCE/f"{name}.svg").write_text(source,encoding="utf8")
        sprite=Image.open(BytesIO(resvg_py.svg_to_bytes(svg_string=source))).convert("RGBA")
        images[name]=sprite
        frame(build,name,name,sprite.size,(0,-70))
    for name,indices in {"closed":[0],"open":list(range(9)),"opened":[8],"close":list(range(8,-1,-1))}.items():
        clip=ET.SubElement(animations,"anim",name=name,root=BANK,framerate="30")
        for i in indices:
            f=ET.SubElement(clip,"frame",x="0",y="-70",w="160",h="160")
            ET.SubElement(f,"element",name=f"pose_{i:02}",frame="0",layername="coffer",z_index="0",
                          m_a="1",m_b="0",m_c="0",m_d="1",m_tx="0",m_ty="0")
    compile_bank(BANK,build,animations,images,TOOLS)
    # Dedicated, tight inventory canvases; no ground shadow in the icons.
    for i,name in [(0,"nw_dustbox"),(8,"nw_dustbox_open")]:
        im=images[f"pose_{i:02}"]
        (SOURCE/f"{name}.svg").write_text(svg(i/8),encoding="utf8")
        box=im.getchannel("A").getbbox()
        from PIL import ImageOps
        icon=ImageOps.contain(im.crop(box),(60,60),Image.Resampling.LANCZOS)
        canvas=Image.new("RGBA",(64,64))
        canvas.alpha_composite(icon,((64-icon.width)//2,(64-icon.height)//2))
        canvas.save(SOURCE/f"{name}.png")
    # Review the real exported ground poses; illustrative ellipse stands in for
    # the engine's DynamicShadow and is not packed into the animation bank.
    review=Image.new("RGBA",(720,240),(220,213,195,255))
    draw=ImageDraw.Draw(review)
    for j,i in enumerate((0,2,5,8)):
        x=j*180+10
        draw.ellipse((x+20,174,x+142,198),fill=(84,78,73,85))
        review.alpha_composite(images[f"pose_{i:02}"],(x,35))
        draw.text((x+25,214),["CLOSED","OPEN 1","OPEN 2","OPENED"][j],fill="#302936")
    review.convert("RGB").save(SOURCE/"review.png")
    frames=[]
    for i in [0]*12+list(range(9))+[8]*18+list(range(8,-1,-1)):
        im=Image.new("RGBA",(220,210),(220,213,195,255))
        ImageDraw.Draw(im).ellipse((50,172,172,196),fill=(142,134,121,255))
        im.alpha_composite(images[f"pose_{i:02}"],(30,35))
        frames.append(im.convert("RGB"))
    frames[0].save(SOURCE/"open_close.gif",save_all=True,append_images=frames[1:],duration=33,loop=0)
    print("Dust coffer: 9 poses, 4 animations, 2 inventory icons")


if __name__=="__main__":
    main()
