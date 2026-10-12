"""Parallel workers run concurrently, keep failures, and never attach to another Metro."""
import ast
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from urllib.parse import parse_qs, urlparse
from unittest.mock import patch

from driver import UI, launch_covered, restart_accessibility
import catalog
from orchestrator import managed_metro, prewarm_bundle, run_batches


class RunnerTest(unittest.TestCase):
    def test_case_links_encode_the_action_and_allow_repeated_entry(self):
        with tempfile.TemporaryDirectory() as directory, patch('driver.subprocess.run') as run:
            ui = UI('owned-simulator', directory)
            ui.open_case('case with & query')
            ui.open_case('case with & query')
            urls = [call.args[0][-1] for call in run.call_args_list]
            queries = [parse_qs(urlparse(url).query) for url in urls]
            self.assertEqual([q['verifyCase'] for q in queries], [['case with & query']] * 2)
            self.assertNotEqual(queries[0]['request'], queries[1]['request'])
            self.assertTrue(all(urlparse(url).path == '/debug' for url in urls))
            self.assertTrue(all(call.kwargs['check'] and call.kwargs['timeout'] == 30 for call in run.call_args_list))

    def test_failed_case_link_is_not_silently_replaced_by_menu_navigation(self):
        with tempfile.TemporaryDirectory() as directory, patch('driver.subprocess.run', side_effect=subprocess.CalledProcessError(1, 'openurl')):
            with self.assertRaises(subprocess.CalledProcessError):
                UI('owned-simulator', directory).open_case('send-handoff')

    def test_text_uses_one_system_paste_without_losing_quotes_or_newlines(self):
        text = "draft 'quoted' \"double\"\nnext line & $value"
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-simulator', directory)
            with patch.object(ui, 'paste_text', return_value='performed') as paste, patch('driver.subprocess.check_output') as hid:
                self.assertEqual(ui.axe('type', text), 'performed')
                paste.assert_called_once_with(text)
                hid.assert_not_called()

    def test_batch_typing_uses_one_input_command_and_fails_without_retyping(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-simulator', directory)
            with patch.object(ui, 'paste_text') as paste, patch.object(ui, 'element', return_value={'AXValue': 'draft'}):
                ui.type_into('field', 'draft')
                paste.assert_called_once_with('draft', expected_identifier='field')

    def test_text_input_preserves_case_instead_of_accepting_shift_transformation(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-simulator', directory)
            with patch.object(ui, 'paste_text') as paste, patch.object(ui, 'element', return_value={'AXValue': 'DRAFT'}):
                with self.assertRaisesRegex(AssertionError, "did not commit: 'DRAFT'"):
                    ui.type_into('field', 'draft')
                paste.assert_called_once_with('draft', expected_identifier='field')
            with patch.object(ui, 'paste_text') as paste, patch.object(ui, 'element', return_value={'AXValue': 'different'}):
                with self.assertRaisesRegex(AssertionError, 'did not commit'):
                    ui.type_into('field', 'draft')
                paste.assert_called_once_with('draft', expected_identifier='field')

    def test_partial_batch_input_is_reported_without_appending_or_erasing_text(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-simulator', directory)
            with patch.object(ui, 'paste_text') as paste, patch.object(ui, 'element', return_value={'AXValue': 'dra'}):
                with self.assertRaisesRegex(AssertionError, "did not commit: 'dra'"):
                    ui.type_into('field', 'draft')
                paste.assert_called_once_with('draft', expected_identifier='field')

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


class SystemPasteTest(unittest.TestCase):
    @staticmethod
    def focused(text='', start=0, end=0):
        return {'id': 'field', 'pid': 123, 'class': 'UITextField', 'text': text, 'firstResponder': True,
                'selection': {'start': start, 'end': end},
                'frame': {'x': 16, 'y': 120, 'width': 314, 'height': 44},
                'caret': {'x': 22, 'y': 130, 'width': 2, 'height': 20},
                'selectedFrame': {'x': 22, 'y': 130, 'width': 100, 'height': 20},
                'touchOwner': {'class': 'UITextField', 'id': 'field', 'belongsToInput': True,
                               'point': {'x': 26 if start == end else 72, 'y': 140}}}

    def perform(self, ui, text, focus, *, touch_error=None, existing_menu=False):
        paste = {'AXLabel': 'Paste', 'frame': {'x': 40, 'y': 90, 'width': 50, 'height': 44}}
        with (
            patch.object(ui, '_focused_input', side_effect=focus) as read,
            patch.object(ui, 'axe', side_effect=touch_error) as gestures,
            patch.object(ui, 'wait', return_value=paste),
            patch.object(ui, 'state', return_value=[paste] if existing_menu else []),
            patch('driver.subprocess.run') as copy,
            patch('driver.subprocess.check_output', return_value=text) as clipboard,
            patch('catalog.system', return_value='Paste'),
        ):
            ui.paste_text(text)
        return read, gestures, copy, clipboard

    def test_recorded_back_overlap_fails_before_clipboard_or_any_gesture(self):
        before = {'id': 'team-join-reason', 'pid': 3086, 'class': 'RCTUITextView',
                  'text': '', 'firstResponder': True, 'selection': {'start': 0, 'end': 0},
                  'frame': {'x': 16, 'y': 41, 'width': 370, 'height': 100},
                  'caret': {'x': 31, 'y': 51, 'width': 2, 'height': 22},
                  'selectedFrame': {'x': 32, 'y': 52, 'width': 0, 'height': 20.33333333333333},
                  'touchOwner': {'class': 'UIKit.NavigationBarContentView', 'id': '',
                                 'belongsToInput': False, 'point': {'x': 35, 'y': 62}}}
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with (patch.object(ui, '_focused_input', return_value=before),
                  patch.object(ui, 'axe') as gestures, patch('driver.subprocess.run') as copy,
                  patch('driver.subprocess.check_output') as clipboard):
                with self.assertRaisesRegex(RuntimeError, 'touch belongs to another view'):
                    ui.type_into('team-join-reason', 'Please add me.')
            copy.assert_not_called()
            clipboard.assert_not_called()
            gestures.assert_not_called()
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['before'], before)
            self.assertEqual(event['status'], 'failed')
            self.assertNotIn('clipboardSeconds', event)
            self.assertNotIn('menuAction', event)

    def test_recorded_native_point_mismatch_fails_before_clipboard_or_any_gesture(self):
        before = {'id': 'Toolbar', 'pid': 99853, 'class': 'UISearchBarTextField',
                  'text': '', 'firstResponder': True, 'selection': {'start': 0, 'end': 0},
                  'frame': {'x': 8, 'y': 498, 'width': 326, 'height': 28},
                  'caret': {'x': 48.66666666666666, 'y': 501, 'width': 2, 'height': 22},
                  'selectedFrame': {'x': 48.66666666666666, 'y': 502, 'width': 0, 'height': 20.33333333333337},
                  'touchOwner': {'class': 'UICollectionView', 'id': '', 'belongsToInput': True,
                                 'point': {'x': 52.66666666666666, 'y': 0}}}
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with (patch.object(ui, '_focused_input', return_value=before),
                  patch.object(ui, 'axe') as gestures, patch('driver.subprocess.run') as copy,
                  patch('driver.subprocess.check_output') as clipboard):
                with self.assertRaisesRegex(RuntimeError, 'native hit-test point differs'):
                    ui.paste_text('/tmp/lody-ios')
            copy.assert_not_called()
            clipboard.assert_not_called()
            gestures.assert_not_called()
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['before'], before)
            self.assertEqual(event['status'], 'failed')
            self.assertNotIn('clipboardSeconds', event)
            self.assertNotIn('menuAction', event)

    def test_empty_input_pastes_complete_text_at_the_existing_caret_without_refocus(self):
        text = 'Mobile review\nquotes " & $value'
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            read, gestures, copy, clipboard = self.perform(ui, text, [self.focused()])
            read.assert_called_once()
            copy.assert_called_once_with(['xcrun', 'simctl', 'pbcopy', 'owned-phone'], input=text, text=True,
                                         capture_output=True, check=True, timeout=30)
            clipboard.assert_called_once_with(['xcrun', 'simctl', 'pbpaste', 'owned-phone'], text=True, timeout=30)
            self.assertEqual([call.args[0] for call in gestures.call_args_list], ['touch', 'tap'])
            self.assertEqual(gestures.call_args_list[0].args[2:5], ('26', '-y', '140.0'))
            self.assertTrue(all(call.kwargs.get('recover') is False for call in gestures.call_args_list))
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['before']['selection'], {'start': 0, 'end': 0})
            self.assertEqual(event['text'], text)
            self.assertEqual(event['status'], 'performed')

    def test_nonempty_append_and_selected_text_require_unchanged_native_selection(self):
        for start, end in [(5, 5), (1, 4)]:
            with self.subTest(start=start, end=end), tempfile.TemporaryDirectory() as directory:
                ui = UI('owned-phone', directory)
                before = self.focused('draft', start, end)
                before['class'] = 'RCTUITextField'
                read, gestures, copy, _ = self.perform(ui, ' suffix', [before, dict(before)], existing_menu=start != end)
                self.assertEqual(read.call_count, 2)
                copy.assert_called_once()
                expected_actions = ['touch', 'tap'] if start == end else ['tap']
                self.assertEqual([call.args[0] for call in gestures.call_args_list], expected_actions)
                event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
                self.assertEqual(event['afterMenu']['selection'], before['selection'])

    def test_existing_selected_range_menu_is_used_without_another_gesture(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            before = self.focused('draft', 0, 5)
            read, gestures, copy, _ = self.perform(ui, 'replacement', [before, dict(before)], existing_menu=True)
            self.assertEqual(read.call_count, 2)
            copy.assert_called_once()
            self.assertEqual([call.args[0] for call in gestures.call_args_list], ['tap'])
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['menuAction'], 'existing-menu')
            self.assertEqual(event['afterMenu']['selection'], {'start': 0, 'end': 5})

    def test_hidden_selected_range_menu_fails_without_changing_selection(self):
        before = self.focused('draft', 0, 5)
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with (
                patch.object(ui, '_focused_input', return_value=before) as read,
                patch.object(ui, 'axe') as gestures,
                patch.object(ui, 'state', return_value=[]),
                patch.object(ui, 'wait') as wait,
                patch('driver.subprocess.run'),
                patch('driver.subprocess.check_output', return_value='replacement'),
                patch('catalog.system', return_value='Paste'),
            ):
                with self.assertRaisesRegex(RuntimeError, 'selected range.*no visible Paste menu'):
                    ui.paste_text('replacement')
            read.assert_called_once()
            gestures.assert_not_called()
            wait.assert_not_called()
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['before']['selection'], {'start': 0, 'end': 5})
            self.assertEqual(event['menuAction'], 'existing-menu')
            self.assertEqual(event['status'], 'failed')

    def test_long_press_that_changes_selection_fails_before_paste_without_restoring_it(self):
        before = self.focused('draft', 5, 5)
        changed = self.focused('draft', 0, 5)
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with (
                patch.object(ui, '_focused_input', side_effect=[before, changed]),
                patch.object(ui, 'axe') as gestures,
                patch.object(ui, 'wait', return_value={'frame': {'x': 40, 'y': 90, 'width': 50, 'height': 44}}),
                patch('driver.subprocess.run'),
                patch('driver.subprocess.check_output', return_value=' suffix'),
                patch('catalog.system', return_value='Paste'),
            ):
                with self.assertRaisesRegex(RuntimeError, 'changed.*selection'):
                    ui.paste_text(' suffix')
            self.assertEqual([call.args[0] for call in gestures.call_args_list], ['touch'])
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['status'], 'failed')

    def test_missing_existing_focus_fails_without_tapping_or_copying_text(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with patch.object(ui, '_focused_input', side_effect=RuntimeError('no focus')), patch.object(ui, 'axe') as gestures, patch('driver.subprocess.run') as copy:
                with self.assertRaisesRegex(RuntimeError, 'no focus'):
                    ui.paste_text('draft')
            gestures.assert_not_called()
            copy.assert_not_called()

    def test_failed_paste_tap_is_not_replayed(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with patch.object(ui, '_focused_input', return_value=self.focused()), patch.object(ui, 'axe', side_effect=[None, subprocess.TimeoutExpired('tap', 20)]) as gestures, patch.object(ui, 'wait', return_value={'frame': {'x': 40, 'y': 90, 'width': 50, 'height': 44}}), patch('driver.subprocess.run'), patch('driver.subprocess.check_output', return_value='draft'), patch('catalog.system', return_value='Paste'):
                with self.assertRaises(subprocess.TimeoutExpired):
                    ui.paste_text('draft')
            self.assertEqual([call.args[0] for call in gestures.call_args_list], ['touch', 'tap'])
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['status'], 'failed')


    def test_type_into_rejects_another_focused_field_before_clipboard_or_any_gesture(self):
        before = self.focused('Mobile review ', 14, 14)
        before['id'] = 'prompt-shortcut-name'
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with (
                patch.object(ui, '_focused_input', return_value=before) as read,
                patch.object(ui, 'axe') as gestures,
                patch.object(ui, 'element') as element,
                patch('driver.subprocess.run') as copy,
                patch('driver.subprocess.check_output') as clipboard,
            ):
                with self.assertRaisesRegex(RuntimeError, "does not belong to 'prompt-shortcut-prompt'.*'prompt-shortcut-name'"):
                    ui.type_into('prompt-shortcut-prompt', 'Review the mobile change.')
            read.assert_called_once()
            gestures.assert_not_called()
            element.assert_not_called()
            copy.assert_not_called()
            clipboard.assert_not_called()
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['expectedIdentifier'], 'prompt-shortcut-prompt')
            self.assertEqual(event['before'], before)
            self.assertEqual(event['status'], 'failed')
            self.assertNotIn('pasteFrame', event)

    def test_targeted_input_uses_the_matched_native_owner_without_refocus(self):
        text = 'Mobile review'
        paste = {'AXLabel': 'Paste', 'frame': {'x': 40, 'y': 90, 'width': 50, 'height': 44}}
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with (
                patch.object(ui, '_focused_input', return_value=self.focused()) as read,
                patch.object(ui, 'axe') as gestures,
                patch.object(ui, 'wait', return_value=paste),
                patch.object(ui, 'state', return_value=[]),
                patch.object(ui, 'element', return_value={'AXValue': text}) as element,
                patch('driver.subprocess.run') as copy,
                patch('driver.subprocess.check_output', return_value=text),
                patch('catalog.system', return_value='Paste'),
            ):
                ui.type_into('field', text)
            read.assert_called_once()
            copy.assert_called_once()
            element.assert_called_once_with('field')
            self.assertEqual([call.args[0] for call in gestures.call_args_list], ['touch', 'tap'])
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['expectedIdentifier'], 'field')
            self.assertEqual(event['status'], 'performed')

    def test_targeted_input_without_a_native_owner_fails_without_guessing_from_the_frame(self):
        before = self.focused()
        before['id'] = ''
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with patch.object(ui, '_focused_input', return_value=before), patch.object(ui, 'axe') as gestures, patch('driver.subprocess.run') as copy:
                with self.assertRaisesRegex(RuntimeError, "does not belong to 'field'"):
                    ui.paste_text('draft', expected_identifier='field')
            gestures.assert_not_called()
            copy.assert_not_called()


    def test_empty_rn_field_opens_paste_with_one_caret_tap_and_checks_the_same_owner(self):
        text = 'new@example.invalid'
        before = self.focused()
        before['class'] = 'RCTUITextField'
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            read, gestures, copy, _ = self.perform(ui, text, [before, dict(before)])
            self.assertEqual(read.call_count, 2)
            copy.assert_called_once()
            self.assertEqual([call.args[0] for call in gestures.call_args_list], ['tap', 'tap'])
            self.assertEqual(gestures.call_args_list[0].args[2:5], ('26', '-y', '140.0'))
            self.assertTrue(all(call.kwargs.get('recover') is False for call in gestures.call_args_list))
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['menuAction'], 'repeat-caret-tap')
            self.assertEqual(event['afterMenu'], before)
            self.assertNotIn('afterLongPress', event)
            self.assertEqual(event['text'], text)
            self.assertEqual(event['status'], 'performed')

    def test_empty_rn_field_that_changes_owner_after_menu_is_rejected_before_paste(self):
        before = self.focused()
        before['class'] = 'RCTUITextField'
        changed = dict(before, id='other-field')
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-phone', directory)
            with (
                patch.object(ui, '_focused_input', side_effect=[before, changed]) as read,
                patch.object(ui, 'axe') as gestures,
                patch.object(ui, 'wait', return_value={'frame': {'x': 40, 'y': 90, 'width': 50, 'height': 44}}),
                patch('driver.subprocess.run') as copy,
                patch('driver.subprocess.check_output', return_value='draft'),
                patch('catalog.system', return_value='Paste'),
            ):
                with self.assertRaisesRegex(RuntimeError, 'changed.*focused input'):
                    ui.paste_text('draft', expected_identifier='field')
            self.assertEqual(read.call_count, 2)
            copy.assert_called_once()
            self.assertEqual([call.args[0] for call in gestures.call_args_list], ['tap'])
            event = json.loads((Path(directory) / 'text-input.jsonl').read_text())
            self.assertEqual(event['before'], before)
            self.assertEqual(event['afterMenu'], changed)
            self.assertEqual(event['status'], 'failed')
            self.assertNotIn('pasteFrame', event)


