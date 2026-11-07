"""New geometry-only recess study. Does not open or modify existing art PNGs."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter

OUT = Path(__file__).resolve().parent
AA = 3
BG = "#373431"
PAPER = "#DED4BE"
SIDE = "#BBAA8E"
INK = "#4E4237"
SHADOW = "#4D483E"
TEXT = "#EDE5D5"
MUTED = "#C4B7A2"
MARK = "#DAB477"
SHAPES = {
    "R": [(4,0),(48,0),(52,4),(52,52),(48,56),(4,56),(0,52),(0,4)],
    "H": [(26,0),(52,12),(52,44),(26,56),(0,44),(0,12)],
    "N": [(4,0),(18,0),(18,8),(34,8),(34,0),(48,0),(52,4),(52,52),(48,56),(4,56),(0,52),(0,4)],
}


def font(size):
    return ImageFont.truetype("C:/Windows/Fonts/arial.ttf", round(size*AA))


def text(im, xy, value, size=22, color=TEXT, anchor="mm"):
    ImageDraw.Draw(im).text(tuple(round(x*AA) for x in xy),value,font=font(size),fill=color,anchor=anchor)


def polygon(kind,cx,y0,scale,elevation):
    return [((cx+(x-26)*scale*(.68+.32*y/56))*AA,
             (y0+y*scale*.60-elevation)*AA) for x,y in SHAPES[kind]]


def mask(im, pts):
    out=Image.new("L",im.size)
    ImageDraw.Draw(out).polygon(pts,fill=255)
    return out


def ground_shadow(im, sequence, cx,y0,scale,thickness):
    # Cast footprint falls on the ground, not a fictional solid rectangular base.
    m=Image.new("L",im.size)
    d=ImageDraw.Draw(m)
    for kind in sequence:
        p=polygon(kind,cx+2,y0+3,scale,-thickness)
        d.polygon(p,fill=155)
    m=m.filter(ImageFilter.GaussianBlur(2*AA))
    im.paste("#11100F",(0,0),m)


def layer(im, kind, uppers,cx,y0,scale,elevation,thickness):
    d=ImageDraw.Draw(im)
    face=polygon(kind,cx,y0,scale,elevation)
    foot=[(x,y+thickness*AA) for x,y in face]
    # Draw only the true extruded footprint. H has NO rectangular front corners.
    d.polygon(foot,fill=SIDE)
    for n,p in enumerate(face):
        j=(n+1)%len(face)
        side_color=SIDE
        # Side surfaces recessed below an overhanging R receive less light.
        # Their geometry still follows H's actual diagonal edges.
        if kind=="H" and any(u in ("R","N") for u in uppers):
            side_color="#968972"
        d.polygon([p,face[j],foot[j],foot[n]],fill=side_color)
    d.line(foot+[foot[0]],fill=INK,width=round(1.5*AA),joint="curve")
    d.polygon(face,fill=PAPER)
    # Shadows land on complete LOWER paper surfaces. In R-H-R this is the
    # bottom R top face exposed where H's front corners are absent, NOT a hole.
    if uppers:
        cast=Image.new("L",im.size)
        sd=ImageDraw.Draw(cast)
        for u in uppers:
            sd.polygon(polygon(u,cx,y0,scale,elevation),fill=255)
        cast=ImageChops.multiply(cast,mask(im,face))
        im.paste(SHADOW,(0,0),cast)
    ImageDraw.Draw(im).line(face+[face[0]],fill=INK,width=round(1.7*AA),joint="curve")


def pile(im,sequence,cx,y0,scale,thickness):
    ground_shadow(im,sequence,cx,y0,scale,thickness)
    for i in range(len(sequence)-1,-1,-1):
        layer(im,sequence[i],sequence[:i],cx,y0,scale,
              (len(sequence)-1-i)*thickness,thickness)


def save(im,name):
    im.resize((im.width//AA,im.height//AA),Image.Resampling.LANCZOS).save(OUT/name)


def focus():
    im=Image.new("RGB",(1500*AA,1100*AA),BG)
    text(im,(750,40),"HEXAGON RECESS / TRUE UNDERCARD FOOTPRINT",30)
    text(im,(750,80),"Exact same alignment. Contacting layers. Display thickness x2 for recess visibility.",20,MUTED)
    cases=[("RRR","All R: three continuous paper edges"),
           ("RHR","H missing corners: shadow on the lower R, not a paper sidewall"),
           ("RRH","Bottom H: upper R overhang; no rectangular foot below"),
           ("RHH","Two H layers: deeper corner recession under the top R")]
    for i,(seq,caption) in enumerate(cases):
        cx=375+750*(i%2)
        y=200+430*(i//2)
        text(im,(cx,y-50)," > ".join(seq),30)
        pile(im,list(seq),cx,y,scale=7.5,thickness=10)
        text(im,(cx,y+310),caption,18,MUTED)
    text(im,(750,1050),"Light = actual paper. Dark recessed areas = occlusion shadow or ground. Never fill H's missing corners with paper.",19,MUTED)
    save(im,"pile_recess_focus_geometry.png")


def matrix():
    im=Image.new("RGB",(1440*AA,1320*AA),BG)
    text(im,(720,38),"RECESSED UNDERCARD GEOMETRY / 12 COMBINATIONS",28)
    text(im,(720,78),"No spreading or air gaps. Layer thickness is exaggerated for structural review.",20,MUTED)
    centers=[420,810,1200]
    for x,kind,name in zip(centers,"RHN",["RECTANGLE","HEXAGON","NOTCHED"]):
        text(im,(x,133),f"{kind} | {name}",22)
    bases=["RR","HR","RH","HH"]
    for row,base in enumerate(bases):
        y=198+266*row
        text(im,(94,y+72),base,30)
        for cx,top in zip(centers,"RHN"):
            pile(im,list(top+base),cx,y,scale=4.7,thickness=9)
            text(im,(cx,y+204),f"T={top} | {base[0]} > {base[1]}",20,MUTED)
    text(im,(720,1266),"R / N undercards share R's outer footprint. H has diagonal recessed sides and genuinely missing front corners.",19,MUTED)
    save(im,"pile_recess_matrix_geometry.png")


if __name__=="__main__":
    focus()
    matrix()
    print(OUT/"pile_recess_focus_geometry.png")
    print(OUT/"pile_recess_matrix_geometry.png")
