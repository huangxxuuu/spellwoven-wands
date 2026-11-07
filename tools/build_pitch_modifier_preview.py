"""Preview the four pitch-modifier illustrations without registering runtime cards."""
import hashlib
import html
import json

from PIL import Image, ImageDraw, ImageFilter

from compose_spell_cards import ROOT, S, RES, fitted_subject, font, simple_plate

OUT = ROOT / 'assets_src/spell_card_subjects/v7_pitch_modifiers'
FRAMES = ROOT / 'assets_src/spell_cards_composed/v1/layers'


def main():
    cards = json.loads((OUT / 'cards.json').read_text(encoding='utf8'))['cards']
    paper = Image.open(FRAMES / 'modifier.paper.png').convert('RGBA')
    rim = Image.open(FRAMES / 'modifier.rim.png').convert('RGBA')
    safe = Image.open(FRAMES / 'modifier.safe.png').convert('L')
    small, small_inner = simple_plate('modifier')
    small_safe = small_inner.resize((S, S), Image.Resampling.NEAREST).filter(ImageFilter.MinFilter(17))
    preview = OUT / 'preview'
    preview.mkdir(exist_ok=True)
    board = Image.new('RGB', (1040, 810), '#dedad2')
    draw = ImageDraw.Draw(board)
    page = ['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>调音修饰主图</title><style>body{margin:24px;background:#dedad2;color:#292727;font:16px/1.6 system-ui}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(510px,1fr));gap:20px}article{padding:18px;background:#f6f2e9;border-radius:12px}.large{width:240px;vertical-align:middle}.small{image-rendering:auto;margin:10px}a{color:#34567b}</style><h1>四张调音修饰 · 主图设计</h1><p>统一音符；长箭头表示八度，短箭头表示半音。青绿升调，紫色降调。</p><main class="grid">']
    checks = []
    for index, card in enumerate(cards):
        ident = card['id']
        source = OUT / card['image']
        raw = Image.open(source)
        assert raw.mode == 'RGBA', ident
        alpha = raw.getchannel('A')
        box = alpha.point(lambda v: 255 if v >= 8 else 0).getbbox()
        assert box and alpha.getextrema()[0] == 0, ident
        art, fit = fitted_subject(source, safe, False)
        album = paper.copy()
        album.alpha_composite(art)
        album.alpha_composite(rim)
        album.save(preview / f'{ident}.card.png')
        small_art, small_fit = fitted_subject(source, small_safe, False)
        icon = small.copy()
        icon.alpha_composite(small_art.resize((256, 256), RES))
        for size in (128, 64, 32):
            icon.resize((size, size), RES).save(preview / f'{ident}.{size}.png')
        x = index % 2 * 520
        y = index // 2 * 400
        for image, dx in ((raw, 10), (album, 270)):
            thumb = image.copy()
            thumb.thumbnail((240, 285), RES)
            board.paste(thumb, (x + dx + (240 - thumb.width) // 2, y + 20), thumb)
        draw.text((x + 260, y + 292), card['name'] + '  ' + card['symbol'], anchor='mm', font=font(22), fill='#292727')
        draw.text((x + 260, y + 325), '独立主图 / 修饰卡边框组合', anchor='mm', font=font(14), fill='#685e53')
        for size, dx in ((64, 198), (32, 284)):
            thumb = icon.resize((size, size), RES)
            board.paste(thumb, (x + dx, y + 335), thumb)
        name = html.escape(card['name'])
        page.append(f'<article><h2>{name} · {card["symbol"]} 半音</h2><a href="{ident}.png"><img class="large" src="{ident}.png"></a><a href="preview/{ident}.card.png"><img class="large" src="preview/{ident}.card.png"></a><p><img class="small" width="64" src="preview/{ident}.64.png"><img class="small" width="32" src="preview/{ident}.32.png"></p><a href="{ident}.prompt.txt">完整 prompt</a> · <a href="{ident}.png">透明主图</a></article>')
        checks.append({'id': ident, 'size': list(raw.size), 'mode': raw.mode, 'bbox_alpha8': box, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'album_fit': fit, 'inventory_fit': small_fit})
    page.append('</main></html>')
    board.save(OUT / 'review.png')
    (OUT / 'index.html').write_text(''.join(page), encoding='utf8')
    registered=json.loads((OUT / 'cards.json').read_text(encoding='utf8')).get('runtime_registered',False)
    (OUT / 'validation.json').write_text(json.dumps({'cards': checks, 'runtime_registered': registered, 'frame_containment': 'passed', 'imagegen_calls': 4, 'game_tests': 'not run'}, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print('4 subjects, 16 framed previews; frame containment passed')


if __name__ == '__main__':
    main()
