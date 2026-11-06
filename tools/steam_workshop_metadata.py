"""Update only localized Workshop titles/descriptions using the logged-in Steam client.

Windows x64; uses DST's installed Steam API DLL (SDK 1.51), never redistributes it.
ABI source: ValveSoftware/Proton, steamworks_sdk_151/isteamugc.h.
https://partner.steamgames.com/doc/api/ISteamUGC#SetItemUpdateLanguage
No passwords, browser cookies, Web API keys, new items or visibility changes.
"""
from __future__ import annotations

import argparse
import ctypes as C
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
U64, U32, INT, BOOL, PTR, STR = C.c_uint64, C.c_uint32, C.c_int32, C.c_bool, C.c_void_p, C.c_char_p
INVALID = (1 << 64) - 1


class MetadataError(RuntimeError):
    pass


def require(ok, message):
    if not ok:
        raise MetadataError(message)


class QueryResult(C.Structure):
    _pack_ = 8
    _fields_ = [('handle', U64), ('result', INT), ('count', U32), ('total', U32),
                ('cached', BOOL), ('cursor', C.c_char * 256)]


class SubmitResult(C.Structure):
    _pack_ = 8
    _fields_ = [('result', INT), ('needs_agreement', BOOL), ('item_id', U64)]


class Details(C.Structure):
    _pack_ = 8
    _fields_ = [('item_id', U64), ('result', INT), ('file_type', INT), ('creator_app', U32),
                ('consumer_app', U32), ('title', C.c_char * 129), ('description', C.c_char * 8000),
                ('owner', U64), ('created', U32), ('updated', U32), ('added', U32),
                ('visibility', INT), ('banned', BOOL), ('accepted', BOOL), ('tags_truncated', BOOL),
                ('tags', C.c_char * 1025), ('file', U64), ('preview', U64),
                ('filename', C.c_char * 260), ('file_size', INT), ('preview_size', INT),
                ('url', C.c_char * 256), ('votes_up', U32), ('votes_down', U32),
                ('score', C.c_float), ('children', U32)]


def find_dll(explicit=None):
    if explicit:
        path = Path(explicit).resolve()
        require(path.is_file(), f'Steam API DLL not found: {path}')
        return path
    require(sys.platform == 'win32', 'This publisher requires Windows and 64-bit Python.')
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Valve\Steam') as key:
        steam = Path(winreg.QueryValueEx(key, 'SteamPath')[0])
    libraries = [steam]
    vdf = steam / 'steamapps/libraryfolders.vdf'
    if vdf.is_file():
        libraries += [Path(p.replace('\\\\', '\\')) for p in
                      re.findall(r'"path"\s+"([^"]+)"', vdf.read_text(encoding='utf8'))]
    for library in libraries:
        dll = library / "steamapps/common/Don't Starve Together/bin64/steam_api64.dll"
        if dll.is_file():
            return dll
    raise MetadataError('Install DST or pass --steam-api-dll PATH to its bin64/steam_api64.dll.')


