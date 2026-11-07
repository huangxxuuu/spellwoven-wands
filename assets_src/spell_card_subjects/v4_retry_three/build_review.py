"""Build a local comparison; inspect PNGs without changing their pixels."""
import hashlib
import html
import json
import os
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent
panels = []
selection = {}
for ident in ('knockback', 'repeat_2', 'target_neutral'):
    record_path = root / (ident + '.result.json')
    r = json.loads(record_path.read_text(encoding='utf-8'))
    path = root / r['output']
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    with Image.open(path) as im:
        alpha = im.getchannel('A')
        box = alpha.point(lambda x: 255 if x >= 8 else 0).getbbox()
        r['validation'] = {
            'size': list(im.size), 'mode': im.mode,
            'alpha_extrema': list(alpha.getextrema()), 'bbox_alpha8': box,
            'minimum_visible_margin_px': min(box[0], box[1], im.width-box[2], im.height-box[3]),
            'sha256': digest,
            'matches_source': digest == hashlib.sha256(Path(r['source']).read_bytes()).hexdigest(),
            'raw_png_modified': False,
        }
    assert r['validation']['matches_source']
    record_path.write_text(json.dumps(r, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    before = Path(os.path.relpath(r['reference'], root)).as_posix()
    name = html.escape(r['name'])
    note = html.escape(r.get('review', '待审查'))
    panels.append(f'''<section><h2>{name}</h2><p>{note}</p><div class="pair">
    <figure><a href="{before}"><img src="{before}"></a><figcaption>首轮</figcaption></figure>
    <figure><a href="{ident}.png"><img src="{ident}.png"></a><figcaption>本次重试</figcaption></figure>
    </div><p><a href="{ident}.prompt.txt">本次完整 prompt</a> · <a href="{ident}.result.json">检查记录</a></p></section>''')
    selection[ident] = {'selected': ident+'.png' if r['status']=='candidate' else None, 'status':r['status'], 'previous':before, 'total_attempt_number':2}
(root/'selection.json').write_text(json.dumps(selection, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
page = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>三张主图重试对比</title>
<style>body{font:16px/1.6 system-ui;margin:30px auto;max-width:1100px;background:#f4f2ed;color:#292929}section{margin:30px 0;padding:20px;background:white;border-radius:12px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:20px}figure{margin:0;text-align:center}img{width:100%;height:400px;object-fit:contain;background:var(--bg,#ddd)}a{color:#245b90}button{padding:8px 14px}</style>
<h1>三张主图 · 第二次尝试</h1><p>每张本次仅重试一次。原始图与本次结果均保留，图片未经后处理。</p>
<button onclick="document.body.style.setProperty('--bg','#fff')">白底</button>
<button onclick="document.body.style.setProperty('--bg','#ddd')">灰底</button>
<button onclick="document.body.style.setProperty('--bg','#292d34')">深底</button>'''
(root/'index.html').write_text(page+'\n'.join(panels)+'</html>', encoding='utf-8')
print(json.dumps({k:v['status'] for k,v in selection.items()}))
