"""Parallel workers run concurrently, keep failures, and never attach to another Metro."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from driver import UI
from orchestrator import managed_metro, prewarm_bundle, run_batches


class RunnerTest(unittest.TestCase):
    def test_parallel_workers_keep_sibling_results_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            worker = output / 'worker.py'
            worker.write_text('''import json, pathlib, sys, time
root, name = pathlib.Path(sys.argv[1]), sys.argv[2]
(root / (name + '.ready')).touch()
deadline = time.monotonic() + 10
while len(list(root.glob('*.ready'))) != 3:
    assert time.monotonic() < deadline, 'Workers did not start concurrently'
    time.sleep(.01)
status = 'failed' if name == 'b' else 'passed'
(root / name / 'results.json').write_text(json.dumps([{'case': name, 'status': status}]))
print('completed ' + name)
sys.exit(1 if name == 'b' else 0)
''')
            commands = {name: [sys.executable, str(worker), directory, name] for name in ['a', 'b', 'c']}
            self.assertEqual(run_batches(commands, output), 1)
            results = json.loads((output / 'results.json').read_text())
            self.assertEqual({r['case']: r['status'] for r in results}, {'a': 'passed', 'b': 'failed', 'c': 'passed'})
            for name in commands:
                self.assertIn('completed ' + name, (output / name / 'worker.log').read_text())

    def test_owned_metro_refuses_occupied_port_without_stopping_it(self):
        with socket.socket() as server, tempfile.TemporaryDirectory() as output:
            server.bind(('127.0.0.1', 0))
            server.listen()
            port = server.getsockname()[1]
            with self.assertRaisesRegex(RuntimeError, 'occupied'):
                with managed_metro(Path(output), port, Path(output)):
                    self.fail('An existing server must never be reused')
            with socket.create_connection(('127.0.0.1', port)):
                pass


class AcceptanceRoundTest(unittest.TestCase):
    """A round keeps both appearances, refuses missing evidence, and separates blocked from fail."""

    SCRIPT = Path(__file__).with_name('acceptance-round.py')
    CLAIM = {
        'id': 'glass-fusion',
        'behavior': '聊天输入框融合后共用玻璃交互',
        'category': '输入框交互',
        'cases': ['composer-glass-chat'],
        'requiredEvidence': ['screenshot', 'video'],
    }

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.output = self.root / 'run'

    def tearDown(self):
        self.directory.cleanup()

    def write_run(self, statuses, errors):
        for appearance, status, error in zip(('light', 'dark'), statuses, errors):
            case = self.output / appearance / 'composer-glass-chat'
            case.mkdir(parents=True, exist_ok=True)
            (case / 'after.png').write_bytes(b'png ' + appearance.encode())
            (case / 'after.json').write_text('{}')
            (case / 'run.mp4').write_bytes(b'mp4')
        (self.output / 'results.json').write_text(json.dumps([
            {'case': 'composer-glass-chat', 'appearance': appearance, 'language': 'en', 'status': status, 'error': error}
            for appearance, status, error in zip(('light', 'dark'), statuses, errors)
        ]))
        (self.output / 'environment.json').write_text(json.dumps({
            'app': '/tmp/Lody.app', 'language': 'en', 'baseCommit': 'deadbeef',
        }))

    def export(self, claims, name, *extra):
        claims_path = self.root / f'{name}-claims.json'
        claims_path.write_text(json.dumps(claims, ensure_ascii=False))
        round_dir = self.root / name
        completed = subprocess.run(
            [sys.executable, str(self.SCRIPT), '--output', str(self.output), '--claims', str(claims_path),
             '--title', '融合 Plus 的玻璃交互', '--dir', str(round_dir), *extra],
            capture_output=True, text=True,
        )
        return completed, round_dir

    def test_round_keeps_each_appearance_apart(self):
        self.write_run(('passed', 'passed'), (None, None))
        completed, round_dir = self.export([self.CLAIM], 'round')
        self.assertEqual(completed.returncode, 0, completed.stderr)
        evidence = json.loads((round_dir / 'result.json').read_text())['cases'][0]['evidence']
        self.assertEqual(len(evidence), len(set(evidence)), 'One appearance must not overwrite the other')
        self.assertTrue(all((round_dir / path).is_file() for path in evidence))
        for appearance in ('light', 'dark'):
            self.assertIn(f'assets/composer-glass-chat/{appearance}/after.png', evidence)

    def test_missing_required_evidence_writes_no_round(self):
        self.write_run(('passed', 'passed'), (None, None))
        claim = {**self.CLAIM, 'requiredEvidence': ['screenshot', 'gif']}
        completed, round_dir = self.export([claim], 'round-missing')
        self.assertEqual(completed.returncode, 1)
        self.assertIn('gif', completed.stderr)
        self.assertFalse(round_dir.exists())

    def test_harness_timeout_is_blocked_and_assertion_failure_is_not(self):
        self.write_run(('passed', 'failed'), (None, "Command 'x' timed out after 180 seconds"))
        completed, blocked_round = self.export([self.CLAIM], 'round-blocked')
        self.assertEqual(completed.returncode, 0, completed.stderr)
        blocked = json.loads((blocked_round / 'result.json').read_text())
        self.assertEqual(blocked['cases'][0]['status'], 'blocked')
        self.assertEqual(blocked['summary']['verdict'], 'partial')

        self.write_run(('failed', 'passed'), ('AssertionError: Fast state did not return from RN', None))
        completed, failed_round = self.export([self.CLAIM], 'round-failed')
        self.assertEqual(completed.returncode, 0, completed.stderr)
        failed = json.loads((failed_round / 'result.json').read_text())
        self.assertEqual(failed['cases'][0]['status'], 'fail')
        self.assertEqual(failed['summary']['verdict'], 'fail')


class CaseSelectionTest(unittest.TestCase):
    def test_default_phone_run_excludes_pad_device_cases(self):
        source = Path(__file__).with_name('run.py').read_text()
        self.assertIn('PHONE_CASES', source)
        self.assertIn('selected = PHONE_CASES', source)
        self.assertNotIn('selected = CASES', source)
        self.assertIn('if args.case in PAD_CASES', source)

    def test_core_suite_is_the_six_product_paths(self):
        source = Path(__file__).with_name('run.py').read_text()
        self.assertIn(
            "'core': ['onboarding', 'inbox', 'navigation', 'send', 'send-handoff', 'composer-success']",
            source,
        )
        self.assertIn("'core-home': ['onboarding', 'inbox', 'navigation']", source)
        self.assertIn("'core-send': ['send', 'send-handoff', 'composer-success']", source)
        self.assertIn("selection.add_argument('--suite', choices=SUITES", source)
        self.assertIn('core_suite = args.suite in CORE_SUITES', source)
        self.assertIn("appearances = ['light']", source)
        self.assertIn("'--embedded'", source)
        self.assertIn('args.shared_metro or args.embedded', source)
        self.assertIn("ui.screenshot('failure')", source)
        self.assertIn("elif case == 'navigation':", source)
        self.assertIn('check_timeout = 480', source)
        self.assertIn('check_timeout = 600', source)
        self.assertIn("elif case == 'send':", source)
        self.assertIn('fail_fast = bool(args.fail_fast)', source)
        self.assertIn("env['LODY_UI_EMBEDDED'] = '1'", source)
        self.assertIn('except subprocess.TimeoutExpired as error:', source)
        navigation = Path(__file__).with_name('navigation.py').read_text()
        self.assertIn("for label in ('Open', '打开', '開啟'):", navigation)
        self.assertIn('_scheme_allowed', navigation)
        self.assertIn("range(2 if embedded else 3)", navigation)
        self.assertIn('recover=False', navigation)
        native = Path(__file__).resolve().parents[1].joinpath('native.py').read_text()
        self.assertIn('timeout=240', native)
        self.assertIn("files.insert(0, 'LodyUIVerify.swift')", native)


class CaptureTest(unittest.TestCase):
    def test_screenshot_does_not_need_axe(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)

            def run(command, **_kwargs):
                Path(command[-1]).write_bytes(b'png')
                return subprocess.CompletedProcess(command, 0)

            with patch('subprocess.run', run):
                path = ui.screenshot('failure')
            self.assertEqual(path, Path(directory) / 'failure.png')
            self.assertTrue(path.exists())

    def test_capture_keeps_screenshot_when_describe_ui_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)

            def run(command, **_kwargs):
                Path(command[-1]).write_bytes(b'png')
                return subprocess.CompletedProcess(command, 0)

            with (
                patch('subprocess.run', run),
                patch.object(ui, 'axe', side_effect=subprocess.TimeoutExpired('axe', 20)),
                self.assertRaises(subprocess.TimeoutExpired),
            ):
                ui.capture('failure')
            self.assertTrue((Path(directory) / 'failure.png').exists())

    def test_state_retries_until_axe_session_is_ready(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            calls = {'count': 0}

            def axe(*_args, **_kwargs):
                calls['count'] += 1
                if calls['count'] < 3:
                    raise RuntimeError('Error: Timed out creating the simulator remote automation session')
                return '[]'

            with patch.object(ui, 'axe', axe), patch('driver.time.sleep'):
                self.assertEqual(ui.state(), [])
            self.assertEqual(calls['count'], 3)
            self.assertTrue(ui._axe_ready)
            ui.invalidate_axe()
            self.assertFalse(ui._axe_ready)

    def test_axe_retries_when_the_session_dies_mid_command(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            ui._axe_ready = True
            calls = {'count': 0}

            def check_output(*_args, **_kwargs):
                calls['count'] += 1
                if calls['count'] < 3:
                    raise subprocess.TimeoutExpired('axe', 20)
                return 'ok'

            with patch('subprocess.check_output', check_output), patch('driver.time.sleep'):
                self.assertEqual(ui.axe('tap', '--id', 'send-fail'), 'ok')
            self.assertEqual(calls['count'], 3)
            self.assertTrue(ui._axe_ready)


class PrewarmTest(unittest.TestCase):
    def test_prewarm_retries_manifest_then_succeeds(self):
        calls = {'manifest': 0}

        def manifest(_port, _timeout=60):
            calls['manifest'] += 1
            if calls['manifest'] < 2:
                raise TimeoutError('slow compile')
            return {'launchAsset': {'url': 'http://127.0.0.1/bundle'}}

        with (
            patch('orchestrator.load_expo_manifest', manifest),
            patch('orchestrator.read_launch_asset', return_value=b'ok'),
            patch('orchestrator.time.sleep'),
        ):
            prewarm_bundle(8097, attempts=3, pause=0)
        self.assertEqual(calls['manifest'], 2)

    def test_prewarm_gives_up_after_retries(self):
        with (
            patch('orchestrator.load_expo_manifest', side_effect=TimeoutError('slow compile')),
            patch('orchestrator.time.sleep'),
            self.assertRaises(TimeoutError),
        ):
            prewarm_bundle(8097, attempts=2, pause=0)


if __name__ == '__main__':
    unittest.main()
