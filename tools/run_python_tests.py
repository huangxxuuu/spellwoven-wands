"""Run unittest discovery with one quiet summary and a complete, unique log."""
import argparse
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import traceback
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
QUIET_MAX_CASES = 5
QUIET_MAX_CHARS = 12000


def excerpt(text, *, chars=1600, lines=18, tail_only=False):
    """Bound both long lines and many short lines without losing the end."""
    source_lines = text.splitlines(keepends=True)
    if len(source_lines) > lines:
        omitted = len(source_lines) - lines
        marker = f"\n... [omitted {omitted} lines] ...\n"
        if tail_only:
            text = marker + "".join(source_lines[-lines:])
        else:
            half = lines // 2
            text = "".join(source_lines[:half]) + marker + "".join(source_lines[-(lines - half):])
    if len(text) > chars:
        marker = "\n... [omitted characters] ...\n"
        for _ in range(3):
            marker = f"\n... [omitted {len(text) - chars + len(marker)} characters] ...\n"
        available = chars - len(marker)
        if tail_only:
            text = marker + text[-available:]
        else:
            half = available // 2
            text = text[:half] + marker + text[-(available - half):]
    return text.rstrip()


def quiet_diagnostic(detail):
    header, separator, body = detail.partition("\n")
    if not separator:
        return excerpt(header)
    # Keep traceback/error text separate: a huge captured print must never push
    # the actual assertion or exception out of the displayed excerpt.
    parts = re.split(r"\n(Stdout:|Stderr:|Captured stdout/stderr:)\n", body)
    pieces = [excerpt(header, chars=400, lines=2), excerpt(parts[0])]
    sections = list(zip(parts[1::2], parts[2::2]))
    for label, output in sections[:3]:
        pieces.append(label + "\n" + excerpt(output, chars=500, lines=8, tail_only=True))
    if len(sections) > 3:
        pieces.append(f"... [omitted {len(sections) - 3} output sections] ...")
    return "\n".join(piece for piece in pieces if piece)


def quiet_details(details):
    rendered = []
    used = 0
    for detail in details[:QUIET_MAX_CASES]:
        item = quiet_diagnostic(detail)
        if used + len(item) > QUIET_MAX_CHARS:
            break
        rendered.append(item)
        used += len(item) + 2
    omitted = len(details) - len(rendered)
    if omitted:
        rendered.append(f"... [omitted {omitted} diagnostic cases; complete details in log] ...")
    return "\n\n".join(rendered)


def log_tail(path):
    """Read only a bounded byte tail, even after an unstructured worker crash."""
    with path.open("rb") as source:
        source.seek(0, os.SEEK_END)
        size = source.tell()
        source.seek(max(0, size - 4096))
        tail = source.read(4096).decode("utf-8", errors="replace")
    prefix = f"... [omitted {size - 4096} log bytes] ...\n" if size > 4096 else ""
    return prefix + excerpt(tail, chars=2000, lines=16, tail_only=True)


