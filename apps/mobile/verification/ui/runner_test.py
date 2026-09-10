"""Exercise real CLI selection and standalone failure propagation without a Simulator."""
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


class StopBeforeMetro(Exception):
    pass


class RunnerTest(unittest.TestCase):
    def test_failed_standalone_does_not_skip_next_case_or_other_batches(self):
        for batch in ['pages', 'send', 'chat']:
            with self.subTest(batch=batch), tempfile.TemporaryDirectory() as output:
                calls = []

                def child(command, **kwargs):
                    case = command[command.index('--case') + 1]
                    calls.append(case)
                    self.assertFalse(kwargs['check'])
                    if case == 'home':
                        return subprocess.CompletedProcess(command, 1)
                    path = Path(command[command.index('--output') + 1])
                    path.mkdir(parents=True)
                    (path / 'results.json').write_text(json.dumps([{'case': case, 'status': 'passed'}]))
                    return subprocess.CompletedProcess(command, 0)

                argv = ['run.py', '--udid', 'test-device', '--app', '/unused.app', '--batch', batch, '--output', output]
                with patch.object(sys, 'argv', argv), patch('subprocess.run', side_effect=child), \
                     patch('socket.create_connection', side_effect=OSError), \
                     patch('subprocess.Popen', side_effect=StopBeforeMetro):
                    with self.assertRaises(StopBeforeMetro):
                        runpy.run_path(str(Path(__file__).with_name('run.py')), run_name='__main__')
                if batch == 'pages':
                    self.assertEqual(calls, ['home', 'licenses', 'navigation'])
                    results = json.loads((Path(output) / 'results.json').read_text())
                    self.assertEqual([item['status'] for item in results], ['failed', 'passed', 'passed'])
                else:
                    self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
