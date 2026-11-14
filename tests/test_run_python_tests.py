"""CLI regression fixtures exercise real discovery, subprocesses and exit codes."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools/run_python_tests.py"


class PythonTestRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def fixture(self, source, name="test_fixture.py"):
        (self.directory / name).write_text(textwrap.dedent(source), encoding="utf-8")

    def run_fixture(self, *args):
        completed = subprocess.run(
            [sys.executable, str(RUNNER), "-s", str(self.directory), *args],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            env=dict(os.environ, PYTHONIOENCODING="utf-8"),
        )
        self.assertEqual(completed.stderr, "")
        match = re.search(r"log=(.+)$", completed.stdout)
        self.assertIsNotNone(match, completed.stdout)
        log = Path(match.group(1)).read_text(encoding="utf-8")
        return completed, log

    def test_success_is_one_line_and_all_output_is_logged(self):
        self.fixture('''
            import ctypes, os, subprocess, sys, unittest
            print("IMPORT_OUTPUT")
            class Sample(unittest.TestCase):
                @classmethod
                def setUpClass(cls):
                    print("CLASS_OUTPUT")
                def test_pass(self):
                    print("PYTHON_OUTPUT")
                    print("STDERR_OUTPUT", file=sys.stderr)
                    os.write(1, b"FD_OUTPUT\\n")
                    native = ctypes.CDLL("ucrtbase" if os.name == "nt" else None)
                    native.puts(b"NATIVE_C_OUTPUT")
                    native.fflush(None)
                    subprocess.run([sys.executable, "-c", "print('CHILD_OUTPUT')"], check=True)
        ''')
        result, log = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(len(result.stdout.splitlines()), 1)
        self.assertIn("run=1 success=1 failures=0 errors=0", result.stdout)
        for marker in ("IMPORT_OUTPUT", "CLASS_OUTPUT", "PYTHON_OUTPUT", "STDERR_OUTPUT", "FD_OUTPUT", "NATIVE_C_OUTPUT", "CHILD_OUTPUT"):
            self.assertNotIn(marker, result.stdout)
            self.assertIn(marker, log)

    def test_failure_details_include_python_and_inherited_output(self):
        self.fixture('''
            import os, subprocess, sys, unittest
            class Sample(unittest.TestCase):
                def test_failure(self):
                    print("FAIL_STDOUT")
                    print("FAIL_STDERR", file=sys.stderr)
                    os.write(2, b"FAIL_FD\\n")
                    subprocess.run([sys.executable, "-c", "print('FAIL_CHILD')"], check=True)
                    self.fail("failure marker")
                def test_pass(self):
                    print("SUCCESS_HIDDEN")
        ''')
        result, log = self.run_fixture()
        self.assertNotEqual(result.returncode, 0)
        for marker in ("FAIL_STDOUT", "FAIL_STDERR", "FAIL_FD", "FAIL_CHILD", "Traceback", "failure marker"):
            self.assertIn(marker, result.stdout)
        self.assertNotIn("SUCCESS_HIDDEN", result.stdout)
        self.assertIn("SUCCESS_HIDDEN", log)
        self.assertIn("run=2 success=1 failures=1 errors=0", result.stdout)

    def test_verbose_shows_passing_output(self):
        self.fixture('''
            import unittest
            class Sample(unittest.TestCase):
                def test_pass(self):
                    print("VERBOSE_MARKER")
        ''')
        result, _ = self.run_fixture("--verbose")
        self.assertEqual(result.returncode, 0)
        self.assertIn("VERBOSE_MARKER", result.stdout)
        self.assertIn("test_pass (", result.stdout)

    def test_empty_discovery_fails(self):
        result, _ = self.run_fixture("-p", "missing_*.py")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No tests discovered", result.stdout)
        self.assertIn("run=0 success=0", result.stdout)

    def test_skip_expected_failure_and_unexpected_success_are_counted(self):
        self.fixture('''
            import unittest
            class Sample(unittest.TestCase):
                @unittest.skip("skip fixture")
                def test_skip(self): pass
                @unittest.expectedFailure
                def test_expected(self): self.fail("expected")
                @unittest.expectedFailure
                def test_unexpected(self): pass
        ''')
        result, _ = self.run_fixture()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("run=3 success=0 failures=0 errors=0 skipped=1", result.stdout)
        self.assertIn("expected_failures=1 unexpected_successes=1", result.stdout)
        self.assertIn("UNEXPECTED SUCCESS:", result.stdout)

    def test_skip_and_expected_failure_alone_succeed(self):
        self.fixture('''
            import unittest
            class Sample(unittest.TestCase):
                @unittest.skip("skip fixture")
                def test_skip(self): pass
                @unittest.expectedFailure
                def test_expected(self): self.fail("expected")
        ''')
        result, log = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("skipped=1 expected_failures=1", result.stdout)
        self.assertIn("skip fixture", log)

    def test_overlapping_patterns_only_run_each_case_once(self):
        self.fixture('''
            import unittest
            class Sample(unittest.TestCase):
                def test_pass(self): pass
        ''')
        result, _ = self.run_fixture("-p", "test_*.py", "-p", "test_fixture.py", "-p", "test_fixture.py")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("run=1 success=1", result.stdout)

    def test_import_and_class_setup_errors_keep_tracebacks(self):
        self.fixture('''
            import os, unittest
            class Sample(unittest.TestCase):
                @classmethod
                def setUpClass(cls):
                    print("SETUP_FAILURE_OUTPUT")
                    os.write(2, b"SETUP_FD_OUTPUT\\n")
                    raise RuntimeError("setup marker")
                def test_pass(self): pass
        ''')
        self.fixture('raise RuntimeError("import marker")', "test_import.py")
        result, _ = self.run_fixture()
        self.assertNotEqual(result.returncode, 0)
        for marker in ("SETUP_FAILURE_OUTPUT", "SETUP_FD_OUTPUT", "setup marker", "import marker", "Traceback"):
            self.assertIn(marker, result.stdout)
        self.assertIn("errors=2", result.stdout)

    def test_abrupt_worker_exit_shows_diagnostics_and_fails(self):
        self.fixture('''
            import os
            print("ABRUPT_EXIT_OUTPUT", flush=True)
            os._exit(7)
        ''')
        result, log = self.run_fixture()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exit 7", result.stdout)
        self.assertIn("ABRUPT_EXIT_OUTPUT", result.stdout)
        self.assertIn("ABRUPT_EXIT_OUTPUT", log)

    def test_long_failure_output_is_bounded_without_losing_the_error(self):
        self.fixture('''
            import sys, unittest
            class Sample(unittest.TestCase):
                def test_failure(self):
                    print("FULL_OUTPUT_START" + "X" * 50000 + "OUTPUT_TAIL")
                    print("stderr line\\n" * 1000 + "STDERR_TAIL", file=sys.stderr)
                    self.fail("ACTUAL_ERROR_HEAD" + "E" * 50000 + "ACTUAL_ERROR_TAIL")
        ''')
        result, log = self.run_fixture()
        self.assertNotEqual(result.returncode, 0)
        self.assertLess(len(result.stdout), 5000)
        self.assertLess(len(result.stdout.splitlines()), 70)
        for marker in ("test_fixture.Sample.test_failure", "Traceback", "ACTUAL_ERROR_TAIL",
                       "OUTPUT_TAIL", "STDERR_TAIL", "omitted"):
            self.assertIn(marker, result.stdout)
        self.assertIn("FULL_OUTPUT_START" + "X" * 50000 + "OUTPUT_TAIL", log)
        self.assertIn("ACTUAL_ERROR_HEAD" + "E" * 50000 + "ACTUAL_ERROR_TAIL", log)
        verbose, _ = self.run_fixture("--verbose")
        self.assertNotEqual(verbose.returncode, 0)
        self.assertIn("FULL_OUTPUT_START" + "X" * 50000 + "OUTPUT_TAIL", verbose.stdout)

    def test_abrupt_exit_after_large_output_uses_bounded_log_tail(self):
        self.fixture('''
            import os
            print("CRASH_FULL_START" + "Z" * 50000 + "CRASH_OUTPUT_TAIL", flush=True)
            os._exit(7)
        ''')
        result, log = self.run_fixture()
        self.assertNotEqual(result.returncode, 0)
        self.assertLess(len(result.stdout), 3500)
        self.assertIn("exit 7", result.stdout)
        self.assertIn("CRASH_OUTPUT_TAIL", result.stdout)
        self.assertIn("omitted", result.stdout)
        self.assertIn("CRASH_FULL_START" + "Z" * 50000 + "CRASH_OUTPUT_TAIL", log)

    def test_many_failures_have_a_run_limit_and_an_omitted_case_count(self):
        self.fixture('''
            import os, sys, unittest
            class Sample(unittest.TestCase): pass
            def failure(self):
                print("detail line\\n" * 120)
                print("stderr line\\n" * 120, file=sys.stderr)
                os.write(1, b"native detail " * 250)
                self.fail("CASE_ERROR_MARKER" + "E" * 3000 + "CASE_ERROR_TAIL")
            for index in range(80):
                setattr(Sample, "test_failure_%03d" % index, failure)
        ''')
        result, log = self.run_fixture()
        self.assertNotEqual(result.returncode, 0)
        self.assertLess(len(result.stdout), 13000)
        self.assertLess(len(result.stdout.splitlines()), 180)
        displayed = len(re.findall(r"^FAIL: ", result.stdout, re.MULTILINE))
        self.assertGreater(displayed, 0)
        self.assertLess(displayed, 5)  # The total character budget is reached first.
        self.assertIn(f"omitted {80 - displayed} diagnostic cases", result.stdout)
        self.assertIn("CASE_ERROR_TAIL", result.stdout)
        self.assertIn("run=80 success=0 failures=80", result.stdout)
        self.assertIn("test_failure_079", log)
        self.assertNotIn("test_failure_079", result.stdout)


if __name__ == "__main__":
    unittest.main()