class CapturingResult(unittest.TextTestResult):
    """Capture inherited file descriptors as well as ordinary Python prints."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.successes = 0
        self.saved_fds = []
        self.capture = None

    def _setupStdout(self):
        # unittest uses this hook for module/class fixtures as well as tests.
        if self.capture is None:
            self.problem_offsets = (len(self.failures), len(self.errors))
            sys.stdout.flush()
            sys.stderr.flush()
            self.capture = tempfile.TemporaryFile()
            self.saved_fds = [os.dup(1), os.dup(2)]
            os.dup2(self.capture.fileno(), 1)
            os.dup2(self.capture.fileno(), 2)
        super()._setupStdout()

    def addSuccess(self, test):
        self.successes += 1
        super().addSuccess(test)

    def _restoreStdout(self):
        # unittest includes buffered Python output in failure tracebacks. Preserve
        # successful and fixture output in the full log as well.
        if self.capture is not None:
            sys.stdout.flush()
            sys.stderr.flush()
            for descriptor, saved in zip((1, 2), self.saved_fds):
                os.dup2(saved, descriptor)
                os.close(saved)
            self.saved_fds = []
            self.capture.seek(0)
            output = self.capture.read().decode("utf-8", errors="replace")
            self.capture.close()
            self.capture = None
            if output:
                self._original_stdout.write(f"\n--- Inherited stdout/stderr ---\n{output}")
                for problems, offset in zip((self.failures, self.errors), self.problem_offsets):
                    for index in range(offset, len(problems)):
                        case, detail = problems[index]
                        problems[index] = (case, detail + "\nCaptured stdout/stderr:\n" + output)
        if self.buffer and self._stdout_buffer is not None:
            for label, buffer in (("stdout", self._stdout_buffer), ("stderr", self._stderr_buffer)):
                output = buffer.getvalue()
                if output:
                    self._original_stdout.write(f"\n--- {label} ---\n{output}")
            self._mirrorOutput = False
        super()._restoreStdout()


def flatten(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from flatten(test)
        else:
            yield test


def worker(args):
    started = time.monotonic()
    stream = io.StringIO()
    try:
        loader = unittest.TestLoader()
        tests = {}
        for pattern in args.patterns or ["test_*.py"]:
            for test in flatten(loader.discover(str(Path(args.start_directory).resolve()), pattern=pattern)):
                tests.setdefault(test.id(), test)
        runner = unittest.TextTestRunner(stream=stream, verbosity=2, buffer=True,
                                         resultclass=CapturingResult)
        result = runner.run(unittest.TestSuite(tests.values()))
        details = []
        for label, cases in (("FAIL", result.failures), ("ERROR", result.errors)):
            for test, detail in cases:
                details.append(f"{label}: {test.id()}\n{detail}")
        for test in result.unexpectedSuccesses:
            details.append(f"UNEXPECTED SUCCESS: {test.id()}")
        if not result.testsRun:
            details.append("ERROR: No tests discovered; check the start directory and patterns.")
        payload = dict(run=result.testsRun, success=result.successes, failures=len(result.failures),
                       errors=len(result.errors), skipped=len(result.skipped),
                       expected_failures=len(result.expectedFailures),
                       unexpected_successes=len(result.unexpectedSuccesses),
                       elapsed=time.monotonic() - started, details="\n\n".join(details),
                       diagnostics=details,
                       ok=result.wasSuccessful() and result.testsRun > 0)
    except BaseException:
        payload = dict(run=0, success=0, failures=0, errors=1, skipped=0,
                       expected_failures=0, unexpected_successes=0,
                       elapsed=time.monotonic() - started, details=traceback.format_exc(), ok=False)
        payload["diagnostics"] = [payload["details"]]
    print(stream.getvalue(), end="")
    if payload["details"]:
        print(payload["details"])
    Path(args.worker_result).write_text(json.dumps(payload), encoding="utf-8")
    return 0 if payload["ok"] else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-s", "--start-directory", default=str(ROOT / "tests"))
    parser.add_argument("-p", "--pattern", dest="patterns", action="append")
    parser.add_argument("--verbose", action="store_true", help="show the complete captured log")
    parser.add_argument("--worker-result", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.worker_result:
        return worker(args)
    reports = ROOT / "test_reports"
    reports.mkdir(exist_ok=True)
    log = reports / ("python_tests_" + time.strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex + ".log")
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="python-test-result-") as temporary:
        result_path = Path(temporary) / "result.json"
        command = [sys.executable, str(Path(__file__).resolve()), "-s", args.start_directory,
                   "--worker-result", str(result_path)]
        for pattern in args.patterns or []:
            command.extend(["-p", pattern])
        env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUNBUFFERED="1")
        with log.open("wb") as output:
            try:
                child = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, env=env)
                returncode = child.returncode
            except OSError:
                output.write(traceback.format_exc().encode("utf-8"))
                returncode = 1
        try:
            result = json.loads(result_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            crash = (f"ERROR: Test worker exited without a result (exit {returncode}).\n"
                     + log_tail(log))
            result = dict(run=0, success=0, failures=0, errors=1, skipped=0,
                          expected_failures=0, unexpected_successes=0,
                          elapsed=time.monotonic() - started, ok=False,
                          details=crash, diagnostics=[crash])
    if returncode and result["ok"]:
        result["ok"] = False
        result["errors"] += 1
        result["details"] += f"\nERROR: Test worker exited with code {returncode}."
        result["diagnostics"].append(f"ERROR: Test worker exited with code {returncode}.")
    if args.verbose:
        print(log.read_text(encoding="utf-8", errors="replace"), end="")
    elif result["details"]:
        print(quiet_details(result["diagnostics"]))
    summary = (f"Python tests: run={result['run']} success={result['success']} "
               f"failures={result['failures']} errors={result['errors']} skipped={result['skipped']} "
               f"expected_failures={result['expected_failures']} "
               f"unexpected_successes={result['unexpected_successes']} "
               f"time={result['elapsed']:.3f}s log={log}")
    print(summary)
    with log.open("a", encoding="utf-8") as output:
        output.write(summary + "\n")
    return 0 if result["ok"] and returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
