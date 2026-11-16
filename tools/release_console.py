"""Quiet, process-isolated console for the complete release workflow."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import traceback


_stage = 'startup'
_RESULT_OPTION = '--_console-result'
_WINDOWS = os.name == 'nt'


def set_stage(label):
    """Record progress without producing console output."""
    global _stage
    _stage = str(label)


def _single_line(value, limit=700):
    value = ' '.join(str(value).split())
    if len(value) <= limit:
        return value
    head = (limit - 3) // 2
    return value[:head] + ' … ' + value[-(limit - 3 - head):]


def _configure_utf8():
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, 'reconfigure', None)
        if reconfigure is not None:
            try:
                reconfigure(encoding='utf-8', errors='backslashreplace')
            except (OSError, ValueError):
                pass


def _print_summary(message):
    try:
        print(message, flush=True)
    except UnicodeEncodeError:
        # Some embedded hosts expose a fixed-encoding wrapper with no reconfigure.
        raw = getattr(sys.stdout, 'buffer', None)
        if raw is None:
            raise
        raw.write((message + '\n').encode('utf-8', errors='backslashreplace'))
        raw.flush()


def _stop_tree(process):
    """Stop descendants and reap the worker; return any unconfirmed cleanup."""
    problem = ''
    pid = getattr(process, 'pid', None)
    try:
        if pid and _WINDOWS:
            stopped = subprocess.run(
                ['taskkill', '/PID', str(pid), '/T', '/F'],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0x08000000), timeout=20)
            if stopped.returncode:
                problem = f'Process tree cleanup failed (taskkill exit {stopped.returncode}); descendants may remain.'
        elif pid:
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        else:
            # Test doubles and embedded process adapters may not expose a PID.
            process.terminate()
    except (OSError, subprocess.SubprocessError) as error:
        problem = f'Process tree cleanup failed: {error}; descendants may remain.'
    try:
        if problem and process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)
    except (OSError, subprocess.SubprocessError) as error:
        problem += f' Worker exit could not be confirmed: {error}.'
    return problem


def _extract_result(argv):
    clean = []
    result = None
    index = 0
    while index < len(argv):
        item = argv[index]
        if item == _RESULT_OPTION or item.startswith(_RESULT_OPTION + '='):
            if result is not None:
                raise ValueError('Duplicate internal console result argument.')
            if item == _RESULT_OPTION:
                index += 1
                if index == len(argv):
                    raise ValueError('Missing internal console result path.')
                value = argv[index]
            else:
                value = item.split('=', 1)[1]
            result = Path(value)
            if not result.is_absolute():
                raise ValueError('Internal console result path must be absolute.')
        else:
            clean.append(item)
        index += 1
    return clean, result


def _all_mode(argv):
    return any(item == '--mode=all' or
               (item == '--mode' and index + 1 < len(argv) and argv[index + 1] == 'all')
               for index, item in enumerate(argv))


def _tail_reason(path):
    try:
        with path.open('rb') as source:
            source.seek(0, os.SEEK_END)
            source.seek(max(0, source.tell() - 4096))
            lines = source.read().decode('utf-8', errors='replace').splitlines()
        return next((line.strip() for line in reversed(lines) if line.strip()), '')
    except OSError:
        return ''


def _worker(main, argv, result_path):
    set_stage('arguments')
    try:
        value = main(argv)
        if not isinstance(value, dict) or not value.get('version') or value.get('mode') != 'all':
            raise ValueError('Release workflow returned no valid completion result.')
        result = dict(success=True, code=0, stage=_stage, reason='Release completed.', details=value)
    except BaseException as error:
        if isinstance(error, KeyboardInterrupt):
            code, reason = 130, 'Interrupted. Completed stages are retained for --resume.'
        elif isinstance(error, SystemExit):
            code = error.code if isinstance(error.code, int) and error.code else 1
            sys.stdout.flush()
            sys.stderr.flush()
            reason = (str(error.code) if isinstance(error.code, str) else
                      _tail_reason(result_path.parent / 'output.log')) or f'Exited with code {code}.'
        else:
            code, reason = 1, str(error) or type(error).__name__
        traceback.print_exc()
        result = dict(success=False, code=code, stage=_stage,
                      reason=_single_line(reason), details=dict(exception=type(error).__name__))
    temporary = result_path.with_suffix('.tmp')
    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(result_path)
    return result['code']


def _legacy(main, argv):
    """Preserve the release script's established non-all CLI behavior."""
    release_error = getattr(main, '__globals__', {}).get('ReleaseError')
    caught = (OSError, ValueError, KeyError)
    if isinstance(release_error, type) and issubclass(release_error, Exception):
        caught += (release_error,)
    try:
        main(argv)
        return 0
    except caught as error:
        print(f'RELEASE STOPPED: {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('Interrupted. Completed stages are retained for --resume.', file=sys.stderr)
        return 130


def entrypoint(main, root, argv=None):
    """Return a CLI exit code; only --mode all runs in a quiet worker."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    quiet = _all_mode(arguments)
    if quiet and '--help' not in arguments and '-h' not in arguments:
        _configure_utf8()
    try:
        clean, result_path = _extract_result(arguments)
    except ValueError as error:
        if not quiet:
            raise
        _print_summary(f'FAILED [arguments]: {_single_line(error)}; log: unavailable')
        return 2
    if result_path is not None:
        return _worker(main, clean, result_path)
    if not quiet or '--help' in clean or '-h' in clean:
        return _legacy(main, clean)

    process = None
    log_path = None
    stage = 'startup'
    code = 1
    reason = ''
    interrupted = False
    try:
        report_root = Path(root).resolve() / 'test_reports'
        report_root.mkdir(parents=True, exist_ok=True)
        report = Path(tempfile.mkdtemp(prefix='release-', dir=report_root))
        result_path = report / 'result.json'
        log_path = report / 'output.log'
        env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8',
                   GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never', GH_PROMPT_DISABLED='1')
        with log_path.open('wb') as output:
            process_options = (dict(creationflags=getattr(subprocess, 'CREATE_NEW_PROCESS_GROUP', 0x200) |
                                    getattr(subprocess, 'CREATE_NO_WINDOW', 0x08000000))
                               if _WINDOWS else dict(start_new_session=True))
            process = subprocess.Popen(
                [sys.executable, str(Path(sys.argv[0]).resolve()), *clean,
                 _RESULT_OPTION, str(result_path)], cwd=str(Path(root).resolve()),
                env=env, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                **process_options)
            process.wait()
        stage = 'worker'
        if not result_path.is_file():
            reason = f'Worker exited with code {process.returncode} without a completion result.'
            last_output = _tail_reason(log_path)
            if last_output:
                reason += ' Last output: ' + last_output
        else:
            result = json.loads(result_path.read_text(encoding='utf-8'))
            if not isinstance(result, dict):
                raise ValueError('Invalid worker completion result.')
            stage = result.get('stage') or stage
            if result.get('success') is True and result.get('code') == 0 and process.returncode == 0:
                details = result.get('details')
                if not isinstance(details, dict) or not details.get('version') or details.get('mode') != 'all':
                    raise ValueError('Invalid worker success details.')
                _print_summary(f'SUCCESS: {_single_line(details["version"])}; log: {log_path}')
                return 0
            code = process.returncode or result.get('code') or 1
            reason = result.get('reason') or f'Worker exited with code {code}.'
            if result.get('success') is True:
                reason = f'Worker exited with code {code} after writing a success result.'
    except KeyboardInterrupt:
        interrupted = True
        code, reason = 130, 'Interrupted. Completed stages are retained for --resume.'
    except Exception as error:
        reason = str(error) or type(error).__name__
        if log_path is not None:
            try:
                with log_path.open('a', encoding='utf-8') as output:
                    traceback.print_exc(file=output)
            except OSError:
                pass
    finally:
        if process is not None and (interrupted or process.poll() is None):
            cleanup_problem = _stop_tree(process)
            if cleanup_problem:
                reason += ' ' + cleanup_problem
    _print_summary(f'FAILED [{_single_line(stage, 80)}]: {_single_line(reason)}; log: {log_path or "unavailable"}')
    return code if isinstance(code, int) and code else 1
