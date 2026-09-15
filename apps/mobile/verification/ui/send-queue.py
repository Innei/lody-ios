"""Queue above the composer; Steer delivers the selected item, Stop advances FIFO."""
import json
import subprocess
import sys
from driver import UI
import catalog
from send_motion import ThrowTrace

ui = UI(*sys.argv[1:])
trace = ThrowTrace(ui)
ui.axe('tap', '--id', 'send-connect')
assert ui.element('session-stop')['enabled'], 'Running with no draft must offer Stop'
assert ui.element('session-stop')['AXLabel'] == catalog.text('native.chat.composer.stop')
ui.axe('tap', '--id', 'session-input')
ui.type_into('session-input', 'draft')
assert ui.element('session-send')['enabled']
for _ in range(5):
    ui.axe('key', '42')
assert ui.element('session-stop')['enabled'], 'Deleting the draft must restore Stop'
turns = []
for index in [1, 2]:
    message = f'{index} queued message'
    ui.type_into('session-input', message)
    ui.axe('tap', '--id', 'session-send')
    ui.wait(lambda items: any(i.get('AXLabel') == f'Calls: {index} · sending' for i in items), 'Queue write did not start')
    pending = ui.wait(lambda items: next((i for i in items if (i.get('AXUniqueId') or '').endswith(':queued') and message in (i.get('AXLabel') or '')), None), 'Pending queue card missing')
    turn = pending['AXUniqueId'].removesuffix(':queued')
    turns.append(turn)
    assert not any(i.get('AXUniqueId') in [turn + ':user', turn + ':duration'] for i in ui.state()), 'Queued message flashed in the transcript'
    assert not ui.element(turn + ':steer')['enabled'], 'Unconfirmed queue write must not be steerable'
    assert ui.element(turn + ':steer')['AXLabel'].startswith(catalog.text('native.chat.composer.steer') + ': ')
    ui.axe('tap', '--id', 'send-complete')
    ui.wait(lambda items: any(i.get('AXUniqueId') == turn + ':steer' and i.get('enabled') for i in items), 'Queue receipt did not unlock Steer')
    assert ui.element('queue-count')['AXLabel'] == f'Queue: {index}'
    assert not ui.element('session-input').get('AXValue'), 'Queued draft reappeared'
    assert ui.element('session-stop')['enabled']
    frame = ui.element(turn + ':queued')['frame']
    assert frame['y'] + frame['height'] <= ui.element('session-input')['frame']['y'], 'Queue must sit above the input'
    ui.capture(f'queued-{index}')
assert turns[0] != turns[1]
assert not set(trace.folder.glob('lody-throw-*.json')) - trace.existing, 'Queuing a message must not fly it into the transcript'
ui.type_into('session-input', '123456')
subprocess.run([str(ui.output.parents[1] / 'software-keyboard'), subprocess.check_output(['xcode-select', '-p'], text=True).strip(), ui.udid], check=True, timeout=30)
ui.wait(lambda items: any(i.get('AXUniqueId') == 'inputView' and i['frame']['height'] > 200 for i in items),
        'Queue landing must be exercised with the software keyboard open')

ui.axe('tap', '--id', turns[1] + ':steer')
request = json.loads(ui.element('control-request')['AXLabel'])
assert request['action'] == 'steer' and request['messageId'] == turns[1] and request['turnId'] == 'running-reply'
assert not ui.element(turns[1] + ':steer')['enabled']
ui.capture('steer-pending')
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXUniqueId') == turns[1] + ':steer' and i.get('enabled') for i in items), 'Failed Steer did not retain a retryable queue message')
assert ui.element('queue-count')['AXLabel'] == 'Queue: 2'
ui.capture('steer-failed-retained')
ui.axe('tap', '--id', turns[1] + ':steer')
ui.axe('tap', '--id', 'send-complete')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'queue-count' and i.get('AXLabel') == 'Queue: 1' for i in items), 'Selected Steer was not consumed')
ui.element(turns[0] + ':queued')
assert not any(i.get('AXUniqueId') == turns[1] + ':queued' for i in ui.state())
ui.element(turns[1] + ':reply:text')
if not any(i.get('AXUniqueId') == turns[1] + ':user' for i in ui.state()):
    ui.axe('swipe', '--start-x', '200', '--start-y', '350', '--end-x', '200', '--end-y', '700', '--duration', '.4', '--post-delay', '.6')
ui.element(turns[1] + ':user')
assert ui.element('session-input').get('AXValue') == '123456', 'Steer must preserve the current unsent draft'
ui.capture('steer-applied-first-still-queued')
ui.axe('tap', '--id', 'session-input')
for _ in range(6):
    ui.axe('key', '42')

ui.axe('tap', '--id', 'session-stop')
request = json.loads(ui.element('control-request')['AXLabel'])
assert request['action'] == 'stop' and request['turnId'] == turns[1] + ':reply'
assert not ui.element('session-stop')['enabled']
ui.capture('stopping')
ui.axe('tap', '--id', 'send-complete')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'queue-count' and i.get('AXLabel') == 'Queue: 0' for i in items), 'Stop did not advance the queued message')
ui.element(turns[0] + ':reply:text')
if not any(i.get('AXUniqueId') == turns[0] + ':user' for i in ui.state()):
    ui.axe('swipe', '--start-x', '200', '--start-y', '350', '--end-x', '200', '--end-y', '700', '--duration', '.4', '--post-delay', '.6')
ui.element(turns[0] + ':user')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-stop' and i.get('enabled') for i in items), 'The next running turn must offer Stop')
ui.capture('stop-advanced-queue')
ui.axe('tap', '--id', 'session-stop')
ui.axe('tap', '--id', 'send-complete')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-send' and not i.get('enabled') for i in items), 'Stop without a queue must return to idle')
assert not any((i.get('AXUniqueId') or '').endswith(':queued') for i in ui.state())
assert not any(i.get('AXUniqueId') == 'session-queue' and i['frame']['height'] > 0 for i in ui.state()), \
    'Empty queue glass must release its reserved height'
ui.capture('idle')
trace.verify(1)
print('PASS: input/Stop switching, queue-only pending cards, selected Steer with failure/retry, targeted Stop advances FIFO, no queue-time throw, steered rows slide into the transcript')
