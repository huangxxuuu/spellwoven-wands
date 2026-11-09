"""Validate and copy the approved coffer/lamp runtime art into the mod."""
from pathlib import Path
import shutil
from xml.etree import ElementTree

from animation_atlas import validate_animation_archive

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    'anim/nw_dustbox.zip', 'anim/nw_emberlamp.zip',
    'images/inventoryimages/nw_arcane_storage.xml',
    'images/inventoryimages/nw_arcane_storage.tex',
)


def main():
    source = ROOT / 'assets_src/arcane_storage_final/package'
    for name in FILES:
        if not (source / name).is_file():
            raise SystemExit(f'Missing compiled art: {source / name}. Run tools/package_arcane_storage_art.py first.')
    for name in FILES[:2]:
        validate_animation_archive(source / name)
    atlas = ElementTree.parse(source / FILES[2])
    assert atlas.find('Texture').get('filename') == 'nw_arcane_storage.tex'
    assert (source / FILES[3]).read_bytes()[:4] == b'KTEX'
    for name in FILES:
        target = ROOT / 'mod' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, target)
        assert target.read_bytes() == (source / name).read_bytes()
    print('Approved arcane storage art: 2 native animation banks and inventory atlas synced.')


if __name__ == '__main__':
    main()
