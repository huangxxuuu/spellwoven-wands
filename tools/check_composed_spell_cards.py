"""Focused asset checks; no game launch or full gameplay test suite."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from PIL import Image
from compose_spell_cards import ROOT, OUT, perspective


def main():
 m=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
 assert len(m['cards'])==186
 assert len({r['id'] for r in m['cards']})==186
 checked=0
 for row in m['cards']:
  p=ROOT/row['source'];assert hashlib.sha256(p.read_bytes()).hexdigest()==row['source_sha256']
  assert row['layout']['inside_safe_mask'] and row['inventory_layout']['inside_safe_mask']
  for group,size in [('album',1024),('inventory_128',128),('inventory_64',64),('inventory_32',32),('ground',256)]:
   with Image.open(OUT/group/(row['id']+'.png')) as im:
    im.load();assert im.mode=='RGBA' and im.size==(size,size)
    assert im.getchannel('A').getextrema()==(0,255)
   checked+=1
 for path in (OUT/'piles').glob('*.png'):
  with Image.open(path) as im:im.load();assert im.size==(512,512) and im.mode=='RGBA'
 assert len(list((OUT/'piles').glob('*.png')))==36
 # A real missing H corner, not a rectangular plate carrying a triangular ornament.
 rect=perspective(Image.open(OUT/'frames/basic.png').convert('RGBA')).getchannel('A')
 hexa=perspective(Image.open(OUT/'frames/modifier.png').convert('RGBA')).getchannel('A')
 assert rect.getpixel((60,196))>200 and hexa.getpixel((60,196))<8
 byid={r['id']:r for r in m['cards']}
 assert byid['imprint_hit']['primary_class']=='control' and byid['imprint_hit']['mechanism_badge'] is None
 assert byid['repeat_2']['primary_class']=='control' and byid['repeat_2']['mechanism_badge'] is None
 assert byid['sleep_crystal']['mechanism_badge'] is None
 overrides=json.loads((ROOT/'assets_src/spell_card_subjects/selected_overrides.json').read_text(encoding='utf8'))
 for ident,path in overrides.items():assert byid[ident]['source'].endswith(path)
 assert byid['edge_farm_hoe']['source'].endswith('edge_farm_hoe.native.png')
 html=(OUT/'index.html').read_text(encoding='utf8')
 script=re.search(r'<script>(.*?)</script>',html,re.S).group(1)
 with tempfile.TemporaryDirectory(prefix='spell-card-js-') as tmp:
  path=Path(tmp)/'check.js';path.write_text(script,encoding='utf8')
  subprocess.run(['node','--check',str(path)],check=True,capture_output=True)
 report={'passed':True,'single_card_exports_checked':checked,'pile_exports_checked':36,'source_hashes_unchanged':True,'native_hoe_and_latest_retries_selected':True,'hexagon_has_true_missing_corners':True,'html_javascript_syntax':'passed','runtime_game_tests':'not run; source composition task'}
 (OUT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print(json.dumps(report))

if __name__=='__main__':main()
