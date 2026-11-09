"""Publish only the configured Workshop main preview, preserving item content."""
from datetime import datetime
import ctypes as C
import hashlib
import json
import time
from urllib.request import urlopen
from pathlib import Path

from steam_workshop_metadata import (
    Steam, U64, INT, PTR, BOOL, STR, INVALID, require, save,
)

ROOT = Path(__file__).resolve().parents[1]


class LegacySubmitResult(C.Structure):
    _pack_ = 8
    _fields_ = [('result', INT), ('item_id', U64), ('needs_agreement', BOOL)]


def main():
    config = json.loads((ROOT / 'tools/release_config.json').read_text(encoding='utf8'))
    preview = ROOT / config['preview']
    require(preview.is_file() and 0 < preview.stat().st_size < 1024 * 1024, 'Missing/oversize preview.')
    item = int(config['publishedfileid'])
    require(config['app_id'] == 322330 and item > 0, 'Expected an existing DST item.')
    receipt = ROOT / 'dist/workshop-metadata' / ('main-preview-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json')
    with Steam(config['app_id']) as api:
        before = {lang: api.read(item, lang) for lang in ('schinese', 'english')}
        require(all(row['owner'] == api.owner for row in before.values()), 'Not the item owner.')
        data = dict(item_id=item, before=before, preview=str(preview),
                    sha256=hashlib.sha256(preview.read_bytes()).hexdigest(), complete=False)
        save(receipt, data)
    # This item's preview is owned by the original Klei uploader (AppID 245850).
    # ISteamUGC can update localized text but silently leaves this legacy preview unchanged.
    creator = before['english']['creator_app']
    require(creator == 245850, 'Expected a legacy Klei uploader item.')
    with Steam(creator) as api:
        require(api.owner == before['english']['owner'], 'Steam user changed.')
        storage = api.fn('SteamAPI_SteamRemoteStorage_v014', PTR)()
        require(storage, 'RemoteStorage unavailable.')
        image = preview.read_bytes()
        cloud_name = ('nw_main_preview_' + hashlib.sha256(image).hexdigest() + '.png').encode('ascii')
        require(api.fn('SteamAPI_ISteamRemoteStorage_FileWrite', BOOL, PTR, STR, PTR, INT)(
            storage, cloud_name, C.create_string_buffer(image), len(image)), 'Cloud preview write failed.')
        handle = api.fn('SteamAPI_ISteamRemoteStorage_CreatePublishedFileUpdateRequest', U64, PTR, U64)(storage, item)
        require(handle not in (0, INVALID), 'Invalid update handle.')
        require(api.fn('SteamAPI_ISteamRemoteStorage_UpdatePublishedFilePreviewFile', BOOL, PTR, U64, STR)(
            storage, handle, cloud_name), 'Cannot set preview.')
        print('Uploading Chinese Workshop main preview...', flush=True)
        result = api.wait(api.fn('SteamAPI_ISteamRemoteStorage_CommitPublishedFileUpdate', U64, PTR, U64)(
            storage, handle), LegacySubmitResult, 1316, timeout=180)
        require(result.item_id == item and not result.needs_agreement, 'Upload not confirmed.')
        data['submit_result'] = 'OK'
        save(receipt, data)
    with Steam(config['app_id']) as api:
        after = {lang: api.read(item, lang) for lang in before}
        for attempt in range(5):
            if all(row['preview_size'] == preview.stat().st_size for row in after.values()):
                break
            time.sleep(2)
            after = {lang: api.read(item, lang) for lang in before}
        data['after'] = after
        save(receipt, data)
        invariants = ('title', 'description', 'owner', 'visibility', 'tags', 'file', 'filename', 'file_size')
        require(all(after[lang][key] == before[lang][key] for lang in before for key in invariants),
                'An unrelated Workshop field changed; inspect receipt.')
        require(all(row['preview_size'] == preview.stat().st_size for row in after.values()),
                'Preview size read-back mismatch.')
        url = 'https://images.steamusercontent.com/ugc/' + str(after['english']['preview']) + '/' + hashlib.sha1(image).hexdigest().upper() + '/'
        with urlopen(url, timeout=30) as response:
            require(response.read() == image, 'Public preview bytes differ from the approved image.')
        data['verified_preview_url'] = url
        data.update(after=after, complete=True, result='OK')
        save(receipt, data)
        print('Verified Workshop preview; content and localized text preserved. Receipt:', receipt)


if __name__ == '__main__':
    main()
