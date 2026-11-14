"""Run a noninteractive Python check, keeping successful output in a local log."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
TAIL_BYTES = 16000
TAIL_LINES = 60


def failure_excerpt(path):
    """Unknown scripts have no structured result: show bounded diagnostic context."""
    size = path.stat().st_size
    with path.open("rb") as stream:
        stream.seek(max(0, size - TAIL_BYTES))
        data = stream.read()
    lines = data.decode("utf-8", errors="replace").splitlines()
    # Prefer the final exception over successful setup messages preceding it.
    tracebacks = [i for i, line in enumerate(lines)
                  if line.startswith("Traceback (most recent call last):")]
    if tracebacks:
        lines = lines[tracebacks[-1]:]
    omitted = size > TAIL_BYTES or len(lines) > TAIL_LINES
    excerpt = "\n".join(lines[-TAIL_LINES:]) or "(check exited without diagnostic output)"
    if omitted:
        excerpt = "[bounded failure excerpt; full output is in the log]\n" + excerpt
    return excerpt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="show full output after the check finishes")
    parser.add_argument("script", help="repository-relative Python check script")
    parser.add_argument("script_args", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    script = (ROOT / args.script).resolve()
    if not script.is_relative_to(ROOT) or not script.is_file() or script.suffix != ".py":
        parser.error("script must be a Python file inside the repository")
    report_dir = ROOT / "test_reports"
    report_dir.mkdir(exist_ok=True)
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    start = time.perf_counter()
    with tempfile.NamedTemporaryFile(prefix="quiet-check-", suffix=".log", dir=report_dir,
                                     mode="wb", delete=False) as output:
        log = Path(output.name)
        try:
            result = subprocess.run([sys.executable, str(script), *args.script_args], cwd=ROOT,
                                    stdout=output, stderr=subprocess.STDOUT, env=env)
            code = result.returncode
        except OSError as exc:
            output.write((f"Unable to start check: {exc}\n").encode("utf-8"))
            code = 1
    if args.verbose:
        # Stream the saved log instead of loading an unbounded file into memory.
        with log.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                print(line, end="")
    elif code:
        print(f"FAIL {script.relative_to(ROOT).as_posix()}\n{failure_excerpt(log)}", file=sys.stderr)
    elapsed = time.perf_counter() - start
    status = "PASS" if code == 0 else "FAIL"
    print(f"{status}: {script.name}; exit={code}; {elapsed:.2f}s; "
          f"log={log.relative_to(ROOT).as_posix()}", flush=True)
    return code if 0 <= code <= 255 else 1


if __name__ == "__main__":
    raise SystemExit(main())
