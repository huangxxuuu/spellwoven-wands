"""Place untouched native hoe art inside the current v3 frame sample."""
from pathlib import Path
import hashlib
import json
import shutil

from PIL import Image, ImageOps

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / 'assets_src/projectiles/tools_v1/farm_hoe-native.png'
FRAME = ROOT / 'assets_src/spell_card_frames/v3_refined_magic/refined_magic_collector_basic.png'
# Hand-checked interior rectangle of this specific 1254px frame candidate.
# It leaves a small gap from the inner ink line and avoids all cut corners.
INNER = (175, 105, 1080, 1148)


def main():
    native = HERE / 'edge_farm_hoe.native.png'
    shutil.copyfile(SOURCE, native)
    art = Image.open(native).convert('RGBA')
    frame = Image.open(FRAME).convert('RGBA')
    assert frame.size == (1254, 1254)
    source_bbox = art.getchannel('A').getbbox()
    assert source_bbox
    cropped = art.crop(source_bbox)
    left, top, right, bottom = INNER
    fitted = ImageOps.contain(cropped, (right-left, bottom-top), Image.Resampling.LANCZOS)
    x = left + (right-left-fitted.width)//2
    y = top + (bottom-top-fitted.height)//2
    assert left <= x and top <= y and x+fitted.width <= right and y+fitted.height <= bottom
    assert fitted.width == right-left or fitted.height == bottom-top
    subject = Image.new('RGBA', frame.size)
    subject.alpha_composite(fitted, (x, y))
    subject.save(HERE / 'edge_farm_hoe.native_layout.png')
    frame.alpha_composite(subject)
    frame.save(HERE / 'edge_farm_hoe.native_card_preview.png')
    report = {
        'source': str(SOURCE.relative_to(ROOT)),
        'native_archive': 'anim/quagmire_hoe.zip', 'symbol': 'hoe01', 'frame': 0,
        'native_copy': native.name,
        'sha256': hashlib.sha256(native.read_bytes()).hexdigest(),
        'source_copy_identical': SOURCE.read_bytes() == native.read_bytes(),
        'source_size': art.size, 'source_alpha_bbox': source_bbox,
        'frame_candidate': str(FRAME.relative_to(ROOT)),
        'frame_status': 'v3 candidate, not final production frame',
        'inner_safe_rect': INNER, 'fitted_size': fitted.size, 'position': (x, y),
        'operations': ['trim transparent outer margin', 'uniform scale', 'translate'],
        'fits_inside_inner_rect': True,
        'maximal_contain_scale': True,
        'status': 'native subject selected; frame composition preview only',
    }
    (HERE / 'native_hoe_layout.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
