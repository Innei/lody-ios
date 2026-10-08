"""System sheet zoom: reversible dismissal and first-message composer handoff.

Review run.mp4: the source button expands into the sheet and cancellation returns
to it. Sending must remain continuous when navigation removes the source button.
"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
folder = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip()) / 'tmp'
started = time.monotonic()
events = []

def mark(action):
    events.append({'action': action, 'secondsFromFirstAction': time.monotonic() - started})

close = catalog.text('accessibility.closeSheet', title=catalog.text('create.title'))

def open_sheet():
    buttons = [i for i in ui.state() if i.get('type') == 'Button' and i.get('frame')]
    frame = max(buttons, key=lambda i: i['frame']['y'])['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1')
    ui.element('create-session-input')

for action in ('close', 'backdrop', 'swipe', 'send'):
    mark(action + '-open')
    open_sheet()
    ui.capture(action + '-open')
    if action == 'close':
        header = next(i['frame'] for i in ui.state() if i.get('AXLabel') == close)
        x, y = header['x'] + header['width'] / 2, header['y'] + header['height'] / 2
        ui.axe('swipe', '--start-x', str(x), '--start-y', str(y),
               '--end-x', str(x), '--end-y', str(y + 45), '--duration', '1', '--post-delay', '1')
        ui.element('create-session-input')
        ui.capture('cancelled-drag')
        mark('close-dismiss')
        ui.axe('tap', '--label', close, '--post-delay', '1')
    elif action == 'swipe':
        header = next(i['frame'] for i in ui.state() if i.get('AXLabel') == close)
        x, y = header['x'] + header['width'] / 2, header['y'] + header['height'] / 2
        mark('swipe-dismiss')
        ui.axe('swipe', '--start-x', str(x), '--start-y', str(y),
               '--end-x', str(x), '--end-y', str(y + 450), '--duration', '.5', '--post-delay', '1')
    elif action == 'backdrop':
        mark('backdrop-dismiss')
        ui.axe('tap', '-x', '30', '-y', '180', '--tap-style', 'physical', '--post-delay', '1')
    else:
        (folder / 'lody-production-composer-relay.json').unlink(missing_ok=True)
        frame = ui.element('create-type')['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] * .75), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1')
        ui.axe('tap', '--id', 'create-session-input')
        ui.type_into('create-session-input', 'System zoom handoff')
        ui.capture('send-draft')
        draft = ui.element('create-session-input')['AXValue']
        mark('send-dismiss')
        ui.axe('tap', '--id', 'session-send', '--post-delay', '1')
        ui.element('session-input')
        ui.wait(lambda items: any(i.get('AXLabel') == draft and (i.get('AXUniqueId') or '').endswith(':user') for i in items), 'Sent draft did not reach the conversation')
        relay = json.loads((folder / 'lody-production-composer-relay.json').read_text())
        assert relay['sameComposer'] and relay['inputBefore'] == relay['inputAfter'], 'Zoom interrupted the composer handoff'
        assert relay['inputBefore']['focused'], 'Zoom lost keyboard focus'
        assert all(abs(a - b) < 1.5 for a, b in zip(relay['source'], relay['adopted'])), 'Composer jumped after zoom dismissal'
        shutil.copy2(folder / 'lody-production-composer-relay.json', ui.output)
    ui.wait(lambda items: not any(i.get('AXUniqueId') == 'create-session-input' for i in items), action + ' left the sheet visible')
    ui.capture(action + '-closed')
    if action != 'send':
        ui.element('ui-design')
        probe = ui.element('ui-navigation-state')
        assert json.loads(probe['AXValue']) == ['index'], 'Dismissal left a stale Router presentation'
    mark(action + '-settled')
(ui.output / 'transition-events.json').write_text(json.dumps(events, indent=2))
print('PASS: close, cancelled drag, backdrop, completed swipe and send preserve sheet lifecycle and composer handoff. VISUAL REVIEW REQUIRED: system button-to-sheet zoom and source-less send dismissal.')
