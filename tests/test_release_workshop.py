"""Offline regression coverage for localized Steam updates (no Steam login needed)."""
import copy
import ctypes
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('metadata', ROOT / 'tools/steam_workshop_metadata.py')
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class FakeSteam:
    owner = 42

    def __init__(self, fail_language=None, wrong_readback=False):
        self.fail_language, self.wrong_readback = fail_language, wrong_readback
        self.writes = []
        row = dict(owner=42, consumer_app=322330, creator_app=245850, created=1, visibility=3,
                   tags='Version:0.25.7', file=123, preview=456, filename='mod.zip', file_size=100,
                   preview_size=200, title='旧标题', description='旧中文描述')
        self.rows = {lang: dict(row) for lang in ('schinese', 'english')}

    def read(self, item, language):
        return dict(self.rows[language])

    def write(self, item, language, row):
        self.writes.append(language)
        if language == self.fail_language:
            raise metadata.MetadataError('simulated Steam failure')
        if not self.wrong_readback:
            self.rows[language].update(row)


class WorkshopTests(unittest.TestCase):
    def payload(self):
        return dict(app_id=322330, publishedfileid='3834454416', languages={
            'schinese': dict(title='织法之杖', description='中文版'),
            'english': dict(title='Spellwoven Wands', description='English description')})

    def test_sdk151_windows_abi(self):
        self.assertEqual(ctypes.sizeof(metadata.QueryResult), 280)
        self.assertEqual(ctypes.sizeof(metadata.SubmitResult), 16)
        self.assertEqual(metadata.Details.title.offset, 24)
        self.assertEqual(metadata.Details.description.offset, 153)
        self.assertEqual(metadata.Details.owner.offset, 8160)
        self.assertEqual(ctypes.sizeof(metadata.Details), 9776)

    def test_both_language_fields_verified_independently_and_backup_retained(self):
        with tempfile.TemporaryDirectory() as d:
            api = FakeSteam()
            receipt = metadata.publish(api, self.payload(), Path(d) / 'receipt.json')
            self.assertEqual(api.writes, ['schinese', 'english'])
            self.assertTrue(receipt['complete'])
            self.assertEqual(receipt['before']['english']['description'], '旧中文描述')
            self.assertEqual(api.rows['english']['description'], 'English description')
            self.assertEqual(api.rows['schinese']['description'], '中文版')
            self.assertTrue(all(r['visibility'] == 3 for r in receipt['languages'].values()))

    def test_partial_failure_remains_incomplete_and_retry_skips_matching_language(self):
        with tempfile.TemporaryDirectory() as d:
            api = FakeSteam(fail_language='english')
            path = Path(d) / 'first.json'
            with self.assertRaises(metadata.MetadataError):
                metadata.publish(api, self.payload(), path)
            receipt = json.loads(path.read_text(encoding='utf8'))
            self.assertFalse(receipt['complete'])
            self.assertEqual(set(receipt['languages']), {'schinese'})
            api.fail_language = None
            api.writes.clear()
            metadata.publish(api, self.payload(), Path(d) / 'retry.json')
            self.assertEqual(api.writes, ['english'])

    def test_successful_submission_without_matching_readback_fails(self):
        with tempfile.TemporaryDirectory() as d, patch.object(metadata.time, 'sleep'):
            path = Path(d) / 'receipt.json'
            with self.assertRaises(metadata.MetadataError):
                metadata.publish(FakeSteam(wrong_readback=True), self.payload(), path)
            self.assertFalse(json.loads(path.read_text(encoding='utf8'))['complete'])

    def test_different_owner_cannot_publish(self):
        api = FakeSteam()
        api.owner = 7
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(metadata.MetadataError):
                metadata.publish(api, self.payload(), Path(d) / 'receipt.json')
        self.assertEqual(api.writes, [])

    def test_validate_both_sources_utf8_limits_and_nul(self):
        self.assertEqual(set(metadata.load_snapshot()['languages']), {'schinese', 'english'})
        for mutation in ('missing', 'too_long', 'nul'):
            payload = copy.deepcopy(self.payload())
            if mutation == 'missing':
                del payload['languages']['english']
            else:
                payload['languages']['schinese']['description'] = '字' * 2700 if mutation == 'too_long' else 'bad\0text'
            with tempfile.TemporaryDirectory() as d:
                path = Path(d) / 'input.json'
                path.write_text(json.dumps(payload), encoding='utf8')
                with self.assertRaises(metadata.MetadataError):
                    metadata.load_snapshot(path=path)

    def test_plan_does_not_load_steam(self):
        with patch.object(metadata, 'Steam', side_effect=AssertionError('plan connected to Steam')):
            metadata.main([])


if __name__ == '__main__':
    unittest.main()