class Steam:
    def __init__(self, app_id, dll=None):
        require(sys.platform == 'win32' and C.sizeof(PTR) == 8, 'Use Windows with 64-bit Python.')
        self.app_id = app_id
        self.path = find_dll(dll)
        self.dll = C.CDLL(str(self.path))
        self.started = False

    def fn(self, name, restype, *args):
        fn = getattr(self.dll, name)
        fn.restype, fn.argtypes = restype, list(args)
        return fn

    def ugc(self, name, restype, *args):
        fn = self.fn('SteamAPI_ISteamUGC_' + name, restype, PTR, *args)
        return lambda *values: fn(self.ugc_ptr, *values)

    def __enter__(self):
        self.old_env = {k: os.environ.get(k) for k in ('SteamAppId', 'SteamGameId')}
        os.environ.update(SteamAppId=str(self.app_id), SteamGameId=str(self.app_id))
        try:
            require(self.fn('SteamAPI_Init', BOOL)(), 'Steam API initialization failed. Log into Steam as the item owner.')
            self.started = True
            # Bind the exact ABI shipped by DST; fail clearly if its SDK changes.
            self.ugc_ptr = self.fn('SteamAPI_SteamUGC_v015', PTR)()
            self.utils = self.fn('SteamAPI_SteamUtils_v010', PTR)()
            user = self.fn('SteamAPI_SteamUser_v021', PTR)()
            require(self.ugc_ptr and self.utils and user, 'Required Steam interfaces unavailable.')
            require(self.fn('SteamAPI_ISteamUtils_GetAppID', U32, PTR)(self.utils) == self.app_id,
                    'Steam initialized for a different app.')
            self.owner = self.fn('SteamAPI_ISteamUser_GetSteamID', U64, PTR)(user)
            return self
        except Exception:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *args):
        if self.started:
            self.fn('SteamAPI_Shutdown', None)()
            self.started = False
        for key, value in self.old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def wait(self, call, structure, callback, timeout=90):
        require(call != 0, 'Steam returned an invalid asynchronous call.')
        complete = self.fn('SteamAPI_ISteamUtils_IsAPICallCompleted', BOOL, PTR, U64, C.POINTER(BOOL))
        result_fn = self.fn('SteamAPI_ISteamUtils_GetAPICallResult', BOOL, PTR, U64, PTR, INT, INT, C.POINTER(BOOL))
        failed, result = BOOL(), structure()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if complete(self.utils, call, C.byref(failed)):
                require(not failed.value, 'Steam asynchronous operation failed.')
                require(result_fn(self.utils, call, C.byref(result), C.sizeof(result), callback, C.byref(failed))
                        and not failed.value, 'Steam result ABI/callback mismatch or I/O failure.')
                require(result.result == 1, f'Steam returned EResult={result.result}; operation not confirmed.')
                return result
            time.sleep(.1)
        raise MetadataError('Steam operation timed out; inspect current metadata before retrying.')

    def read(self, item_id, language):
        ids = (U64 * 1)(item_id)
        handle = self.ugc('CreateQueryUGCDetailsRequest', U64, C.POINTER(U64), U32)(ids, 1)
        require(handle not in (0, INVALID), 'Invalid Steam query handle.')
        try:
            require(self.ugc('SetLanguage', BOOL, U64, STR)(handle, language.encode()), 'Cannot set query language.')
            require(self.ugc('SetReturnLongDescription', BOOL, U64, BOOL)(handle, True), 'Cannot query full description.')
            require(self.ugc('SetAllowCachedResponse', BOOL, U64, U32)(handle, 0), 'Cannot disable query cache.')
            result = self.wait(self.ugc('SendQueryUGCRequest', U64, U64)(handle), QueryResult, 3401)
            require(result.handle == handle and result.count == 1, 'Workshop item missing or inaccessible.')
            details = Details()
            require(self.ugc('GetQueryUGCResult', BOOL, U64, U32, C.POINTER(Details))(handle, 0, C.byref(details)),
                    'Cannot read Workshop details.')
            row = {key: (value.decode('utf8') if isinstance(value, bytes) else value)
                   for key, _ in Details._fields_ for value in [getattr(details, key)]}
            require(row['result'] == 1 and row['item_id'] == item_id and row['consumer_app'] == self.app_id,
                    'Unexpected Workshop item, app or result.')
            return row
        finally:
            self.ugc('ReleaseQueryUGCRequest', BOOL, U64)(handle)

    def write(self, item_id, language, row):
        handle = self.ugc('StartItemUpdate', U64, U32, U64)(self.app_id, item_id)
        require(handle not in (0, INVALID), 'Invalid Steam update handle.')
        for name, value in [('SetItemUpdateLanguage', language), ('SetItemTitle', row['title']),
                            ('SetItemDescription', row['description'])]:
            require(self.ugc(name, BOOL, U64, STR)(handle, value.encode('utf8')), f'{name} failed.')
        result = self.wait(self.ugc('SubmitItemUpdate', U64, U64, STR)(handle, None), SubmitResult, 3404)
        require(result.item_id == item_id, 'Steam updated an unexpected item.')
        require(not result.needs_agreement, 'Accept the Steam Workshop legal agreement before publishing.')


