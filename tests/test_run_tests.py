"""Offline regression checks for Lua runner selection and isolation."""
import contextlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import run_tests


class RunTestsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tests").mkdir()
        (self.root / "mod").mkdir()
        for name in ("test_a.lua", "test_b.lua"):
            (self.root / "tests" / name).write_text("assert(_VERSION == 'Lua 5.1')", encoding="utf-8")
        (self.root / "tests/helper.lua").write_text("", encoding="utf-8")

    def test_default_and_explicit_selection(self):
        self.assertEqual([p.name for p in run_tests.select_tests([], self.root)],
                         ["test_a.lua", "test_b.lua"])
        paths = run_tests.select_tests(["tests/test_b.lua", "tests/test_a.lua", "tests/test_b.lua"], self.root)
        self.assertEqual([p.name for p in paths], ["test_b.lua", "test_a.lua"])

    def test_unknown_non_test_and_empty_fail(self):
        for name in ("tests/test_missing.lua", "tests/helper.lua", "../test_a.lua", "tests/test_*.lua"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                run_tests.select_tests([name], self.root)
        with self.assertRaises(ValueError):
            run_tests.select_tests([], self.root / "empty")

    def test_test_symlink_cannot_escape_or_enter_default_selection(self):
        target = self.root / "outside.lua"
        target.write_text("error('external link executed')", encoding="utf-8")
        link = self.root / "tests/test_link.lua"
        try:
            link.symlink_to(target)
        except OSError as exc:
            self.skipTest(f"Symlinks unavailable: {exc}")
        with self.assertRaises(ValueError):
            run_tests.select_tests(["tests/test_link.lua"], self.root)
        selected = run_tests.select_tests([], self.root)
        self.assertEqual([path.name for path in selected], ["test_a.lua", "test_b.lua"])
        with patch.object(run_tests, "ROOT", self.root), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run_tests.run_tests(selected), 0)
        # Even a symlink to a legitimate test is not itself an executable test entry.
        link.unlink()
        link.symlink_to(self.root / "tests/test_a.lua")
        with self.assertRaises(ValueError):
            run_tests.select_tests(["tests/test_link.lua"], self.root)


    def test_each_test_has_fresh_lua51_runtime(self):
        (self.root / "tests/test_a.lua").write_text("assert(_VERSION == 'Lua 5.1'); leaked = true; package.loaded.leaked = true")
        (self.root / "tests/test_b.lua").write_text("assert(leaked == nil); assert(package.loaded.leaked == nil)")
        with patch.object(run_tests, "ROOT", self.root), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run_tests.run_tests(run_tests.select_tests([], self.root)), 0)

    def test_selected_run_still_checks_all_mod_syntax(self):
        (self.root / "mod/broken.lua").write_text("local = broken", encoding="utf-8")
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(run_tests, "ROOT", self.root), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            self.assertEqual(run_tests.run_tests(run_tests.select_tests(["tests/test_a.lua"], self.root)), 1)
        self.assertIn("syntax mod/broken.lua", errors.getvalue())
        self.assertIn("LuaError", errors.getvalue())
        self.assertIn("passed=0 failed=1", output.getvalue())

    def test_list_and_invalid_cli_from_another_cwd(self):
        command = [sys.executable, str(ROOT / "tools/run_tests.py")]
        result = subprocess.run(command + ["tests/test_world_bounds.lua", "--list"],
                                cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "tests/test_world_bounds.lua")
        failed = subprocess.run(command + ["tests/unknown.lua"], cwd=self.root, capture_output=True, text=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("Unknown Lua test", failed.stderr)

    def test_cli_selection_list_only_and_failure_exit(self):
        (self.root / "tools").mkdir()
        script = self.root / "tools/run_tests.py"
        shutil.copy2(ROOT / "tools/run_tests.py", script)
        (self.root / "tests/test_b.lua").write_text("error('selected failure')", encoding="utf-8")
        command = [sys.executable, str(script)]
        selected = subprocess.run(command + ["tests/test_a.lua"], cwd=self.root.parent,
                                  capture_output=True, text=True)
        self.assertEqual(selected.returncode, 0, selected.stderr)
        self.assertIn("passed=1 failed=0", selected.stdout)
        self.assertNotIn("PASS test_a.lua", selected.stdout)
        self.assertNotIn("test_b.lua", selected.stdout)
        listed = subprocess.run(command + ["tests/test_b.lua", "--list"], cwd=self.root.parent,
                                capture_output=True, text=True)
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual(listed.stdout.strip(), "tests/test_b.lua")
        failed = subprocess.run(command, cwd=self.root.parent, capture_output=True, text=True)
        self.assertNotEqual(failed.returncode, 0)
        self.assertIn("selected failure", failed.stderr)
        self.assertIn("tests/test_b.lua", failed.stderr)
        self.assertIn("stack traceback", failed.stderr)
        self.assertIn("passed=1 failed=1", failed.stdout)


    def test_native_output_is_quiet_logged_and_verbose_is_complete(self):
        (self.root / "tools").mkdir()
        script = self.root / "tools/run_tests.py"
        shutil.copy2(ROOT / "tools/run_tests.py", script)
        (self.root / "tests/test_a.lua").write_text(
            "print('lua print marker'); io.write('native stdout marker\\n'); io.stderr:write('native stderr marker\\n')",
            encoding="utf-8")
        command = [sys.executable, str(script), "tests/test_a.lua"]
        quiet = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(quiet.returncode, 0, quiet.stderr)
        self.assertEqual(len(quiet.stdout.splitlines()), 1)
        self.assertEqual(quiet.stderr, "")
        log_path = Path(quiet.stdout.strip().split("log=", 1)[1])
        logged = log_path.read_text(encoding="utf-8")
        for marker in ("lua print marker", "native stdout marker", "native stderr marker", "PASS test_a.lua"):
            self.assertNotIn(marker, quiet.stdout)
            self.assertIn(marker, logged)
        verbose = subprocess.run(command + ["--verbose"], capture_output=True, text=True)
        self.assertEqual(verbose.returncode, 0, verbose.stderr)
        for marker in ("lua print marker", "native stdout marker", "native stderr marker", "PASS test_a.lua"):
            self.assertIn(marker, verbose.stdout)
        self.assertNotEqual(quiet.stdout.strip().split("log=", 1)[1],
                            verbose.stdout.strip().split("log=", 1)[1])

    def test_failure_shows_own_context_without_success_noise(self):
        (self.root / "tests/test_a.lua").write_text("print('unrelated success noise')")
        (self.root / "tests/test_b.lua").write_text(
            "io.write('failure context marker\\n'); assert(false, 'important assertion')")
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(run_tests, "ROOT", self.root), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = run_tests.run_tests(run_tests.select_tests([], self.root))
        self.assertEqual(code, 1)
        self.assertNotIn("unrelated success noise", errors.getvalue())
        self.assertIn("failure context marker", errors.getvalue())
        self.assertIn("important assertion", errors.getvalue())
        self.assertIn("tests/test_b.lua", errors.getvalue())
        self.assertIn("Traceback", errors.getvalue())


    def test_long_lua_error_is_bounded_but_raw_log_and_verbose_are_complete(self):
        (self.root / "tools").mkdir()
        script = self.root / "tools/run_tests.py"
        shutil.copy2(ROOT / "tools/run_tests.py", script)
        (self.root / "tests/test_a.lua").write_text(
            "print(string.rep('C', 50000)); error('ERROR_HEAD' .. string.rep('N', 50000) .. 'ERROR_TAIL')",
            encoding="utf-8")
        command = [sys.executable, str(script), "tests/test_a.lua"]
        quiet = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(quiet.returncode, 0)
        self.assertLess(len(quiet.stdout) + len(quiet.stderr), 17000)
        for marker in ("Traceback (most recent call last):", "ERROR_HEAD", "ERROR_TAIL", "stack traceback",
                       "traceback omitted; full log:", "tests/test_a.lua"):
            self.assertIn(marker, quiet.stderr)
        log_path = Path(quiet.stdout.strip().split("log=", 1)[1])
        logged = log_path.read_text(encoding="utf-8")
        self.assertIn("ERROR_HEAD" + "N" * 50000 + "ERROR_TAIL", logged)
        verbose = subprocess.run(command + ["--verbose"], capture_output=True, text=True)
        self.assertNotEqual(verbose.returncode, 0)
        self.assertIn("ERROR_HEAD" + "N" * 50000 + "ERROR_TAIL", verbose.stdout)
        self.assertNotIn("traceback omitted", verbose.stdout)

    def test_worker_uses_utf8_despite_inherited_ascii_environment(self):
        (self.root / "tests/test_a.lua").write_text("error('中文诊断')", encoding="utf-8")
        output, errors = io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {"PYTHONIOENCODING": "ascii", "PYTHONUTF8": "0"}), \
                patch.object(run_tests, "ROOT", self.root), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            code = run_tests.run_tests(run_tests.select_tests(["tests/test_a.lua"], self.root))
        self.assertEqual(code, 1)
        self.assertIn("中文诊断", errors.getvalue())
        self.assertNotIn("UnicodeEncodeError", errors.getvalue())
        log_path = Path(output.getvalue().strip().split("log=", 1)[1])
        self.assertIn("中文诊断", log_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
