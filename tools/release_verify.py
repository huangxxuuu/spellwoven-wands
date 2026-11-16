"""Read-only final verification of the frozen release on GitHub and Pages."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import time
from urllib.error import HTTPError
from urllib.parse import quote, urljoin, urlsplit
from urllib.request import urlopen
import zipfile

PAGES = tuple(prefix + name for prefix in ('', 'en/')
              for name in ('index.html', 'updates.html', 'spells.html'))
PAGES_WINDOW_SECONDS = 60
REQUEST_TIMEOUT_SECONDS = 10
RETRY_SLEEP_SECONDS = 3


class RemoteVerificationError(RuntimeError):
    pass


def _require(condition, message):
    if not condition:
        raise RemoteVerificationError(message)


def _sha256(data):
    return hashlib.sha256(data).hexdigest()


def _page_sha256(data):
    # Windows freezes CRLF HTML; the Linux Pages builder writes LF. Preserve
    # every other byte, including whitespace, so real content drift still fails.
    return _sha256(data.replace(b'\r\n', b'\n'))


def _github(gh_json, endpoint, description):
    try:
        result = gh_json('api', endpoint)
    except Exception as exc:
        # CLI exceptions may contain an authenticated command or response body.
        status = re.search(r'\bHTTP\s+\d{3}\b', str(exc), re.I)
        detail = f'; {status[0]}' if status else ''
        raise RemoteVerificationError(f'GitHub {description}: API read failed ({type(exc).__name__}{detail}).') from None
    _require(isinstance(result, dict), f'GitHub {description}: invalid API response.')
    return result


def _fetch(url, timeout):
    with urlopen(url, timeout=timeout) as response:
        _require(urlsplit(response.geturl()).scheme == 'https', 'Pages redirected away from HTTPS.')
        return response.read()


def _verify_pages(directory, state):
    version, commit = state['version'], state['steps']['commit']
    base = state['config'].get('site_url', '')
    parsed = urlsplit(base)
    _require(parsed.scheme == 'https' and parsed.netloc and not parsed.username
             and not parsed.password and not parsed.query and not parsed.fragment,
             f'Pages v{version}: config.site_url must be an HTTPS URL without credentials, query or fragment.')
    archive_path = directory / f'field-guide-{version}.zip'
    try:
        with zipfile.ZipFile(archive_path) as archive:
            expected = {name: _page_sha256(archive.read(name)) for name in PAGES}
    except (OSError, KeyError, zipfile.BadZipFile) as exc:
        raise RemoteVerificationError(f'Pages v{version}: frozen {archive_path.name} lacks readable page content ({type(exc).__name__}).') from None
    pending = dict(expected)
    evidence, failures = {}, {}
    deadline = time.monotonic() + PAGES_WINDOW_SECONDS
    # The attempt bound also makes retry termination independent of clock quirks.
    for attempt in range(1, 22):
        for name, wanted in list(pending.items()):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            url = urljoin(base.rstrip('/') + '/', name) + '?release_commit=' + quote(commit, safe='')
            try:
                actual = _page_sha256(_fetch(url, min(REQUEST_TIMEOUT_SECONDS, remaining)))
                if actual != wanted:
                    failures[name] = f'SHA256 mismatch (expected {wanted}, received {actual})'
                    continue
                evidence[name] = {'url': url, 'sha256': actual, 'attempt': attempt}
                del pending[name]
            except Exception as exc:
                failures[name] = (f'HTTP {exc.code}' if isinstance(exc, HTTPError)
                                  else f'GET failed ({type(exc).__name__})')
        if not pending:
            return {'status': 'verified', 'normalization': 'CRLF to LF only', 'pages': evidence}
        remaining = deadline - time.monotonic()
        if remaining <= 0 or attempt == 21:
            break
        time.sleep(min(RETRY_SLEEP_SECONDS, remaining))
    details = '; '.join(f'{name}: {failures.get(name, "verification deadline reached")}' for name in pending)
    raise RemoteVerificationError(f'Pages v{version}: deployment verification failed within {PAGES_WINDOW_SECONDS}s: {details}')


def verify_remote(directory: Path, state: dict, gh_json: callable) -> dict:
    """Return JSON evidence only after all applicable remote readbacks pass.

    The caller persists this result. No release state or remote data is mutated.
    An absent GitHub asset digest is recorded as unchecked, never as hash proof.
    """
    directory = Path(directory)
    version, audience = state['version'], state['audience']
    _require(audience in ('public', 'private'), f'GitHub v{version}: unsupported audience {audience!r}.')
    repo, commit = state['config']['repository'], state['steps'].get('commit')
    _require(bool(commit), f'GitHub v{version}: missing recorded release commit.')
    tag = f'v{version}'
    endpoint_tag = quote(tag, safe='')
    remote_commit = _github(gh_json, f'repos/{repo}/commits/{endpoint_tag}', f'tag {tag}')
    _require(remote_commit.get('sha') == commit, f'GitHub tag {tag}: SHA differs from recorded commit {commit}.')
    release = _github(gh_json, f'repos/{repo}/releases/tags/{endpoint_tag}', f'Release {tag}')
    _require(release.get('tag_name') == tag, f'GitHub Release {tag}: tag_name differs.')
    _require(release.get('draft') is False, f'GitHub Release {tag}: expected a non-draft release.')
    _require(release.get('prerelease') is (audience == 'private'),
             f'GitHub Release {tag}: prerelease differs from {audience} audience.')
    assets = release.get('assets')
    _require(isinstance(assets, list), f'GitHub Release {tag}: missing assets list.')
    evidence = {}
    for name in (f'spellwoven-wands-{version}.zip', f'field-guide-{version}.zip', 'SHA256SUMS.txt'):
        matches = [asset for asset in assets if isinstance(asset, dict) and asset.get('name') == name]
        _require(len(matches) == 1, f'GitHub Release {tag}: expected exactly one attachment {name}, found {len(matches)}.')
        try:
            local = (directory / name).read_bytes()
        except OSError:
            raise RemoteVerificationError(f'GitHub Release {tag}: cannot read frozen local attachment {name}.') from None
        asset = matches[0]
        _require(type(asset.get('size')) is int and asset['size'] == len(local),
                 f'GitHub Release {tag}: attachment {name} size differs from frozen local file ({len(local)} bytes).')
        local_digest = _sha256(local)
        remote_digest = asset.get('digest')
        if remote_digest:
            _require(isinstance(remote_digest, str) and remote_digest.lower() == 'sha256:' + local_digest,
                     f'GitHub Release {tag}: attachment {name} SHA256 digest differs or is unsupported.')
        evidence[name] = {'size': len(local), 'local_sha256': local_digest,
                          'digest_checked': bool(remote_digest)}
        if remote_digest:
            evidence[name]['remote_digest'] = remote_digest
    result = {'version': version, 'audience': audience,
              'github': {'repository': repo, 'tag': tag, 'commit': commit,
                         'draft': False, 'prerelease': audience == 'private', 'assets': evidence}}
    result['pages'] = (_verify_pages(directory, state) if audience == 'public'
                       else {'status': 'skipped', 'reason': 'private audience'})
    return result
