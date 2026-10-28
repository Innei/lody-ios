"""Exercise the production Widget in the offline ActivityKit verification host.

Run in a verify:simulator lease after installing LodyActivityVerify. This checks
Widget presentation, not the full app's catalog, push delivery or route handling.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from driver import UI

udid = os.environ['LODY_VERIFY_UDID']
output = Path(sys.argv[1])
ui = UI(udid, output)


def sim(*args):
    return subprocess.run(['xcrun', 'simctl', *args], check=True, capture_output=True, text=True, timeout=30)


def select(name):
    sim('launch', '--terminate-running-process', udid, 'app.innei.lody', '-fixture', name, '-AppleLanguages', '(en)', '-AppleLocale', 'en_US')
    ui.invalidate_axe()
    expected = 'Ended' if name == 'end' else f'Showing {name}'
    ui.wait(lambda items: any(i.get('AXLabel') == expected for i in items), f'ActivityKit did not accept {name}')


def allow():
    for item in ui.state():
        if item.get('type') == 'Button' and item.get('AXLabel') in ['Allow', 'Always Allow']:
            ui.axe('tap', '--label', item['AXLabel'], '--post-delay', '1')
            return


record_log = (output / 'recording.log').open('w')
recording = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--force', '--codec=h264', str(output / 'phone.mp4')],
                             stdout=subprocess.DEVNULL, stderr=record_log)
results = []
try:
    select('end')
    for appearance in ['light', 'dark']:
        sim('ui', udid, 'appearance', appearance)
        for fixture, title in [('single', 'Refactor session list paging'), ('permission', 'Poll GitHub PR status'), ('done', 'Fix the CI cache key')]:
            start = time.monotonic()
            select(fixture)
            ui.axe('button', 'home')
            time.sleep(1)
            allow()
            ui.capture(f'{appearance}-{fixture}-compact')
            ui.axe('touch', '-x', '201', '-y', '33', '--down', '--up', '--delay', '.9')
            time.sleep(1)  # Let the system expansion finish before capturing.
            # Capture before querying AX: a slow Accessibility response can take
            # longer than the system's expanded-Island auto-dismiss deadline.
            ui.capture(f'{appearance}-{fixture}-expanded')
            tree = json.loads((output / f'{appearance}-{fixture}-expanded.json').read_text())
            def labels(nodes):
                for node in nodes:
                    yield node.get('AXLabel') or ''
                    yield from labels(node.get('children', []))
            assert any(title in label for label in labels(tree)), 'Expanded Island title missing'
            ui.axe('button', 'home')
            ui.axe('button', 'lock')
            time.sleep(1)
            allow()
            ui.capture(f'{appearance}-{fixture}-lock')
            ui.axe('button', 'lock')
            ui.axe('swipe', '--start-x', '200', '--start-y', '800', '--end-x', '200', '--end-y', '300', '--duration', '.4', '--post-delay', '1')
            results.append({'appearance': appearance, 'fixture': fixture, 'entrySeconds': round(time.monotonic() - start, 2), 'visualReview': 'pending'})
            print(f'Captured {appearance} {fixture}', flush=True)
    select('end')
finally:
    recording.send_signal(signal.SIGINT)
    recording.wait(timeout=20)
    record_log.close()
    assert recording.returncode == 0, 'Simulator recording failed; see recording.log'
    (output / 'observations.json').write_text(json.dumps({'surface': 'Production Widget in offline ActivityKit host', 'udid': udid, 'checks': results}, indent=2) + '\n')