class InputBaselineTest(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).with_name('run.py')
        declaration = next(node for node in ast.parse(source.read_text()).body
                           if isinstance(node, ast.FunctionDef) and node.name == 'configure_input_baseline')
        namespace = {'Path': Path, 'subprocess': subprocess, 'time': time, 'json': json, '__file__': str(source)}
        exec(compile(ast.Module(body=[declaration], type_ignores=[]), str(source), 'exec'), namespace)
        self.configure = namespace['configure_input_baseline']

    def test_warmup_precedes_the_single_software_keyboard_setup(self):
        def run(command, **kwargs):
            return subprocess.CompletedProcess(command, 0, 'ok', '')

        with tempfile.TemporaryDirectory() as directory, patch('subprocess.run', side_effect=run) as commands, patch('subprocess.check_output', return_value='/Xcode'):
            self.configure('owned-phone', Path(directory))
            calls = [call.args[0] for call in commands.call_args_list]
            warmups = [index for index, command in enumerate(calls) if command[0] == 'axe']
            keyboard = [index for index, command in enumerate(calls) if command[0] == str(Path(directory) / 'software-keyboard')]
            self.assertEqual(len(warmups), 1)
            self.assertEqual(len(keyboard), 1)
            self.assertLess(warmups[0], keyboard[0])
            report = json.loads((Path(directory) / 'input-baseline.json').read_text())
            self.assertFalse(report['afterSoftwareKeyboard'])
            self.assertEqual(report['softwareKeyboard']['returncode'], 0)

    def test_failed_warmup_aborts_before_keyboard_setup_and_keeps_its_actual_error(self):
        def run(command, **kwargs):
            return subprocess.CompletedProcess(command, 1 if command[0] == 'axe' else 0, 'activation failed', '')

        with tempfile.TemporaryDirectory() as directory, patch('subprocess.run', side_effect=run) as commands:
            with self.assertRaises(subprocess.CalledProcessError):
                self.configure('owned-phone', Path(directory))
            calls = [call.args[0] for call in commands.call_args_list]
            self.assertFalse(any(command[0] == str(Path(directory) / 'software-keyboard') for command in calls))
            report = json.loads((Path(directory) / 'input-baseline.json').read_text())
            self.assertEqual(report['returncode'], 1)


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
        self.assertIn("elif case == 'send':", source)
        self.assertIn('check_timeout = 480', source)
        self.assertIn('accessibility automation', Path(__file__).with_name('driver.py').read_text())
        self.assertIn("env['LODY_UI_EMBEDDED'] = '1'", source)
        self.assertIn('except subprocess.TimeoutExpired as error:', source)
        navigation = Path(__file__).with_name('navigation.py').read_text()
        driver = Path(__file__).with_name('driver.py').read_text()
        self.assertIn("for label in ('Open', '打开', '開啟'):", driver)
        self.assertIn('def allow_custom_scheme', driver)
        self.assertIn('allow_custom_scheme(ui)', source)
        self.assertIn('allow_custom_scheme(ui)', navigation)
        self.assertIn('_scheme_allowed', navigation)
        self.assertIn("range(2 if embedded else 3)", navigation)
        self.assertIn("range(1 if embedded else 2)", navigation)
        self.assertIn("if embedded:", navigation)
        self.assertIn('recover=False', driver)
        self.assertIn("if not os.environ.get('LODY_UI_EMBEDDED'):", Path(__file__).with_name('send-handoff.py').read_text())
        native = Path(__file__).resolve().parents[1].joinpath('native.py').read_text()
        self.assertIn('timeout=240', native)
        self.assertIn("files.insert(0, 'LodyUIVerify.swift')", native)


