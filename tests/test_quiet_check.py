"""Check that quiet validation preserves failures and native/child diagnostics."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class QuietCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "tools").mkdir()
        self.wrapper = self.root / "tools/quiet_check.py"
        shutil.copy2(ROOT / "tools/quiet_check.py", self.wrapper)
        self.check = self.root / "tools/check_fixture.py"

    def run_check(self, source, *options):
        self.check.write_text(source, encoding="utf-8")
        return subprocess.run([sys.executable, str(self.wrapper), *options, "tools/check_fixture.py"],
                              cwd=self.root.parent, capture_output=True, text=True, encoding="utf-8")

    def test_success_keeps_python_native_and_child_output_in_unique_logs(self):
        source = "import os, subprocess, sys\nprint('normal setup')\nos.write(2,b'native detail\\n')\nsubprocess.run([sys.executable,'-c',\"print('child detail')\"],check=True)\n"
        for _ in range(2):
            result = self.run_check(source)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            self.assertEqual(len(result.stdout.splitlines()), 1)
            self.assertNotIn("normal setup", result.stdout)
            self.assertNotIn("native detail", result.stdout)
            self.assertNotIn("child detail", result.stdout)
        logs = list((self.root / "test_reports").glob("quiet-check-*.log"))
        self.assertEqual(len(logs), 2)
        for log in logs:
            content = log.read_text("utf-8")
            for message in ("normal setup", "native detail", "child detail"):
                self.assertIn(message, content)

    def test_exception_is_visible_without_successful_setup_and_exit_is_preserved(self):
        result = self.run_check("print('normal setup',flush=True)\nraise RuntimeError('diagnostic failure')\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("diagnostic failure", result.stderr)
        self.assertIn("Traceback", result.stderr)
        self.assertNotIn("normal setup", result.stderr)
        self.assertIn("FAIL:", result.stdout)
        result = self.run_check("import sys\nprint('specific diagnostic')\nsys.exit(7)\n")
        self.assertEqual(result.returncode, 7)
        self.assertIn("specific diagnostic", result.stderr)

    def test_failure_excerpt_is_bounded_but_complete_log_remains(self):
        result = self.run_check("import sys\nfor i in range(300): print('detail',i)\nsys.exit(2)\n")
        self.assertEqual(result.returncode, 2)
        self.assertLessEqual(len(result.stderr.splitlines()), 62)
        self.assertIn("detail 299", result.stderr)
        log = next((self.root / "test_reports").glob("quiet-check-*.log"))
        self.assertEqual(len(log.read_text("utf-8").splitlines()), 300)

    def test_verbose_and_missing_script(self):
        result = self.run_check("print('requested detail')\n", "--verbose")
        self.assertEqual(result.returncode, 0)
        self.assertIn("requested detail", result.stdout)
        missing = subprocess.run([sys.executable, str(self.wrapper), "../outside.py"],
                                 capture_output=True, text=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("inside the repository", missing.stderr)


if __name__ == "__main__":
    unittest.main()
