"""Offline fixtures for bounded project context and frozen release comparison."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import context


class ContextTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "mod").mkdir()
        (self.root / "mod/modinfo.lua").write_text('version = "1.2.4"\n', encoding="utf-8")
        self.git("init", "-q")
        self.git("add", "mod/modinfo.lua")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True)

    def release(self, name, **overrides):
        state = {"version": name, "audience": "public", "release_kind": "code",
                 "steps": {key: True for key in
                           ("commit", "push", "github_draft", "steam", "pages", "github_release")}}
        state.update(overrides)
        directory = self.root / "dist/releases" / name
        directory.mkdir(parents=True)
        (directory / "state.json").write_text(json.dumps(state), encoding="utf-8")
        return directory

    def test_successful_formal_release_selection(self):
        expected = self.release("1.2.9")
        self.release("1.2.10", steps={"commit": True, "steam": True})
        self.release("1.3.0", audience="private")
        self.release("1.4.0", version="0.0.1")
        self.release("9.0.0-preflight", version="9.0.0")
        self.release("8.0.0", release_kind="metadata")
        self.assertEqual(context.latest_release(self.root), expected)
        self.release("1.2.11")
        self.assertEqual(context.latest_release(self.root).name, "1.2.11")

    def test_invalid_state_is_ignored(self):
        directory = self.release("1.0.0")
        (directory / "state.json").write_text("[]")
        self.assertIsNone(context.latest_release(self.root))
        (directory / "state.json").write_text("bad json")
        self.assertIsNone(context.latest_release(self.root))

    def test_git_unicode_spaces_untracked_and_bounded_scope(self):
        (self.root / "文档 空格").mkdir()
        for name in ("修改 一.txt", "新增 二.txt", "新增 三.txt"):
            (self.root / "文档 空格" / name).write_text("fixture", encoding="utf-8")
        self.git("add", "文档 空格/修改 一.txt")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "track one")
        (self.root / "文档 空格/修改 一.txt").write_text("changed", encoding="utf-8")
        summary = context.summarize(self.root, ["文档 空格"], limit=2)
        self.assertEqual(summary["current_version"], "1.2.4")
        self.assertEqual(summary["git"]["total"], 3)
        self.assertEqual(summary["git"]["untracked"], 2)
        self.assertEqual(summary["git"]["by_top_level"], {"文档 空格": 3})
        self.assertEqual(summary["git"]["changes"]["total"], 3)
        self.assertEqual(summary["git"]["changes"]["omitted"], 1)
        self.assertEqual(len(summary["git"]["changes"]["items"]), 2)
        self.assertNotIn("changes", context.summarize(self.root)["git"])
        self.assertEqual(context.summarize(self.root, ["文档 空格/新增 二.txt"])["git"]["changes"]["total"], 1)

    def test_rename_source_matches_scope(self):
        self.git("mv", "mod/modinfo.lua", "mod/renamed 中文.lua")
        changes = context.git_changes(self.root)
        self.assertEqual(changes[0]["original_path"], "mod/modinfo.lua")
        self.assertEqual(changes[0]["path"], "mod/renamed 中文.lua")
        self.assertTrue(context.matches_scope(changes[0]["original_path"], ["mod/modinfo.lua"]))

    def test_top_level_summary_is_bounded_and_scope_filters_groups(self):
        for index in range(30):
            (self.root / f"root file {index}.txt").write_text("fixture")
        for name in ("aaa", "bbb", "ccc", "mod"):
            directory = self.root / name
            directory.mkdir(exist_ok=True)
            (directory / "new.txt").write_text("fixture")
        git = context.summarize(self.root, limit=1)["git"]
        self.assertEqual(git["total"], 34)
        self.assertEqual(git["untracked"], 34)
        self.assertEqual(git["by_top_level"], {".": 30})
        self.assertEqual(git["by_top_level_total"], 5)
        self.assertEqual(git["by_top_level_omitted"], 4)
        self.assertEqual(git["by_top_level_omitted_changes"], 4)
        scoped = context.summarize(self.root, ["mod"], limit=1)
        self.assertEqual(scoped["git"]["total"], 34)
        self.assertEqual(scoped["git"]["by_top_level"], {"mod": 1})
        self.assertEqual(scoped["git"]["by_top_level_omitted"], 0)
        self.assertEqual(scoped["git"]["changes"]["total"], 1)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            context.display(scoped)
        self.assertLess(len(output.getvalue().splitlines()), 10)

    def test_display_escapes_dynamic_group_names(self):
        # Control characters cannot be created in Windows filenames; a Git parser fixture
        # also covers repositories read on systems where those filenames are valid.
        with patch.object(context, "git_changes", return_value=[{"status": "??", "path": "odd\nname/file"}]):
            summary = context.summarize(self.root)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            context.display(summary)
        self.assertIn('"odd\\nname": 1', output.getvalue())
        self.assertNotIn("odd\nname", output.getvalue())

    def test_scope_must_stay_inside_repository(self):
        for scope in ("../outside", str(self.root.parent / "outside")):
            with self.subTest(scope=scope), self.assertRaises(ValueError):
                context.summarize(self.root, [scope])
        self.assertEqual(context.normalize_scopes(self.root, ["mod/../mod"]), ["mod"])
        self.assertFalse(context.matches_scope("model/file.lua", ["mod"]))

    def test_release_diff_compares_mod_bytes_only(self):
        release = self.release("1.2.3")
        baseline = release / "content"
        baseline.mkdir()
        (baseline / "modinfo.lua").write_text('version = "1.2.3"\n')
        (baseline / "same.lua").write_bytes(b"same")
        (baseline / "removed.lua").write_bytes(b"removed")
        (self.root / "mod/same.lua").write_bytes(b"same")
        (self.root / "mod/added.lua").write_bytes(b"added")
        (self.root / "outside.txt").write_text("must not be compared")
        diff = context.summarize(self.root, include_release_diff=True)["release_diff"]
        self.assertTrue(diff["available"])
        self.assertEqual(diff["baseline"], "1.2.3")
        self.assertEqual(diff["added"]["items"], ["added.lua"])
        self.assertEqual(diff["modified"]["items"], ["modinfo.lua"])
        self.assertEqual(diff["deleted"]["items"], ["removed.lua"])
        self.assertEqual(context.release_diff(self.root, release, 0)["added"]["omitted"], 1)

    def test_missing_baseline_is_explicit(self):
        diff = context.summarize(self.root, include_release_diff=True)["release_diff"]
        self.assertFalse(diff["available"])
        self.assertIn("No successful public release", diff["reason"])
        release = self.release("1.2.3")
        self.assertFalse(context.release_diff(self.root, release, 20)["available"])

    def test_missing_current_mod_directory_is_an_error(self):
        release = self.release("1.2.3")
        (release / "content").mkdir()
        (release / "content/old.lua").write_text("fixture")
        missing_root = self.root / "missing_checkout"
        with self.assertRaisesRegex(ValueError, "directory does not exist"):
            context.release_diff(missing_root, release, 20)


if __name__ == "__main__":
    unittest.main()