class SearchKeyboardTest(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).with_name('session-search.py')
        declaration = next(node for node in ast.parse(source.read_text()).body
                           if isinstance(node, ast.FunctionDef) and node.name == 'keyboard')
        namespace = {}
        exec(compile(ast.Module(body=[declaration], type_ignores=[]), str(source), 'exec'), namespace)
        self.keyboard = namespace['keyboard']

    @staticmethod
    def scene(width, height, keyboard_y, keyboard_height):
        return [
            {'type': 'Application', 'frame': {'x': 0, 'y': 0, 'width': width, 'height': height}},
            {'AXUniqueId': 'UIKeyboardLayoutStar Preview',
             'frame': {'x': 0, 'y': keyboard_y, 'width': width, 'height': keyboard_height}},
        ]

    def test_offscreen_preview_does_not_satisfy_keyboard_focus(self):
        self.assertFalse(self.keyboard(self.scene(820, 1180, 1180, 279)))
        self.assertFalse(self.keyboard(self.scene(402, 874, 918, 226)))

    def test_real_visible_keyboard_counts_even_when_named_preview(self):
        self.assertTrue(self.keyboard(self.scene(820, 1180, 898, 279)))
        self.assertTrue(self.keyboard(self.scene(402, 874, 604, 226)))

    def test_missing_or_empty_keyboard_cannot_establish_focus(self):
        self.assertFalse(self.keyboard([]))
        self.assertFalse(self.keyboard(self.scene(402, 874, 604, 0)))


