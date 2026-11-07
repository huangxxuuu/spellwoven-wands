"""Upload named Workshop preview images without changing mod content or visibility."""
import argparse
import ctypes as C
from datetime import datetime
import hashlib
import json
from pathlib import Path
from steam_workshop_metadata import Steam, U64, U32, BOOL, STR, INT, INVALID, QueryResult, SubmitResult, require, save


def previews(api, item):
    ids = (U64 * 1)(item)
    h = api.ugc('CreateQueryUGCDetailsRequest', U64, C.POINTER(U64), U32)(ids, 1)
    require(h not in (0, INVALID), 'Invalid preview query')
    try:
        require(api.ugc('SetReturnAdditionalPreviews', BOOL, U64, BOOL)(h, True), 'Preview query rejected')
        require(api.ugc('SetAllowCachedResponse', BOOL, U64, U32)(h, 0), 'Cache setting rejected')
        r = api.wait(api.ugc('SendQueryUGCRequest', U64, U64)(h), QueryResult, 3401)
        require(r.count == 1 and r.handle == h, 'Unexpected preview query result')
        n = api.ugc('GetQueryUGCNumAdditionalPreviews', U32, U64, U32)(h, 0)
        rows = []
        for i in range(n):
            url, name, kind = C.create_string_buffer(4096), C.create_string_buffer(1024), INT()
            require(api.ugc('GetQueryUGCAdditionalPreview', BOOL, U64, U32, U32, STR, U32, STR, U32, C.POINTER(INT))(
                h, 0, i, url, len(url), name, len(name), C.byref(kind)), 'Preview read failed')
            rows.append(dict(index=i, url=url.value.decode(), filename=name.value.decode(), type=kind.value))
        return rows
    finally:
        api.ugc('ReleaseQueryUGCRequest', BOOL, U64)(h)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--directory', type=Path)
    p.add_argument('--publish', action='store_true')
    p.add_argument('--only', help='Upload just this filename for a staged update')
    a = p.parse_args()
    item = 3834454416
    with Steam(322330) as api:
        before = api.read(item, 'schinese')
        require(before['owner'] == api.owner, 'Not the item owner')
        old = previews(api, item)
        if not a.publish:
            print(json.dumps(old, ensure_ascii=True, indent=2))
            return
        files = sorted(x for x in a.directory.resolve().iterdir() if x.suffix in ('.gif', '.png', '.jpg'))
        if a.only:
            files = [f for f in files if f.name == a.only]
        require(files and all(0 < f.stat().st_size < 1000000 for f in files), 'Missing/oversize media')
        names = {r['filename'] for r in old}
        require(not any(f.name in names for f in files), 'Preview name already exists; inspect before retrying')
        receipt = Path('dist/workshop-metadata') / ('media-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '.json')
        data = dict(before=before, before_previews=old, files={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in files}, complete=False)
        save(receipt, data)
        h = api.ugc('StartItemUpdate', U64, U32, U64)(322330, item)
        require(h not in (0, INVALID), 'Invalid update handle')
        require(api.ugc('SetItemUpdateLanguage', BOOL, U64, STR)(h, b'schinese'), 'Cannot preserve metadata language')
        require(api.ugc('SetItemTitle', BOOL, U64, STR)(h, before['title'].encode('utf8')), 'Cannot preserve title')
        for f in files:
            require(api.ugc('AddItemPreviewFile', BOOL, U64, STR, INT)(h, str(f).encode(), 0), 'Cannot add ' + f.name)
        result = api.wait(api.ugc('SubmitItemUpdate', U64, U64, STR)(h, None), SubmitResult, 3404, timeout=180)
        require(result.item_id == item and not result.needs_agreement, 'Upload not confirmed')
        after = api.read(item, 'schinese')
        require(all(after[k] == before[k] for k in ('owner', 'visibility', 'file', 'preview', 'filename', 'file_size', 'title', 'description')), 'Unrelated metadata changed')
        data['after_previews'] = previews(api, item)
        require(len(data['after_previews']) == len(old) + len(files), 'Unexpected uploaded preview count')
        uploaded = {r['filename']:r for r in data['after_previews']}
        require(all(f.name in uploaded and uploaded[f.name]['url'].startswith('https://') for f in files), 'Missing uploaded media URL')
        data['complete'] = True
        save(receipt, data)
        save(a.directory / 'steam-media.json', {r['filename']:r['url'] for r in data['after_previews']})
        print('Uploaded and verified', len(files), 'previews. Receipt:', receipt)


if __name__ == '__main__':
    main()
