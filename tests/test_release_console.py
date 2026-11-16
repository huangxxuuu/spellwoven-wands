"""Isolated console tests; every worker is a fake temporary release script."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / 'tools/release_console.py'
SPEC = importlib.util.spec_from_file_location('release_console', SOURCE)
console = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(console)


class ReleaseConsoleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copyfile(SOURCE, self.root / 'release_console.py')
        self.entry = self.root / 'release.py'

    def script(self, body):
        self.entry.write_text(
            'import argparse, json, os, subprocess, sys\n'
            'from pathlib import Path\n'
            'from release_console import entrypoint, set_stage\n'
            'def main(argv=None):\n' + textwrap.indent(textwrap.dedent(body), '    ') +
            '\nif __name__ == "__main__":\n'
            '    sys.exit(entrypoint(main, Path(__file__).parent))\n', encoding='utf-8')

    def run_script(self, *argv):
        return subprocess.run([sys.executable, str(self.entry), *argv],
                              capture_output=True, text=True, encoding='utf-8',
                              env=dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8'),
                              timeout=30)

    def report(self):
        reports = list((self.root / 'test_reports').glob('release-*'))
        self.assertEqual(len(reports), 1)
        directory = reports[0]
        return (json.loads((directory / 'result.json').read_text(encoding='utf-8')),
                (directory / 'output.log').read_text(encoding='utf-8'))

    def assert_summary(self, completed, prefix, code):
        self.assertEqual(completed.returncode, code, completed.stdout + completed.stderr)
        self.assertEqual(completed.stderr, '')
        self.assertEqual(len(completed.stdout.splitlines()), 1, completed.stdout)
        self.assertTrue(completed.stdout.startswith(prefix), completed.stdout)
        self.assertIn('log:', completed.stdout)

    def test_all_captures_python_native_and_inherited_child_output(self):
        self.script('''
            assert '--_console-result' not in argv
            print('python-output-中文', flush=True)
            print('python-error', file=sys.stderr, flush=True)
            os.write(1, b'native-out\\n')
            os.write(2, b'native-error\\n')
            subprocess.run([sys.executable, '-c', "print('child-output')"], check=True)
            assert sys.stdin.read() == ''
            for name, value in {'PYTHONUTF8': '1', 'PYTHONIOENCODING': 'utf-8',
                                'GIT_TERMINAL_PROMPT': '0', 'GCM_INTERACTIVE': 'Never',
                                'GH_PROMPT_DISABLED': '1'}.items():
                assert os.environ[name] == value
            set_stage('publish')
            return {'version': '1.2.3', 'mode': 'all', 'resume': False}
        ''')
        completed = self.run_script('--mode', 'all')
        self.assert_summary(completed, 'SUCCESS:', 0)
        result, log = self.report()
        self.assertTrue(result['success'])
        self.assertEqual(result['stage'], 'publish')
        for marker in ('python-output-中文', 'python-error', 'native-out', 'native-error', 'child-output'):
            self.assertIn(marker, log)
            self.assertNotIn(marker, completed.stdout)

    def test_equals_mode_and_failure_preserve_stage_and_bounded_tail_reason(self):
        self.script('''
            set_stage('Steam upload')
            raise RuntimeError('git push failed: ' + 'noise ' * 1000 + '\\n最终失败原因 🧵')
        ''')
        completed = self.run_script('--mode=all')
        self.assert_summary(completed, 'FAILED [Steam upload]:', 1)
        self.assertIn('git push failed:', completed.stdout)
        self.assertIn('最终失败原因', completed.stdout)
        self.assertLess(len(completed.stdout), 1000)
        result, log = self.report()
        self.assertFalse(result['success'])
        self.assertIn('Traceback', log)
        self.assertIn('noise ' * 1000, log)

    def test_argparse_error_is_one_failure_line_with_specific_reason(self):
        self.script('''
            parser = argparse.ArgumentParser()
            parser.add_argument('--mode', choices=['all'])
            parser.parse_args(argv)
            return {'version': '1.2.3', 'mode': 'all'}
        ''')
        completed = self.run_script('--mode', 'all', '--unknown')
        self.assert_summary(completed, 'FAILED [arguments]:', 2)
        self.assertIn('unrecognized arguments: --unknown', completed.stdout)
        result, log = self.report()
        self.assertEqual(result['details']['exception'], 'SystemExit')
        self.assertIn('usage:', log)

    def test_crash_without_result_is_never_success_even_with_zero_exit(self):
        for code in (0, 7):
            with self.subTest(code=code):
                self.script(f'os._exit({code})\n')
                completed = self.run_script('--mode=all')
                self.assert_summary(completed, 'FAILED [worker]:', 1)
                self.assertIn('without a completion result', completed.stdout)
        self.assertEqual(len(list((self.root / 'test_reports').glob('release-*'))), 2)

    def test_success_result_with_nonzero_process_exit_is_failure(self):
        self.script('''
            import atexit
            atexit.register(lambda: os._exit(9))
            return {'version': '1.2.3', 'mode': 'all'}
        ''')
        completed = self.run_script('--mode=all')
        self.assert_summary(completed, 'FAILED [arguments]:', 9)
        self.assertIn('after writing a success result', completed.stdout)

    def test_missing_success_return_is_failure(self):
        self.script("print('no completion data')\n")
        completed = self.run_script('--mode=all')
        self.assert_summary(completed, 'FAILED [arguments]:', 1)
        self.assertIn('no valid completion result', completed.stdout)

    def test_worker_keyboard_interrupt_has_result_and_one_summary(self):
        self.script("set_stage('prepare')\nraise KeyboardInterrupt()\n")
        completed = self.run_script('--mode=all')
        self.assert_summary(completed, 'FAILED [prepare]:', 130)
        self.assertEqual(self.report()[0]['code'], 130)

    def test_legacy_and_help_keep_direct_output(self):
        self.script('''
            print('direct output')
            print('direct error', file=sys.stderr)
        ''')
        for arguments in ([], ['--mode', 'plan'], ['--mode=all', '--help']):
            with self.subTest(arguments=arguments):
                completed = self.run_script(*arguments)
                self.assertEqual(completed.returncode, 0)
                self.assertEqual(completed.stdout, 'direct output\n')
                self.assertEqual(completed.stderr, 'direct error\n')
        self.assertFalse((self.root / 'test_reports').exists())

    def test_legacy_known_failure_uses_existing_format(self):
        self.script("raise ValueError('bad configuration')\n")
        completed = self.run_script('--mode', 'prepare')
        self.assertEqual(completed.returncode, 1)
        self.assertEqual(completed.stdout, '')
        self.assertEqual(completed.stderr, 'RELEASE STOPPED: bad configuration\n')

    def test_set_stage_is_silent_and_main_remains_direct_callable(self):
        output = io.StringIO()
        with redirect_stdout(output), redirect_stderr(output):
            console.set_stage('test')
        self.assertEqual(output.getvalue(), '')
        called = []
        self.assertEqual(console.entrypoint(lambda argv: called.append(argv), self.root, ['--mode=plan']), 0)
        self.assertEqual(called, [['--mode=plan']])

    def test_start_failure_is_single_line_and_logged(self):
        output = io.StringIO()
        with patch.object(console.subprocess, 'Popen', side_effect=OSError('cannot start')), redirect_stdout(output):
            code = console.entrypoint(lambda argv: None, self.root, ['--mode=all'])
        self.assertEqual(code, 1)
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        self.assertIn('FAILED [startup]: cannot start', output.getvalue())
        log = next((self.root / 'test_reports').glob('release-*/output.log'))
        self.assertIn('cannot start', log.read_text(encoding='utf-8'))

    def test_bad_internal_argument_is_single_line(self):
        output = io.StringIO()
        with redirect_stdout(output):
            code = console.entrypoint(lambda argv: None, self.root,
                                      ['--mode=all', '--_console-result', 'relative.json'])
        self.assertEqual(code, 2)
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        self.assertIn('must be absolute', output.getvalue())

    def test_parent_interruption_waits_for_worker_exit_before_summary(self):
        events = []

        class Worker:
            def __init__(self, *args, **kwargs):
                self.returncode = None

            def wait(self, timeout=None):
                if timeout is None:
                    raise KeyboardInterrupt()
                events.append('waited')
                self.returncode = -15
                return self.returncode

            def poll(self):
                return self.returncode

            def terminate(self):
                events.append('terminated')

        class Output(io.StringIO):
            def write(self, text):
                if text.startswith('FAILED'):
                    events.append('summary')
                return super().write(text)

        output = Output()
        with patch.object(console.subprocess, 'Popen', Worker), redirect_stdout(output):
            code = console.entrypoint(lambda argv: None, self.root, ['--mode=all'])
        self.assertEqual(code, 130)
        self.assertEqual(events, ['terminated', 'waited', 'summary'])

    def test_windows_interruption_kills_tree_and_reaps_worker_before_summary(self):
        events = []

        class Worker:
            pid = 12345
            returncode = None

            def __init__(self, *args, **kwargs):
                self.options = kwargs

            def wait(self, timeout=None):
                if timeout is None:
                    raise KeyboardInterrupt()
                events.append('reaped')
                self.returncode = -15

            def poll(self):
                return self.returncode

            def terminate(self):
                events.append('fallback-worker-only')

        def taskkill(command, **options):
            self.assertEqual(command, ['taskkill', '/PID', '12345', '/T', '/F'])
            self.assertIs(options['stdout'], subprocess.DEVNULL)
            self.assertIs(options['stderr'], subprocess.DEVNULL)
            self.assertTrue(options['creationflags'])
            events.append('tree-stopped')
            return subprocess.CompletedProcess(command, 0)

        output = io.StringIO()
        with patch.object(console, '_WINDOWS', True), \
             patch.object(console.subprocess, 'Popen', Worker), \
             patch.object(console.subprocess, 'run', side_effect=taskkill), redirect_stdout(output):
            code = console.entrypoint(lambda argv: None, self.root, ['--mode=all'])
        self.assertEqual(code, 130)
        self.assertEqual(events, ['tree-stopped', 'reaped'])
        self.assertEqual(len(output.getvalue().splitlines()), 1)
        self.assertNotIn('cleanup failed', output.getvalue())

    def test_tree_cleanup_failure_is_reported_even_when_worker_terminates(self):
        events = []

        class Worker:
            pid = 12345
            returncode = None

            def __init__(self, *args, **kwargs):
                pass

            def wait(self, timeout=None):
                if timeout is None:
                    raise KeyboardInterrupt()
                events.append('worker-reaped')
                self.returncode = -15

            def poll(self):
                return self.returncode

            def terminate(self):
                events.append('worker-terminated')

        output = io.StringIO()
        with patch.object(console, '_WINDOWS', True), \
             patch.object(console.subprocess, 'Popen', Worker), \
             patch.object(console.subprocess, 'run', return_value=subprocess.CompletedProcess([], 5)), \
             redirect_stdout(output):
            code = console.entrypoint(lambda argv: None, self.root, ['--mode=all'])
        self.assertEqual(code, 130)
        self.assertEqual(events, ['worker-terminated', 'worker-reaped'])
        self.assertIn('Process tree cleanup failed (taskkill exit 5)', output.getvalue())
        self.assertIn('descendants may remain', output.getvalue())
        self.assertNotIn('SUCCESS', output.getvalue())

    def test_posix_cleanup_signals_worker_process_group(self):
        class Worker:
            pid = 54321

            def wait(self, timeout=None):
                self.waited = timeout

        worker = Worker()
        with patch.object(console, '_WINDOWS', False), \
             patch.object(console.os, 'killpg', create=True) as kill_group, \
             patch.object(console.signal, 'SIGKILL', 9, create=True):
            self.assertEqual(console._stop_tree(worker), '')
        kill_group.assert_called_once_with(54321, 9)
        self.assertEqual(worker.waited, 10)

    def test_all_parent_reconfigures_ascii_console_for_chinese_and_emoji(self):
        self.script("raise RuntimeError('发布失败 🧵')\n")
        completed = subprocess.run(
            [sys.executable, str(self.entry), '--mode=all'], capture_output=True,
            encoding='utf-8', timeout=30,
            env=dict(os.environ, PYTHONUTF8='0', PYTHONIOENCODING='ascii:strict'))
        self.assert_summary(completed, 'FAILED [arguments]:', 1)
        self.assertIn('发布失败 🧵', completed.stdout)

    def test_legacy_does_not_reconfigure_console_encoding(self):
        output = io.StringIO()
        with patch.object(console, '_configure_utf8') as configure, redirect_stdout(output):
            self.assertEqual(console.entrypoint(lambda argv: None, self.root, ['--mode=plan']), 0)
            self.assertEqual(console.entrypoint(lambda argv: None, self.root, ['--mode=all', '--help']), 0)
        configure.assert_not_called()


if __name__ == '__main__':
    unittest.main()