class CheckDeadlineTest(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).with_name('run.py')
        module = ast.parse(source.read_text())
        declarations = [node for node in module.body if (
            isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'OSS_CASES' for target in node.targets)
        ) or (isinstance(node, ast.FunctionDef) and node.name == 'run_case_check')]
        namespace = {'subprocess': subprocess}
        exec(compile(ast.Module(body=declarations, type_ignores=[]), str(source), 'exec'), namespace)
        self.run_check = namespace['run_case_check']

    @staticmethod
    def elapsed_check(command, *, timeout, stdout, **kwargs):
        """A deterministic child-process clock avoids waiting minutes in a runner check."""
        stdout.write('check started\n')
        if int(command[-1]) > timeout:
            raise subprocess.TimeoutExpired(command, timeout)
        stdout.write('check completed\n')
        return subprocess.CompletedProcess(command, 0)

    def test_long_checks_finish_after_the_previous_deadline(self):
        for case, elapsed in (
            ('session-search', 590),
            ('session-search-pad', 590),
            ('pull-request', 400),
        ):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                log_path = Path(directory) / 'check.log'
                with log_path.open('w') as log, patch('subprocess.run', self.elapsed_check):
                    result = self.run_check(case, ['check', str(elapsed)], log, {}, 'full')
                self.assertEqual(result.returncode, 0)
                self.assertEqual(log_path.read_text(), 'check started\ncheck completed\n')

    def test_deadlines_still_stop_long_checks_and_preserve_their_progress(self):
        for case, elapsed in (
            ('session-search', 601),
            ('session-search-pad', 601),
            ('pull-request', 421),
            ('run-options', 421),
            ('title-rename', 181),
        ):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                log_path = Path(directory) / 'check.log'
                with log_path.open('w') as log, patch('subprocess.run', self.elapsed_check):
                    with self.assertRaises(subprocess.TimeoutExpired):
                        self.run_check(case, ['check', str(elapsed)], log, {}, 'full')
                self.assertEqual(log_path.read_text(), 'check started\n')