def load_snapshot(root=ROOT, path=None):
    if path:
        payload = json.loads(Path(path).read_text(encoding='utf8'))
    else:
        config = json.loads((root / 'tools/release_config.json').read_text(encoding='utf8'))
        payload = {key: config[key] for key in ('app_id', 'publishedfileid')}
        payload['languages'] = {language: {'title': row['title'],
            'description': (root / row['description']).read_text(encoding='utf-8-sig')}
            for language, row in config['workshop_languages'].items()}
    require(payload['app_id'] == 322330, 'Only DST Workshop items are supported.')
    require(str(payload['publishedfileid']).isdigit() and 0 < int(payload['publishedfileid']) < INVALID,
            'An existing Workshop item ID is required.')
    require(set(payload['languages']) == {'schinese', 'english'}, 'Both schinese and english must be supplied.')
    for language, row in payload['languages'].items():
        for field, limit in [('title', 129), ('description', 8000)]:
            text = row[field]
            require(isinstance(text, str) and '\0' not in text and 0 < len(text.encode('utf8')) < limit,
                    f'{language} {field} is empty, contains NUL or exceeds its UTF-8 byte limit.')
    return payload


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    temp.replace(path)


def same_text(actual, desired):
    return all(actual[k].replace('\r\n', '\n') == desired[k].replace('\r\n', '\n')
               for k in ('title', 'description'))


def publish(api, payload, receipt_path):
    item = int(payload['publishedfileid'])
    before = {lang: api.read(item, lang) for lang in payload['languages']}
    require(all(row['owner'] == api.owner for row in before.values()), 'Logged-in Steam user does not own this item.')
    receipt = {'publishedfileid': str(item), 'time_utc': datetime.now(timezone.utc).isoformat(),
               'before': before, 'languages': {}, 'complete': False}
    save(receipt_path, receipt)  # Backup before any remote write, including partial failures.
    invariants = ('owner', 'consumer_app', 'creator_app', 'created', 'visibility', 'tags',
                  'file', 'preview', 'filename', 'file_size', 'preview_size')
    for language, desired in payload['languages'].items():
        if not same_text(before[language], desired):
            print(f'Updating Workshop {item}: {language}...', flush=True)
            api.write(item, language, desired)
        actual = api.read(item, language)
        for attempt in range(5):
            if same_text(actual, desired):
                break
            time.sleep(2)
            actual = api.read(item, language)
        require(same_text(actual, desired), f'{language}: Steam read-back differs from source; not marked complete.')
        require(all(actual[k] == before[language][k] for k in invariants),
                f'{language}: an unrelated Workshop field changed; inspect the backup.')
        receipt['languages'][language] = {'verified': True, 'title': actual['title'],
            'description_sha256': hashlib.sha256(actual['description'].encode('utf8')).hexdigest(),
            'description_bytes': len(actual['description'].encode('utf8')), 'visibility': actual['visibility']}
        save(receipt_path, receipt)
        print(f'Verified {language}: full description matches; visibility/content preserved.', flush=True)
    receipt['complete'] = True
    save(receipt_path, receipt)
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['plan', 'check', 'publish'], default='plan')
    parser.add_argument('--snapshot', type=Path)
    parser.add_argument('--steam-api-dll', default=os.environ.get('STEAM_API_DLL'))
    parser.add_argument('--receipt', type=Path)
    args = parser.parse_args(argv)
    payload = load_snapshot(path=args.snapshot)
    if args.mode == 'plan':
        for lang, row in payload['languages'].items():
            print(f'{payload["publishedfileid"]} {lang}: {len(row["description"].encode("utf8"))} UTF-8 bytes')
        print('Plan only. No Steam calls made. Use --mode publish to update both languages.')
        return
    with Steam(payload['app_id'], args.steam_api_dll) as api:
        if args.mode == 'check':
            for lang, desired in payload['languages'].items():
                row = api.read(int(payload['publishedfileid']), lang)
                print(json.dumps({'language': lang, 'title': row['title'], 'matches_source': same_text(row, desired),
                    'description_bytes': len(row['description'].encode('utf8')), 'visibility': row['visibility'],
                    'owned_by_current_user': row['owner'] == api.owner}, ensure_ascii=True))
        else:
            path = args.receipt or ROOT / 'dist/workshop-metadata' / (datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.json')
            require(not path.exists(), 'Receipt already exists; choose a new path to preserve the original backup.')
            publish(api, payload, path)
            print(f'Backup and verification receipt: {path}')


if __name__ == '__main__':
    try:
        main()
    except (MetadataError, OSError, ValueError, KeyError, AttributeError) as error:
        print(f'WORKSHOP METADATA STOPPED: {error}', file=sys.stderr)
        sys.exit(1)
