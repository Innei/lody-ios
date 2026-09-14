"""Real form-sheet dismissal/root push with the same local native message."""
import sys
import subprocess
import json
from pathlib import Path
from driver import UI
import catalog
from send_motion import ThrowTrace
ui = UI(*sys.argv[1:])
throw_trace = ThrowTrace(ui)
subprocess.run([str(ui.output.parent.parent / 'software-keyboard'), subprocess.check_output(['xcode-select', '-p'], text=True).strip(), ui.udid], check=True, timeout=30)
ui.axe('tap', '--id', 'create-session-input', '--tap-style', 'physical', '--post-delay', '.4')
keyboard = ui.element('inputView')
assert keyboard['frame']['height'] > 200, 'The handoff must begin with the software keyboard visible'
# HID typing switches the Simulator to a hardware keyboard; tap software keys
# so this transition exercises the same keyboard dismissal as a real phone.
for char in 'hi':
    key = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').lower() == char and i.get('type') == 'Button'), None), 'Missing keyboard key ' + char)['frame']
    ui.axe('tap', '-x', str(key['x'] + key['width'] / 2), '-y', str(key['y'] + key['height'] / 2), '--tap-style', 'physical')
assert ui.element('inputView')['frame']['height'] > 200
draft = ui.element('create-session-input')['AXValue']
ui.capture('source')
ui.axe('tap', '--id', 'session-send', '--tap-style', 'physical')
ui.element('send-status')
shiny = ui.wait(lambda items: next((i for i in items if (i.get('AXUniqueId') or '').endswith(':duration')), None), 'Target pending row missing')
turn = shiny['AXUniqueId'].removesuffix(':duration')
assert draft == ui.element(turn + ':user')['AXLabel']
assert ui.element('send-status')['AXLabel'] == 'Calls: 0 · waiting', 'Creation waited for network or dispatched offline'
ui.capture('target-offline')
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
relay = json.loads((container / 'tmp/lody-production-composer-relay.json').read_text())
assert relay['sameComposer'], 'The destination replaced the source composer'
assert relay['inputBefore'] == relay['inputAfter'], 'Adoption changed focus, selection, or appearance'
assert relay['inputBefore']['focused'], 'The source lost keyboard focus before adoption'
assert all(abs(a - b) < 1.5 for a, b in zip(relay['source'], relay['adopted'])), relay
assert ui.element('inputView')['frame']['height'] > 200, 'Adoption dismissed the keyboard'
(ui.output / 'composer-relay.json').write_text(json.dumps(relay, indent=2))
timer_frame = ui.element(turn + ':duration')['frame']
geometry_errors = []

def assert_timer_stable(stage):
    frame = ui.element(turn + ':duration')['frame']
    print(f'{stage}: timer frame {frame}', flush=True)
    for dimension in ['y', 'height']:
        if abs(frame[dimension] - timer_frame[dimension]) >= 1.5:
            geometry_errors.append(f'{stage}: timer {dimension} shifted from {timer_frame} to {frame}')

ui.axe('tap', '--id', 'send-connect')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 1 · creating' for i in items), 'Creation did not start')
assert_timer_stable('connected')
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('send.alert.title') for i in items), 'Creation failure missing')
ui.axe('tap', '--label', catalog.system('ok'))
assert not ui.element('session-input').get('AXValue'), 'Failure jumped into the destination input'
assert ui.element(turn + ':user')['AXLabel'] == draft
assert ui.element(turn + ':pending')['AXLabel'] == catalog.text('native.chat.message.retry')
ui.capture('target-failure-retained')
ui.axe('tap', '--id', turn + ':pending')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · creating' for i in items), 'Explicit creation retry did not start')
ui.capture('target-retrying')
assert_timer_stable('retrying')
ui.axe('tap', '--id', 'send-complete')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 3 · sending' for i in items), 'First turn did not start after creation')
assert_timer_stable('created')
ui.axe('tap', '--id', 'send-complete')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 3 · accepted' for i in items), 'Receipt missing')
assert_timer_stable('accepted')
ui.capture('target-accepted')
ui.axe('tap', '--id', 'send-start-reply')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 3 · idle' for i in items), 'First reply did not reconcile pending')
assert_timer_stable('first reply')
first_label = ui.element(turn + ':duration')['AXLabel']
ui.wait(lambda items: any(i.get('AXUniqueId') == turn + ':duration' and i.get('AXLabel') != first_label for i in items), 'Timer stopped after takeover')
assert_timer_stable('tick after takeover')
ui.capture('target-reconciled')
assert not geometry_errors, '\n'.join(geometry_errors)
print('PASS: immediate first turn, failure/retry, stable timer geometry through connection and first reply takeover')

throw_trace.verify(1)