class CaseEntryTest(unittest.TestCase):
    def setUp(self):
        source = Path(__file__).with_name('run.py')
        module = ast.parse(source.read_text())
        names = {'PREVIEW', 'READY', 'HOME_CASES', 'OSS_CASES'}
        declarations = [node for node in module.body if (
            isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id in names for target in node.targets)
        ) or (isinstance(node, ast.FunctionDef) and node.name == 'enter_case')]
        self.namespace = {}
        exec(compile(ast.Module(body=declarations, type_ignores=[]), str(source), 'exec'), self.namespace)
        self.enter_case = self.namespace['enter_case']

    def test_feature_entry_waits_for_its_scene_after_deep_link(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            marker = self.namespace['READY']['preview-close']
            state = [{'AXUniqueId': marker}]
            with patch.object(ui, 'open_case') as open_case, patch.object(ui, 'state', side_effect=[
                [{'AXUniqueId': 'session-input'}], state,
            ]) as read_state, patch('driver.time.sleep'):
                self.enter_case(ui, 'preview-close')
                open_case.assert_called_once_with(self.namespace['PREVIEW']['preview-close'])
                self.assertEqual(read_state.call_count, 2, 'A shared input must not establish readiness for the new scene')


    def test_failed_deep_link_never_reads_or_accepts_another_scene(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            with patch.object(ui, 'open_case', side_effect=RuntimeError('link rejected')), patch.object(ui, 'element') as element:
                with self.assertRaisesRegex(RuntimeError, 'link rejected'):
                    self.enter_case(ui, 'preview-close')
                element.assert_not_called()


    def test_home_fixture_waits_for_launch_without_opening_debug(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            with patch.object(ui, 'open_case') as open_case, patch.object(ui, 'element') as element:
                self.enter_case(ui, 'home')
                open_case.assert_not_called()
                element.assert_called_once_with('ui-verify-ready')


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

    def test_screenshot_retries_one_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            calls = []

            def run(command, **_kwargs):
                calls.append(command)
                if len(calls) == 1:
                    raise subprocess.TimeoutExpired(command, 20)
                Path(command[-1]).write_bytes(b'png')
                return subprocess.CompletedProcess(command, 0)

            with patch('subprocess.run', run):
                self.assertTrue(ui.screenshot('failure').exists())
            self.assertEqual(len(calls), 2)

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

    def test_empty_root_recovers_real_elements_once_without_replaying_input(self):
        stub = {'type': 'Application', 'pid': 31119, 'children': [],
                'frame': {'x': 0, 'y': 0, 'width': 0, 'height': 0}}
        field = {'AXUniqueId': 'chat-find-field', 'AXValue': 'Needle'}
        restored = {**stub, 'children': [field], 'frame': {'x': 0, 'y': 0, 'width': 820, 'height': 1180}}
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-ipad', directory)
            ui._axe_ready = True
            with (
                patch.object(ui, 'axe', side_effect=[json.dumps([stub]), json.dumps([restored])]) as axe,
                patch('driver.restart_accessibility') as restart,
                patch('driver.time.sleep'),
            ):
                self.assertEqual(ui.element('chat-find-field'), field)
            restart.assert_called_once_with('owned-ipad')
            self.assertEqual([call.args for call in axe.call_args_list], [('describe-ui',), ('describe-ui',)])
            events = [json.loads(line) for line in (Path(directory) / 'accessibility-recovery.jsonl').read_text().splitlines()]
            self.assertEqual(events[0]['pid'], 31119)
            self.assertEqual(events[-1]['event'], 'root-restored')
            self.assertEqual(events[-1]['nodes'], 2)
            self.assertTrue(ui._axe_ready)

    def test_persistent_empty_root_is_bounded_and_never_claims_recovery(self):
        stub = {'type': 'Application', 'pid': 31119, 'children': [],
                'frame': {'x': 0, 'y': 0, 'width': 0, 'height': 0}}
        clock = {'t': 0}
        calls = []

        def axe(*args, **kwargs):
            calls.append(args)
            clock['t'] += 31
            return json.dumps([stub])

        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-ipad', directory)
            ui._axe_ready = True
            with (
                patch.object(ui, 'axe', axe),
                patch('driver.restart_accessibility') as restart,
                patch('driver.time.monotonic', lambda: clock['t']),
                patch('driver.time.sleep'),
            ):
                with self.assertRaisesRegex(RuntimeError, 'Accessibility automation.*empty application root'):
                    ui.state()
            restart.assert_called_once_with('owned-ipad')
            self.assertLessEqual(len(calls), 3)
            self.assertTrue(all(args == ('describe-ui',) for args in calls))
            self.assertFalse(ui._axe_ready)
            events = [json.loads(line) for line in (Path(directory) / 'accessibility-recovery.jsonl').read_text().splitlines()]
            self.assertEqual(events[-1]['event'], 'unresolved')
            self.assertFalse(any(event['event'] == 'root-restored' for event in events))

    def test_first_empty_root_read_that_consumes_deadline_preserves_transport_error(self):
        stub = {'type': 'Application', 'pid': 31119, 'children': [],
                'frame': {'x': 0, 'y': 0, 'width': 0, 'height': 0}}
        clock = {'t': 0}

        def describe(*args, **kwargs):
            clock['t'] = 91
            return json.dumps([stub])

        with tempfile.TemporaryDirectory() as directory:
            ui = UI('owned-ipad', directory)
            ui._axe_ready = True
            with (
                patch.object(ui, 'axe', side_effect=describe) as axe,
                patch('driver.restart_accessibility') as restart,
                patch('driver.time.monotonic', lambda: clock['t']),
                patch('driver.time.sleep') as sleep,
            ):
                with self.assertRaisesRegex(RuntimeError, 'Accessibility automation.*empty application root'):
                    ui.state()
            axe.assert_called_once_with('describe-ui', timeout=20)
            restart.assert_called_once_with('owned-ipad')
            sleep.assert_not_called()
            self.assertFalse(ui._axe_ready)
            events = [json.loads(line) for line in (Path(directory) / 'accessibility-recovery.jsonl').read_text().splitlines()]
            self.assertEqual([event['event'] for event in events], ['empty-root', 'unresolved'])
            self.assertIn('empty application root', events[-1]['error'])

    def test_valid_trees_including_blank_full_frame_application_are_untouched(self):
        trees = [
            [],
            [{'type': 'Application', 'children': [], 'frame': {'width': 820, 'height': 1180}}],
            [{'type': 'Application', 'children': [{'AXUniqueId': 'field'}], 'frame': {'width': 0, 'height': 0}}],
        ]
        for tree in trees:
            with self.subTest(tree=tree), tempfile.TemporaryDirectory() as directory:
                ui = UI('owned-ipad', directory)
                with patch.object(ui, 'axe', return_value=json.dumps(tree)) as axe, patch('driver.restart_accessibility') as restart:
                    got = ui.state()
                self.assertEqual(got[:len(tree)], tree)
                axe.assert_called_once()
                restart.assert_not_called()
                self.assertFalse((Path(directory) / 'accessibility-recovery.jsonl').exists())

    def test_wait_survives_a_cold_axe_session(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            calls = {'count': 0}

            def state():
                calls['count'] += 1
                if calls['count'] < 3:
                    raise subprocess.TimeoutExpired('axe', 30)
                return [{'AXUniqueId': 'ui-verify-ready', 'pid': 1}]

            with patch.object(ui, 'state', state), patch('driver.time.sleep'):
                found = ui.wait(
                    lambda items: next((item for item in items if item.get('AXUniqueId') == 'ui-verify-ready'), None),
                    'Missing ui-verify-ready',
                    timeout=30,
                )
            self.assertEqual(found['pid'], 1)
            self.assertEqual(calls['count'], 3)

    def test_launch_covered_detects_springboard(self):
        self.assertFalse(launch_covered([], '15427'))
        self.assertFalse(launch_covered([{'pid': 15427, 'AXUniqueId': 'ui-verify-ready'}], '15427'))
        self.assertTrue(launch_covered([{'pid': 16345, 'AXLabel': 'Maps'}], '15427'))

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

            with (
                patch('subprocess.check_output', check_output),
                patch('driver.time.sleep'),
                patch('driver.restart_accessibility') as restart,
            ):
                self.assertEqual(ui.axe('tap', '--id', 'send-fail'), 'ok')
            self.assertEqual(calls['count'], 3)
            self.assertEqual(restart.call_count, 2)
            restart.assert_called_with('UDID')
            self.assertTrue(ui._axe_ready)

    def test_restart_accessibility_kickstarts_testmanagerd(self):
        with patch('subprocess.run', return_value=subprocess.CompletedProcess([], 0)) as run:
            restart_accessibility('UDID')
        command = run.call_args.args[0]
        self.assertEqual(command[:4], ['xcrun', 'simctl', 'spawn', 'UDID'])
        self.assertEqual(command[-2:], ['-k', 'user/foreground/com.apple.testmanagerd'])
        self.assertFalse(run.call_args.kwargs['check'])

    def test_axe_retries_when_restoring_accessibility_times_out(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            ui._axe_ready = True
            calls = {'count': 0}

            def check_output(*_args, **_kwargs):
                calls['count'] += 1
                if calls['count'] < 3:
                    return 'Error: AXe timed out while restoring accessibility automation.\n'
                return 'ok'

            with patch('subprocess.check_output', check_output), patch('driver.time.sleep'):
                self.assertEqual(ui.axe('tap', '--id', 'send-toggle-pending'), 'ok')
            self.assertEqual(calls['count'], 3)
            self.assertTrue(ui._axe_ready)


class CatalogTest(unittest.TestCase):
    def test_workspace_switch_includes_live_device_summary(self):
        self.assertEqual(
            catalog.workspace_switch('我的超长工作区名称不能折行'),
            'Switch workspace, 我的超长工作区名称不能折行, 2 online / 3 devices',
        )
        self.assertEqual(
            catalog.workspace_switch('另一个工作区', count=0, total=0),
            'Switch workspace, 另一个工作区, 0 online / 0 devices',
        )
        self.assertEqual(
            catalog.workspace_switch('2026'),
            'Switch workspace, 2026, 2 online / 3 devices',
        )

    def test_spoken_workspace_label_is_shared_by_home_hosts(self):
        for name in ('navigation.py', 'home.py', 'licenses.py', 'ipad-sidebar.py'):
            source = Path(__file__).with_name(name).read_text()
            self.assertIn('catalog.workspace_switch(', source, name)


class SchemePermissionTest(unittest.TestCase):
    def test_allow_custom_scheme_taps_open_then_falls_back_to_coordinates(self):
        from driver import allow_custom_scheme
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            calls = []

            def axe(*args, **kwargs):
                calls.append(args)
                if args and args[0] == 'tap' and '--label' in args:
                    raise subprocess.TimeoutExpired('axe', 3)
                return 'ok'

            with patch.object(ui, 'axe', axe), patch('driver.time.sleep'):
                allow_custom_scheme(ui)
            self.assertEqual(calls[0][calls[0].index('--label') + 1], 'Open')
            self.assertEqual(calls[-1][:5], ('tap', '-x', '280', '-y', '450'))
            self.assertFalse(ui._axe_ready)

    def test_allow_custom_scheme_skips_coordinates_when_open_is_absent(self):
        from driver import allow_custom_scheme
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            calls = []
            clock = {'t': 0}

            def axe(*args, **kwargs):
                calls.append(args)
                raise RuntimeError("Error: No accessibility element matched --label 'Open'.")

            with (
                patch.object(ui, 'axe', axe),
                patch('driver.time.monotonic', lambda: clock['t']),
                patch('driver.time.sleep', lambda seconds: clock.update(t=clock['t'] + seconds)),
            ):
                allow_custom_scheme(ui)
            labels = [args[args.index('--label') + 1] for args in calls if '--label' in args]
            self.assertGreaterEqual(len(labels), 6)
            self.assertEqual(labels[:3], ['Open', '打开', '開啟'])
            self.assertFalse(any(args[:2] == ('tap', '-x') for args in calls))

    def test_missing_open_from_cli_exit_does_not_tap_underlying_app(self):
        from driver import allow_custom_scheme
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            clock = {'t': 0}
            missing = subprocess.CalledProcessError(
                1, 'axe', output="Error: No accessibility element matched --label 'Open'.")
            with (
                patch('driver.subprocess.check_output', side_effect=missing) as command,
                patch('driver.time.monotonic', lambda: clock['t']),
                patch('driver.time.sleep', lambda seconds: clock.update(t=clock['t'] + seconds)),
            ):
                allow_custom_scheme(ui)
            self.assertTrue(command.call_args_list)
            self.assertFalse(any('-x' in call.args[0] for call in command.call_args_list))
            self.assertEqual(command.call_args.kwargs['stderr'], subprocess.STDOUT)

    def test_allow_custom_scheme_retries_until_open_appears(self):
        from driver import allow_custom_scheme
        with tempfile.TemporaryDirectory() as directory:
            ui = UI('UDID', directory)
            calls = []

            def axe(*args, **kwargs):
                calls.append(args)
                open_tries = sum(
                    1 for previous in calls if '--label' in previous and previous[previous.index('--label') + 1] == 'Open'
                )
                if args and '--label' in args and args[args.index('--label') + 1] == 'Open' and open_tries >= 2:
                    return 'ok'
                raise RuntimeError("Error: No accessibility element matched --label 'Open'.")

            with patch.object(ui, 'axe', axe), patch('driver.time.sleep'), patch('driver.time.monotonic', return_value=0):
                allow_custom_scheme(ui)
            labels = [args[args.index('--label') + 1] for args in calls if '--label' in args]
            self.assertEqual(labels[:4], ['Open', '打开', '開啟', 'Open'])
            self.assertFalse(any(args[:2] == ('tap', '-x') for args in calls))

    def test_runner_does_not_read_ax_before_dismissing_the_scheme_alert(self):
        handshake = Path(__file__).with_name('run.py').read_text().split('if not links_ready:')[1].split('links_ready = True')[0]
        self.assertIn('allow_custom_scheme(ui)', handshake)
        self.assertNotIn("ui.axe('tap', '--label', 'Open'", handshake)


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
