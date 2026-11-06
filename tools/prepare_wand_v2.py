"""Convert the bold-ink shaft masters to fixed shoulders and three grip lengths."""
from pathlib import Path
import json

from PIL import Image, ImageDraw, ImageChops

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets_src/art_v2'
WIDTH=72
HEIGHTS={'short':48,'medium':104,'long':168}
CAP_HEIGHT=20


def socket(alpha,y):
    # Forked shoulders can have separate prongs on this row. Fit the central
    # joining stub, excluding those decorative side prongs.
    row=list(alpha.crop((0,y,alpha.width,y+1)).getdata())
    runs=[]
    left=None
    for x,a in enumerate(row+[0]):
        if a>50 and left is None:
            left=x
        elif a<=50 and left is not None:
            runs.append((left,x));left=None
    left,right=min(runs,key=lambda r:abs((r[0]+r[1])/2-alpha.width/2))
    return (left+right)/2,26/(right-left)


def strip(source,top,bottom,upper,lower,height):
    ux,us=upper
    lx,ls=lower
    ur,lr=WIDTH/(2*us),WIDTH/(2*ls)
    quad=(ux-ur,top,lx-lr,bottom,lx+lr,bottom,ux+ur,top)
    return source.transform((WIDTH*4,height*4),Image.Transform.QUAD,quad,
                            Image.Resampling.BICUBIC).resize((WIDTH,height),Image.Resampling.LANCZOS)


def tuck(part,top):
    mask=Image.new('L',(WIDTH*4,part.height*4),255)
    draw=ImageDraw.Draw(mask)
    for row in range(32):
        radius=(7+(WIDTH/2-7)*(row/32)**2)*4
        y=row if top else mask.height-1-row
        draw.line((0,y,WIDTH*2-radius,y),fill=0)
        draw.line((WIDTH*2+radius,y,WIDTH*4,y),fill=0)
    part.putalpha(ImageChops.multiply(part.getchannel('A'),mask.resize(part.size,Image.Resampling.LANCZOS)))


def main():
    output=ART/'shafts'
    output.mkdir(exist_ok=True)
    metadata={}
    for style in range(1,10):
        source=Image.open(ART/f'body_{style:02}.png').convert('RGBA')
        source.putalpha(source.getchannel('A').point(lambda v:0 if v<24 else v))
        box=source.getchannel('A').getbbox()
        source=source.crop(box)
        h=source.height
        # Crop only inside the two joining stubs, then keep both shoulders.
        cuts=[round(h*v) for v in (.025,.22,.78,.975)]
        upper_pin=socket(source.getchannel('A'),cuts[0])
        lower_pin=socket(source.getchannel('A'),cuts[3]-1)
        top=strip(source,cuts[0],cuts[1],upper_pin,upper_pin,CAP_HEIGHT)
        bottom=strip(source,cuts[2],cuts[3],lower_pin,lower_pin,CAP_HEIGHT)
        tuck(top,True);tuck(bottom,False)
        middle=strip(source,cuts[1],cuts[2],upper_pin,lower_pin,HEIGHTS['long']-2*CAP_HEIGHT)
        for length,height in HEIGHTS.items():
            body=Image.new('RGBA',(WIDTH,height))
            body.paste(top)
            body.paste(middle.resize((WIDTH,height-2*CAP_HEIGHT),Image.Resampling.LANCZOS),(0,CAP_HEIGHT))
            body.paste(bottom,(0,height-CAP_HEIGHT))
            bb=body.getchannel('A').point(lambda v:255 if v>60 else 0).getbbox()
            assert bb[0]>0 and bb[2]<WIDTH,(style,length,'clipped body')
            path=output/f'body_{style:02}_{length}.png'
            body.save(path)
            check=Image.open(path)
            assert check.crop((0,0,WIDTH,CAP_HEIGHT)).tobytes()==top.tobytes()
            assert check.crop((0,height-CAP_HEIGHT,WIDTH,height)).tobytes()==bottom.tobytes()
        metadata[str(style)]={'source_bbox':box,'cuts':cuts,'fixed_cap_pixels':CAP_HEIGHT,
                              'top_socket':upper_pin,'bottom_socket':lower_pin}
    (ART/'shaft_layouts.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    print('PASS: 27 shafts, identical upper/lower 20px across all three lengths')


if __name__=='__main__':
    main()
