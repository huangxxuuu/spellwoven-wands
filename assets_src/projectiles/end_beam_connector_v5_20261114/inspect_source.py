"""Read-only source alpha/geometry inspection; produces QA records only."""
import json
import statistics
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).parent
im = Image.open(root/'connector-source-01.png').convert('RGBA')
a = im.getchannel('A')
bboxes = {str(t): a.point(lambda v: 255 if v>t else 0).getbbox() for t in (0,2,8,32,128,240)}
l,t,r,b = bboxes['32']
columns = []
for f in (.02,.05,.1,.25,.5,.75,.9,.95,.98):
    x = l+round((r-l-1)*f)
    ys = [y for y in range(im.height) if a.getpixel((x,y))>32]
    bright = [y for y in range(im.height) if min(im.getpixel((x,y))[:3])>200 and a.getpixel((x,y))>32]
    columns.append({'fraction':f, 'x':x, 'top':min(ys) if ys else None, 'bottom_inclusive':max(ys) if ys else None,
                    'height':max(ys)-min(ys)+1 if ys else 0,
                    'core_top':min(bright) if bright else None, 'core_bottom':max(bright) if bright else None})
left = statistics.median(v['height'] for v in columns[:3])
right = statistics.median(v['height'] for v in columns[-3:])
hist = a.histogram()
data = {'size':im.size,'alpha_extrema':a.getextrema(),'alpha_zero_pixels':hist[0],
        'alpha_le2_pixels':sum(hist[:3]),'bbox_by_alpha_greater_than':bboxes,
        'columns':columns,'left_near_end_median_height':left,'right_near_end_median_height':right,
        'right_left_ratio':right/left,'ratio_accept_075_090':.75<=right/left<=.90,
        'measurement':'Median alpha>32 column span at 2%,5%,10% vs 90%,95%,98% bbox length; bbox xyxy exclusive.'}
(root/'alpha-and-geometry.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
cut=im.crop((max(0,l-16),max(0,t-16),min(im.width,r+16),min(im.height,b+16)))
cut.thumbnail((800,500),Image.Resampling.LANCZOS)
board=Image.new('RGB',(840,(cut.height+40)*3))
for row,color in enumerate(('#ffffff','#808080','#353d37')):
    y=row*(cut.height+40)
    board.paste(color,(0,y,840,y+cut.height+40))
    board.paste(cut,(20,y+25),cut)
    ImageDraw.Draw(board).text((20,y+7),color,fill='#111111' if row<2 else '#ffffff')
board.save(root/'qa-white-gray-dark.png')
print(json.dumps(data))
