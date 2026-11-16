"""Offline remote readback tests; all GitHub and HTTP operations are fake."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_verify', ROOT / 'tools/release_verify.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class Response(io.BytesIO):
    def __init__(self, data, url):
        super().__init__(data)
        self.url = url

    def geturl(self):
        return self.url


class RemoteVerifyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.state = {'version': '1.2.3', 'audience': 'public', 'steps': {'commit': 'abc123'},
                      'config': {'repository': 'owner/repo', 'site_url': 'https://example.test/guide/'}}
        self.pages = {name: ('frozen page: ' + name).encode() for name in verify.PAGES}
        with zipfile.ZipFile(self.directory / 'field-guide-1.2.3.zip', 'w') as archive:
            for name, data in self.pages.items():
                archive.writestr(name, data)
        (self.directory / 'spellwoven-wands-1.2.3.zip').write_bytes(b'frozen mod')
        (self.directory / 'SHA256SUMS.txt').write_bytes(b'checksums')
        self.release = {'tag_name': 'v1.2.3', 'draft': False, 'prerelease': False, 'assets': []}
        for path in sorted(self.directory.iterdir()):
            data = path.read_bytes()
            self.release['assets'].append({'name': path.name, 'size': len(data),
                                           'digest': 'sha256:' + hashlib.sha256(data).hexdigest()})
        self.gh = Mock(side_effect=self.github)
        self.now = 0
        self.http = Mock(side_effect=self.urlopen)
        self.addCleanup(patch.stopall)
        patch.object(verify, 'urlopen', self.http).start()
        patch.object(verify.time, 'monotonic', side_effect=lambda: self.now).start()
        self.sleep = patch.object(verify.time, 'sleep', side_effect=self.advance).start()

    def advance(self, seconds):
        self.now += seconds

    def github(self, *args):
        if args == ('api', 'repos/owner/repo/commits/v1.2.3'):
            return {'sha': 'abc123'}
        if args == ('api', 'repos/owner/repo/releases/tags/v1.2.3'):
            return self.release
        raise AssertionError(args)

    def urlopen(self, url, timeout):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 10)
        self.assertEqual(urlsplit(url).query, 'release_commit=abc123')
        name = urlsplit(url).path.removeprefix('/guide/')
        return Response(self.pages[name], url)

    def run_verify(self):
        return verify.verify_remote(self.directory, self.state, self.gh)

    def test_public_success_has_six_full_page_hashes_and_serializable_evidence(self):
        before = copy.deepcopy(self.state)
        evidence = self.run_verify()
        self.assertEqual(evidence['github']['commit'], 'abc123')
        self.assertEqual(set(evidence['pages']['pages']), set(verify.PAGES))
        for name, page in evidence['pages']['pages'].items():
            self.assertEqual(page['sha256'], hashlib.sha256(self.pages[name]).hexdigest())
        self.assertTrue(all(a['digest_checked'] for a in evidence['github']['assets'].values()))
        json.dumps(evidence)
        self.assertEqual(self.state, before)
        self.assertEqual(self.http.call_count, 6)
        self.sleep.assert_not_called()

    def test_missing_digest_only_records_size_verification(self):
        for asset in self.release['assets']:
            asset.pop('digest')
        evidence = self.run_verify()
        self.assertTrue(all(not a['digest_checked'] and 'remote_digest' not in a
                            for a in evidence['github']['assets'].values()))

    def test_windows_frozen_html_matches_linux_pages_without_ignoring_content(self):
        archive_path = self.directory / 'field-guide-1.2.3.zip'
        with zipfile.ZipFile(archive_path, 'w') as archive:
            for name, data in self.pages.items():
                archive.writestr(name, data + b'\r\nsecond line\r\n')
                self.pages[name] = data + b'\nsecond line\n'
        raw = archive_path.read_bytes()
        asset = next(a for a in self.release['assets'] if a['name'] == archive_path.name)
        asset.update(size=len(raw), digest='sha256:' + hashlib.sha256(raw).hexdigest())
        evidence = self.run_verify()
        self.assertEqual(evidence['pages']['normalization'], 'CRLF to LF only')
        self.pages['index.html'] = self.pages['index.html'].replace(b'second line', b'different content')
        with self.assertRaisesRegex(verify.RemoteVerificationError, 'index.html.*SHA256 mismatch'):
            self.run_verify()

    def test_draft_tag_and_prerelease_must_match(self):
        for field, wrong, reason in (('draft', True, 'non-draft'),
                                     ('tag_name', 'v0.0.0', 'tag_name'),
                                     ('prerelease', True, 'prerelease')):
            with self.subTest(field=field):
                original = self.release[field]
                self.release[field] = wrong
                with self.assertRaisesRegex(verify.RemoteVerificationError, reason):
                    self.run_verify()
                self.release[field] = original
        self.http.assert_not_called()

    def test_remote_tag_commit_must_match(self):
        self.gh.side_effect = lambda *args: {'sha': 'different'}
        with self.assertRaisesRegex(verify.RemoteVerificationError, 'tag v1.2.3: SHA'):
            self.run_verify()
        self.http.assert_not_called()

    def test_missing_or_duplicate_attachment_rejected(self):
        original = copy.deepcopy(self.release['assets'])
        for assets in (original[1:], original + [original[0]]):
            with self.subTest(count=len(assets)):
                self.release['assets'] = assets
                with self.assertRaisesRegex(verify.RemoteVerificationError, 'exactly one attachment'):
                    self.run_verify()
        self.http.assert_not_called()

    def test_attachment_size_and_digest_rejected(self):
        asset = self.release['assets'][0]
        for field, wrong, reason in (('size', asset['size'] + 1, 'size differs'),
                                     ('digest', 'sha256:' + '0' * 64, 'digest differs'),
                                     ('digest', 'md5:unsupported', 'digest differs')):
            with self.subTest(field=field, wrong=wrong):
                original = asset[field]
                asset[field] = wrong
                with self.assertRaisesRegex(verify.RemoteVerificationError, reason):
                    self.run_verify()
                asset[field] = original

    def test_private_does_not_read_public_site(self):
        self.state['audience'] = 'private'
        self.state['config'].pop('site_url')
        self.release['prerelease'] = True
        self.assertEqual(self.run_verify()['pages']['status'], 'skipped')
        self.http.assert_not_called()

    def test_stale_page_retries_only_that_page_until_it_matches(self):
        calls = 0

        def eventual(url, timeout):
            nonlocal calls
            if '/en/updates.html?' in url:
                calls += 1
                if calls < 3:
                    return Response(b'old body with current version 1.2.3', url)
            return self.urlopen(url, timeout)

        self.http.side_effect = eventual
        evidence = self.run_verify()
        self.assertEqual(evidence['pages']['pages']['en/updates.html']['attempt'], 3)
        self.assertEqual(self.http.call_count, 8)
        self.assertEqual(self.now, 6)

    def test_stale_page_fails_with_filename_after_bounded_retry(self):
        def stale(url, timeout):
            return Response(b'old v1.2.3 content', url)

        self.http.side_effect = stale
        with self.assertRaisesRegex(verify.RemoteVerificationError, r'Pages v1.2.3:.*en/spells.html: SHA256 mismatch'):
            self.run_verify()
        self.assertLessEqual(self.now, 60)
        self.assertLessEqual(self.http.call_count, 126)
        self.assertTrue(all(call.args[0] <= 3 for call in self.sleep.call_args_list))

    def test_http_failure_is_retried_and_reports_http_code(self):
        self.http.side_effect = HTTPError('https://example.test', 503, 'unavailable', {}, None)
        with self.assertRaisesRegex(verify.RemoteVerificationError, 'index.html: HTTP 503'):
            self.run_verify()
        self.assertLessEqual(self.now, 60)
        self.assertLessEqual(self.http.call_count, 126)

    def test_slow_requests_share_one_global_deadline(self):
        def timeout(url, timeout):
            self.advance(timeout)
            raise TimeoutError()

        self.http.side_effect = timeout
        with self.assertRaisesRegex(verify.RemoteVerificationError, 'within 60s'):
            self.run_verify()
        self.assertEqual(self.now, 60)
        self.assertEqual(self.http.call_count, 6)

    def test_unsafe_site_url_rejected_before_http(self):
        for url in ('http://example.test/', 'https://secret@example.test/'):
            with self.subTest(url=url):
                self.state['config']['site_url'] = url
                with self.assertRaisesRegex(verify.RemoteVerificationError, 'HTTPS URL without credentials'):
                    self.run_verify()
        self.http.assert_not_called()

    def test_github_error_does_not_expose_credentials(self):
        self.gh.side_effect = RuntimeError('token=secret')
        with self.assertRaises(verify.RemoteVerificationError) as caught:
            self.run_verify()
        self.assertIn('GitHub tag v1.2.3', str(caught.exception))
        self.assertNotIn('secret', str(caught.exception))


if __name__ == '__main__':
    unittest.main()
