"""Compare ground paper edges with the captured pre-change source renders."""
from PIL import Image, ImageDraw
from build_split_card_ground import ROOT, SOURCE, compose, make_materials, layouts, font


def main():
    keys=['single_R','single_H','single_N','two_RH','three_RHR',
          'medium_RHR_hex','large_RHR_plain','large_RHR_hex_adjacent',
          'large_HNR_hex_separated']
    layers=make_materials()
    rows={r['key']:r for r in layouts()}
    board=Image.new('RGB',(1080,1040),'#302e25')
    draw=ImageDraw.Draw(board)
    draw.text((20,12),'地面卡牌厚度：左为调整前，右为调整后',font=font(25),fill='#eee5cf')
    for i,key in enumerate(keys):
        x=i%3*360;y=60+i//3*325
        draw.rectangle((x+5,y,x+355,y+315),fill='#60503a')
        row=rows[key]
        ident={'R':'fire','H':'speed_up','N':'repeat_2'}[row['prefix'][0]]
        face=Image.open(SOURCE/'album'/f'{ident}.png').convert('RGBA')
        before=Image.open(ROOT/'test_reports/card_thickness_before'/f'{key}.png').convert('RGBA')
        after=compose(row,layers,face)
        # Same scale and crop: do not auto-fit away the thickness difference.
        for j,pic in enumerate((before,after)):
            small=pic.resize((256,256),Image.Resampling.LANCZOS).crop((30,40,226,205))
            small=small.resize((176,148),Image.Resampling.LANCZOS)
            board.paste(small,(x+j*176+4,y+25),small)
            detail=pic.crop((80*3,170*3,176*3,192*3)).resize((172,66),Image.Resampling.NEAREST)
            board.paste(detail,(x+j*176+6,y+195),detail)
        draw.text((x+12,y+275),key,font=font(16),fill='#eee5cf')
    path=ROOT/'test_reports/card_thickness_comparison.png'
    board.save(path)
    print(path)


if __name__=='__main__':
    main()
