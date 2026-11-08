"""Upload a verified frozen release via DST's installed Steam API and client."""
import argparse
import ctypes as C
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys

from steam_workshop_metadata import Steam, SubmitResult, U64, U32, BOOL, STR, INVALID, require, save
from release import verify_hashes, workshop_changenote


class StringArray(C.Structure):
    _fields_ = [('strings', C.POINTER(STR)), ('count', C.c_int)]


def upload(directory, dll=None):
    directory = Path(directory).resolve()
    state = json.loads((directory / 'state.json').read_text(encoding='utf8'))
    require(state['steam_visibility'] == 'preserve', 'Native upload preserves visibility; use SteamCMD for visibility changes.')
    verify_hashes(directory, state['artifact_hashes'])
    files = {p.relative_to(directory).as_posix() for p in (directory / 'content').rglob('*') if p.is_file()}
    require(files and files == {p for p in state['artifact_hashes'] if p.startswith('content/')},
            'Frozen content contains missing or extra files.')
    text = (directory / 'content/modinfo.lua').read_text(encoding='utf8')
    require(re.search(r'^version\s*=\s*"([^"]+)"', text, re.M)[1] == state['version'], 'Frozen version mismatch.')
    config = state['config']
    require(config['app_id'] == 322330 and int(config['publishedfileid']) > 0, 'Expected an existing DST item.')
    item = int(config['publishedfileid'])
    with Steam(config['app_id'], dll) as api:
        before = api.read(item, 'english')
        require(before['owner'] == api.owner, 'Logged-in user is not the Workshop owner.')
        require(not before['tags_truncated'], 'Cannot safely preserve truncated Workshop tags.')
        receipt_path = directory / ('steam-api-upload-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json')
        receipt = dict(version=state['version'], item_id=item, complete=False, before=before,
                       time_utc=datetime.now(timezone.utc).isoformat())
        save(receipt_path, receipt)
        handle = api.ugc('StartItemUpdate', U64, U32, U64)(api.app_id, item)
        require(handle not in (0, INVALID), 'Invalid update handle.')
        for name, path in [('SetItemContent', directory / 'content'), ('SetItemPreview', directory / 'preview.png')]:
            require(api.ugc(name, BOOL, U64, STR)(handle, str(path).encode('utf8')), name + ' failed.')
        # Keep all existing functional tags, replacing only the stale version tag.
        tags = [t for t in before['tags'].split(',') if t and not t.lower().startswith('version:')]
        tags.append('version:' + state['version'])
        strings = (STR * len(tags))(*(t.encode('utf8') for t in tags))
        array = StringArray(strings, len(tags))
        require(api.ugc('SetItemTags', BOOL, U64, C.POINTER(StringArray))(handle, C.byref(array)), 'Cannot update version tag.')
        notes = workshop_changenote((directory / 'notes.txt').read_text(encoding='utf-8')).encode('utf-8')
        require(b'\0' not in notes, 'NUL in release notes.')
        print(f'Uploading frozen {state["version"]} to Workshop {item} ({len(files)} files)...', flush=True)
        result = api.wait(api.ugc('SubmitItemUpdate', U64, U64, STR)(handle, notes), SubmitResult, 3404, timeout=600)
        require(result.item_id == item and not result.needs_agreement, 'Upload unconfirmed or Workshop agreement required.')
        after = api.read(item, 'english')
        require(after['visibility'] == before['visibility'] and after['owner'] == before['owner'],
                'Unexpected ownership/visibility change.')
        require(set(after['tags'].split(',')) == set(tags), 'Uploaded version tag did not match.')
        receipt.update(complete=True, result='OK', after=after)
        save(receipt_path, receipt)
        print(f'Steam confirmed upload OK; visibility preserved. Receipt: {receipt_path}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--steam-api-dll')
    args = parser.parse_args()
    try:
        upload(args.directory, args.steam_api_dll)
    except (RuntimeError, OSError, ValueError, KeyError, AttributeError) as error:
        print(f'STEAM UPLOAD STOPPED: {error}', file=sys.stderr)
        sys.exit(1)
