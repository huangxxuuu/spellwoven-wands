"""Native uploader validates frozen content and only mutates intended fields."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import steam_workshop_upload as upload


class NativeUploadTests(unittest.TestCase):
    def fixture(self, root):
        (root / 'content').mkdir()
        for name, value in [('content/modinfo.lua', 'version = "1.2.3"'), ('preview.png', 'preview'), ('notes.txt', 'notes')]:
            (root / name).write_text(value, encoding='utf8')
        hashes = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in root.rglob('*') if p.is_file()}
        (root / 'state.json').write_text(json.dumps(dict(version='1.2.3', steam_visibility='preserve',
            artifact_hashes=hashes, config=dict(app_id=322330, publishedfileid='3834454416'))), encoding='utf8')

    def test_tampered_and_extra_content_never_connects_to_steam(self):
        for extra in (False, True):
            with tempfile.TemporaryDirectory() as d, patch.object(upload, 'Steam', side_effect=AssertionError('Steam connected')):
                root = Path(d)
                self.fixture(root)
                (root / ('content/extra.lua' if extra else 'content/modinfo.lua')).write_text('changed')
                with self.assertRaises(RuntimeError):
                    upload.upload(root)

    def test_only_content_preview_and_version_tag_change(self):
        calls = []
        before = dict(owner=1, visibility=3, tags='item,all_clients_require_mod,version:0.25.5', tags_truncated=False)
        class Steam:
            owner, app_id = 1, 322330
            def __init__(self, *args): self.reads = 0
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, *args):
                self.reads += 1
                return dict(before, tags=before['tags'] if self.reads == 1 else 'item,all_clients_require_mod,version:1.2.3')
            def ugc(self, name, *args):
                calls.append(name)
                return lambda *values: 1
            def wait(self, *args, **kwargs):
                return SimpleNamespace(item_id=3834454416, needs_agreement=False)
        with tempfile.TemporaryDirectory() as d, patch.object(upload, 'Steam', Steam):
            root = Path(d)
            self.fixture(root)
            upload.upload(root)
            receipt = json.loads(next(root.glob('steam-api-upload-*.json')).read_text())
            self.assertTrue(receipt['complete'])
            self.assertEqual(calls, ['StartItemUpdate', 'SetItemContent', 'SetItemPreview', 'SetItemTags', 'SubmitItemUpdate'])


if __name__ == '__main__':
    unittest.main()
