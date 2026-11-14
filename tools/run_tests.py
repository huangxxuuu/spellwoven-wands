"""Execute pure rules with Lua 5.1, not Python reimplementations."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import traceback

ROOT = Path(__file__).resolve().parents[1]


def runtime():
    from lupa.lua51 import LuaRuntime
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = str(ROOT / "mod/scripts/?.lua").replace("\\", "/") + ";" + vm.globals().package.path
    vm.execute("local seq=0; TheWorld={components={nw_identity={Next=function() seq=seq+1; return 'test:'..seq end}}}")
    return vm


def select_tests(names, root=ROOT):
    """Accept exact repository-relative paths, independent of the caller's cwd."""
    tests_root = root.resolve() / "tests"
    available = sorted(path for path in tests_root.glob("test_*.lua")
                       if path.is_file() and not path.is_symlink()
                       and path.resolve().parent == tests_root)
    allowed = set(available)
    selected = []
    for name in names:
        candidate = root.resolve() / name
        path = candidate.resolve()
        if candidate.parent != tests_root or candidate.is_symlink() or path not in allowed:
            raise ValueError(f"Unknown Lua test: {name}; expected tests/test_*.lua")
        if path not in selected:
            selected.append(path)
    result = selected if names else available
    if not result:
        raise ValueError("No Lua tests found (expected tests/test_*.lua)")
    return result


def _execute_tests(paths, result_path):
    """Child process: keep native Lua stdout/stderr inside the parent's log."""
    result = {"syntax": 0, "passed": 0, "failed": 0}
    phase = "Lua 5.1 runtime initialization"
    marker = ""
    try:
        lua = runtime()
        syntax = lua.eval("function(source, name) local fn, err = loadstring(source, name); assert(fn, err); return true end")
        files = sorted((ROOT / "mod").rglob("*.lua"))
        for path in files:
            phase = f"syntax {path.relative_to(ROOT).as_posix()}"
            syntax(path.read_text(encoding="utf-8"), str(path))
            result["syntax"] += 1
        print(f"Lua 5.1 syntax: {len(files)} files OK", flush=True)
        for path in paths:
            phase = path.relative_to(ROOT).as_posix()
            marker = f"--- RUN {phase} ---"
            print(marker, flush=True)
            vm = runtime()
            flush = vm.eval("(function() local out, err = io.stdout, io.stderr; "
                            "local flush, pcall = io.stdout.flush, pcall; "
                            "return function() pcall(flush, out); pcall(flush, err) end end)()")
            try:
                vm.execute(path.read_text(encoding="utf-8"), name=phase)
            finally:
                # Flush Lua's C stdio before the next test marker, including on errors.
                flush()
            result["passed"] += 1
            print(f"PASS {path.name}", flush=True)
    except Exception:
        result.update(failed=1, phase=phase, marker=marker, traceback=traceback.format_exc())
        print(f"FAIL {phase}", flush=True)
        print(result["traceback"], file=sys.stderr, flush=True)
    finally:
        result_path.write_text(json.dumps(result), encoding="utf-8")
    return int(bool(result["failed"]))


def _summarize_traceback(detail, log_path, limit=8000):
    """Keep both the initial call chain and final error/stack within the limit."""
    if len(detail) <= limit:
        return detail
    notice = f"\n... traceback omitted; full log: {log_path} ...\n"
    budget = max(0, limit - len(notice))
    head = budget // 2
    return detail[:head] + notice + detail[-(budget - head):]


def run_tests(paths, verbose=False):
    """Capture in a subprocess so Lua C stdio cannot bypass Python redirection."""
    started = time.perf_counter()
    reports = ROOT / "test_reports"
    reports.mkdir(exist_ok=True)
    # Unique directories also keep concurrent runs from overwriting one another.
    report_dir = Path(tempfile.mkdtemp(prefix="lua-tests-", dir=reports))
    log_path = report_dir / "output.log"
    result_path = report_dir / "result.json"
    command = [sys.executable, str(Path(__file__).resolve()), "--_worker",
               "--_root", str(ROOT), "--_result", str(result_path)]
    command.extend(path.relative_to(ROOT).as_posix() for path in paths)
    child_env = os.environ.copy()
    child_env.update(PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    with log_path.open("wb") as log:
        completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=child_env)
    if result_path.exists():
        result = json.loads(result_path.read_text(encoding="utf-8"))
    else:
        result = {"syntax": 0, "passed": 0, "failed": 1,
                  "phase": "Lua worker", "traceback": f"Worker exited with code {completed.returncode}"}
    failed = bool(completed.returncode or result["failed"])
    if verbose or failed:
        output = log_path.read_text(encoding="utf-8", errors="replace")
    if verbose:
        # Internal phase markers are only for locating failure context in the raw log.
        print("\n".join(line for line in output.splitlines() if not line.startswith("--- RUN ")), flush=True)
    elif failed:
        print(f"FAIL {result.get('phase', 'Lua worker')}", file=sys.stderr)
        context = output.split(result.get("marker") or "\0")[-1]
        # Context and traceback each have a fixed console bound; raw logs stay complete.
        context = context.split("Traceback (most recent call last):")[0]
        lines = context.strip().splitlines()
        if lines:
            print("Failure context (last 40 lines, at most 8000 characters):", file=sys.stderr)
            print("\n".join(lines[-40:])[-8000:], file=sys.stderr)
        detail = result.get("traceback", "Worker failed; see full log.")
        print(_summarize_traceback(detail, log_path), file=sys.stderr)
    sys.stderr.flush()
    print(f"Lua 5.1: syntax={result['syntax']} passed={result['passed']} "
          f"failed={max(result['failed'], int(failed))} elapsed={time.perf_counter() - started:.2f}s "
          f"log={log_path}", flush=True)
    return int(failed)


def main(argv=None):
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", metavar="tests/test_NAME.lua",
                        help="exact repository-relative test paths; default: all Lua tests")
    parser.add_argument("--list", action="store_true", help="list selected tests without executing checks")
    parser.add_argument("--verbose", action="store_true", help="show complete test output (default: summary and failures only)")
    parser.add_argument("--_worker", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--_root", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--_result", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args._root is not None:
        ROOT = args._root.resolve()
    try:
        paths = select_tests(args.tests, ROOT)
    except ValueError as exc:
        parser.error(str(exc))
    if args.list:
        for path in paths:
            print(path.relative_to(ROOT).as_posix())
        return 0
    if args._worker:
        return _execute_tests(paths, args._result)
    return run_tests(paths, verbose=args.verbose)


if __name__ == "__main__":
    raise SystemExit(main())
