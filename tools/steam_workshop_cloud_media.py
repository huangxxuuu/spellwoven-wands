"""Share only specified Workshop artwork through Steam Cloud and verify public bytes.

Uses content-addressed names so game saves and existing cloud files are untouched.
The manifest records every successful share before the next upload begins.
"""
import argparse
import ctypes as C
import hashlib
import json
from pathlib import Path
import urllib.request
from steam_workshop_metadata import Steam, INT, U64, BOOL, PTR, STR, require, save


class Shared(C.Structure):
    _pack_ = 8
    _fields_ = [('result', INT), ('handle', U64), ('filename', C.c_char * 260)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    manifest = args.directory / 'steam-cloud-media.json'
    rows = json.loads(manifest.read_text('utf8')) if manifest.exists() else {}
    with Steam(322330) as api:
        require(api.read(3834454416, 'schinese')['owner'] == api.owner, 'Not the Workshop owner')
        rs = api.fn('SteamAPI_SteamRemoteStorage_v014', PTR)()
        require(rs, 'Steam RemoteStorage unavailable')
        for p in sorted(args.directory.iterdir()):
            if p.suffix not in ('.gif', '.png', '.jpg'):
                continue
            data = p.read_bytes()
            digest = hashlib.sha1(data).hexdigest().upper()
            require(0 < len(data) < 16 * 1024 * 1024, 'Unexpected artwork size')
            old = rows.get(p.name)
            if old and old['sha1'] == digest:
                url = old['url']
            else:
                name = ('nw_workshop_media_' + digest + p.suffix).encode('ascii')
                exists = api.fn('SteamAPI_ISteamRemoteStorage_FileExists', BOOL, PTR, STR)(rs, name)
                if exists:
                    size = api.fn('SteamAPI_ISteamRemoteStorage_GetFileSize', INT, PTR, STR)(rs, name)
                    require(size == len(data), 'Cloud name collision')
                    buf = C.create_string_buffer(size)
                    count = api.fn('SteamAPI_ISteamRemoteStorage_FileRead', INT, PTR, STR, PTR, INT)(rs, name, buf, size)
                    require(count == size and buf.raw == data, 'Cloud contents differ; not overwriting')
                else:
                    require(api.fn('SteamAPI_ISteamRemoteStorage_FileWrite', BOOL, PTR, STR, PTR, INT)(
                        rs, name, C.create_string_buffer(data), len(data)), 'Cloud write rejected')
                result = api.wait(api.fn('SteamAPI_ISteamRemoteStorage_FileShare', U64, PTR, STR)(rs, name), Shared, 1307)
                url = f'https://images.steamusercontent.com/ugc/{result.handle}/{digest}/'
                rows[p.name] = dict(sha1=digest, bytes=len(data), handle=result.handle, url=url, verified=False)
                save(manifest, rows)
            with urllib.request.urlopen(url, timeout=45) as response:
                require(response.status == 200 and response.read() == data, 'Public artwork differs')
            rows[p.name]['verified'] = True
            save(manifest, rows)
            print('Verified public artwork:', p.name, flush=True)


if __name__ == '__main__':
    main()
