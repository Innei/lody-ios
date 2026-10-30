import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


def load(name):
    spec = importlib.util.spec_from_file_location(f'lody_verify_mac_{name}', Path(__file__).parent / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sys.path.insert(0, str(Path(__file__).parent))
status = load('vm_status')
vm = load('vm')

LOG = '''Test Suite 'Selected tests' started at 2026-10-30 21:00:00.000.
Test Case '-[LodyMacUITests.SidebarTests testPinnedSessionsLeadProjectsOrderedByRecency]' started.
    t =     0.01s Start Test at 2026-10-30 21:00:00.100
Test Case '-[LodyMacUITests.SidebarTests testPinnedSessionsLeadProjectsOrderedByRecency]' passed (6.512 seconds).
Test Case '-[LodyMacUITests.SignInTests testDeviceCodeSignInStartsCopiesAndCancels]' started.
Test Case '-[LodyMacUITests.SignInTests testDeviceCodeSignInStartsCopiesAndCancels]' failed (3.100 seconds).
Test Case '-[LodyMacUITests.SignInTests testSignedInStateNamesTheUser]' started.
'''


def dead_pid():
    child = subprocess.Popen(['true'])
    child.wait()
    return child.pid


class ProgressTests(unittest.TestCase):
    def test_streaming_xcodebuild_lines_give_the_current_test_and_counts(self):
        tests = status.parse_tests(LOG)
        self.assertEqual(tests, {'current': 'SignInTests.testSignedInStateNamesTheUser', 'passed': 1, 'failed': 1})
        finished = LOG + ("Test Case '-[LodyMacUITests.SignInTests testSignedInStateNamesTheUser]' passed "
                          "(2.200 seconds).\n")
        self.assertEqual(status.parse_tests(finished), {'current': None, 'passed': 2, 'failed': 1})
        self.assertEqual(status.parse_tests(''), {'current': None, 'passed': 0, 'failed': 0})

    def test_in_process_lines_count_their_cases(self):
        text = '{"case":"sign-in","status":"passed","seconds":1.8}\n  open reset=17\n{"case":"tabs","status":"failed"}\n'
        self.assertEqual(status.parse_in_process(text), {'passed': 1, 'failed': 1})

    def test_a_status_file_from_a_dead_or_finished_run_reads_as_not_running(self):
        self.assertTrue(status.live({'pid': os.getpid(), 'finished': None}))
        self.assertFalse(status.live({'pid': dead_pid(), 'finished': None}))
        self.assertFalse(status.live({'pid': os.getpid(), 'finished': 1000.0}))
        self.assertFalse(status.live({}))

    def test_the_lock_names_its_holder_pid(self):
        self.assertEqual(status.lock_owner('verify:mac:vm pid 4242'), 4242)
        self.assertIsNone(status.lock_owner(''))
        self.assertIsNone(status.lock_owner('something else'))

    def test_the_runner_is_stopped_booting_or_up(self):
        self.assertEqual(status.runner_state(running=False, keeper=False, vnc=False), 'stopped')
        self.assertEqual(status.runner_state(running=True, keeper=True, vnc=False), 'booting')
        self.assertEqual(status.runner_state(running=True, keeper=False, vnc=True), 'booting')
        self.assertEqual(status.runner_state(running=True, keeper=True, vnc=True), 'up')

    def test_idle_time_left_counts_down_from_thirty_minutes_and_stops_at_zero(self):
        self.assertEqual(status.idle_left(now=1000 + 600, last=1000, idle=1800), 1200)
        self.assertEqual(status.idle_left(now=1000 + 4000, last=1000, idle=1800), 0)

    def test_a_run_records_its_steps_and_appends_one_history_line(self):
        root = Path(tempfile.mkdtemp())
        progress = status.Progress(root / 'status.json', root / 'history.jsonl')
        progress.begin('run', ['sidebar'], '/tmp/out', log='/tmp/out/test.log')
        with progress.step('host build'):
            pass
        with progress.step('boot'):
            with progress.step('boot'):
                pass
        progress.start('XCUITest')
        saved = json.loads((root / 'status.json').read_text())
        self.assertEqual([step['name'] for step in saved['steps']], ['host build', 'boot', 'XCUITest'])
        self.assertEqual([step['state'] for step in saved['steps']], ['done', 'done', 'running'])
        self.assertEqual(saved['pid'], os.getpid())
        self.assertTrue(status.live(saved))
        progress.end('passed')
        saved = json.loads((root / 'status.json').read_text())
        self.assertFalse(status.live(saved))
        self.assertEqual(saved['steps'][-1]['state'], 'done')
        history = status.history((root / 'history.jsonl').read_text())
        self.assertEqual(len(history), 1)
        self.assertEqual((history[0]['kind'], history[0]['cases'], history[0]['result'], history[0]['output']),
                         ('run', ['sidebar'], 'passed', '/tmp/out'))

    def test_a_step_that_raises_marks_itself_failed(self):
        root = Path(tempfile.mkdtemp())
        progress = status.Progress(root / 'status.json', root / 'history.jsonl')
        progress.begin('prepare', [], '')
        with self.assertRaises(SystemExit):
            with progress.step('recovery'):
                raise SystemExit('the recovery app never showed its menu bar')
        saved = json.loads((root / 'status.json').read_text())
        self.assertEqual(saved['steps'][0]['state'], 'failed')

    def test_history_keeps_the_last_entries_and_skips_broken_lines(self):
        lines = [json.dumps({'kind': 'run', 'result': str(index)}) for index in range(12)]
        text = '\n'.join(lines[:5] + ['{broken'] + lines[5:]) + '\n'
        self.assertEqual([entry['result'] for entry in status.history(text, 10)], [str(index) for index in range(2, 12)])

    def test_the_rendered_status_shows_runner_lock_run_history_and_vnc(self):
        text = status.render({
            'now': 2000.0,
            'runner': {'name': 'lody-verify-runner', 'state': 'up', 'idle_left': 1450, 'paused': False,
                       'vnc': 'vnc://admin@localhost:5905'},
            'lock': {'pid': 77, 'started': 'Fri Oct 30 21:00:01 2026', 'command': 'python3 verification/mac/vm.py',
                     'cwd': '/repo', 'tty': 'ttys004'},
            'run': {'kind': 'run', 'cases': ['sidebar'], 'started': 1900.0, 'output': '/tmp/out',
                    'steps': [{'name': 'host build', 'state': 'done', 'started': 1900.0, 'ended': 1906.0},
                              {'name': 'XCUITest', 'state': 'running', 'started': 1950.0, 'ended': None}],
                    'tests': {'current': 'SidebarTests.testPinned', 'passed': 1, 'failed': 0},
                    'in_process': None},
            'history': [{'kind': 'run', 'cases': [], 'result': 'passed', 'seconds': 156.0, 'started': 1000.0,
                         'output': '/tmp/out'}],
        })
        for part in ['up', 'idle stop in 24m10s', 'vnc://admin@localhost:5905', 'pid 77', 'ttys004', '/repo',
                     'XCUITest', 'SidebarTests.testPinned', '1 passed, 0 failed', 'host build 6s', 'all', '156s']:
            self.assertIn(part, text)
        idle = status.render({'now': 0, 'runner': {'name': 'r', 'state': 'stopped', 'idle_left': None,
                                                   'paused': False, 'vnc': None},
                              'lock': None, 'run': None, 'history': []})
        self.assertIn('stopped', idle)
        self.assertIn('free', idle)
        self.assertIn('not running', idle)

    def test_a_step_that_started_after_the_snapshot_never_shows_a_negative_time(self):
        self.assertEqual(status.duration(-1.4), '0s')
        self.assertEqual(status.duration(3725), '1h02m')

    def test_the_lock_holder_command_drops_the_interpreter_path_and_a_missing_tty(self):
        self.assertEqual(status.short_command('/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/'
                                              'Versions/3.15/Resources/Python.app/Contents/MacOS/Python '
                                              'verification/mac/vm.py --case sidebar'),
                         'Python verification/mac/vm.py --case sidebar')
        lock = {'pid': 1, 'started': 'Fri', 'command': 'x', 'cwd': None, 'tty': '??'}
        text = status.render({'now': 0, 'runner': {'name': 'r', 'state': 'up', 'idle_left': None, 'paused': True,
                                                   'vnc': None}, 'lock': lock, 'run': None, 'history': []})
        self.assertIn('no tty', text)

    def test_status_is_a_command_that_can_follow(self):
        self.assertEqual(vm.parser.parse_args(['status']).command, 'status')
        self.assertFalse(vm.parser.parse_args(['status']).follow)
        self.assertTrue(vm.parser.parse_args(['status', '--follow']).follow)


if __name__ == '__main__':
    unittest.main()
