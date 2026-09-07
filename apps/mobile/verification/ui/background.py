"""Real WebView lifecycle and iOS scheduler; no cloud or credentials."""
import json
from pathlib import Path
import subprocess
import sys
import time
from driver import UI

udid, output = sys.argv[1:3]
ui = UI(udid, output)
evidence = []

def state(items):
    row = next((i for i in items if i.get('AXUniqueId') == 'background-status'), {})
    return json.loads(row.get('AXValue') or row.get('AXLabel') or '{}')

def wait(predicate, label):
    value = ui.wait(lambda items: state(items) if predicate(state(items)) else None, label)
    evidence.append({'step': label, **value})
    return value

def tap(name):
    ui.axe('tap', '--id', 'background-' + name, '--tap-style', 'physical')

def foreground():
    subprocess.run(['xcrun', 'simctl', 'launch', udid, 'app.innei.lody'], check=True, timeout=30)

try:
    tap('start')
    initial = wait(lambda s: s.get('state') == 'live' and s.get('updates', 0) > 0, 'fixture ready')
    ui.capture('connected')
    ui.axe('button', 'home')
    time.sleep(5)
    foreground()
    returned = wait(lambda s: s.get('updates', 0) > initial['updates'], 'callbacks resume after background')
    assert returned['generation'] == initial['generation'], 'Background destroyed the WebView'
    ui.capture('retained')
    tap('send')
    submitted = wait(lambda s: s.get('task') in ['running', 'unavailable'], 'system scheduler decision')
    available = submitted['task'] == 'running'
    ui.capture('task-started')
    ui.axe('button', 'home')
    time.sleep(40)
    ui.capture('background')
    foreground()
    resumed = wait(lambda s: s.get('updates', 0) > submitted['updates'], 'returns after 40 seconds')
    assert resumed['generation'] == initial['generation'], 'Resume rebuilt a healthy WebView'
    if available:
        assert resumed['backgroundUpdates'] - submitted['backgroundUpdates'] >= 25, 'Granted task did not keep WebView executing'
    else:
        print('LIMIT: Simulator rejected BGContinuedProcessingTask; background longevity/cancellation not proven', flush=True)
    ui.capture('after-background')
    tap('complete')
    wait(lambda s: s.get('tasks') == 0 and (not available or s.get('task') == 'completed'),
         'completed work releases task' if available else 'foreground usable after unavailable request')
    ui.capture('completed')
    if available:
        tap('send')
        wait(lambda s: s.get('task') == 'running' and s.get('tasks') == 1, 'new user send starts fresh task')
        tap('expire')
        wait(lambda s: s.get('task') == 'expired' and s.get('tasks') == 0, 'expiration releases task')
        ui.capture('expired')
        time.sleep(2)
        wait(lambda s: s.get('tasks') == 0, 'late stream updates do not restart expired task')
    tap('stop')
    wait(lambda s: s.get('state') == 'stopped', 'explicit stop releases runtime')
    print('PASS: retained WebView, foreground recovery, explicit stop; scheduler available=' + str(available), flush=True)
finally:
    Path(output, 'background-evidence.json').write_text(json.dumps(evidence, indent=2))
