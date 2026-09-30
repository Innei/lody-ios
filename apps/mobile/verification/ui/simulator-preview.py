"""One live decoder survives full-screen/back, dragging and typing; close releases it."""
import re
import sys
import json
import shutil
import subprocess
from pathlib import Path
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
container = Path(subprocess.check_output(
    ['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
traces = container / 'tmp'
entrances = 0


def stream():
    item = ui.element('simulator-stream')
    value = item.get('AXValue') or ''
    match = re.fullmatch(r'stream:([^,]+),connections:(\d+),active:(\d+),frame:(\d+)', value)
    assert match, f'Fixture has not decoded a frame: {value}'
    assert int(match[3]) == 1, f'A previous stream is still running: {value}'
    return match[1], int(match[2]), int(match[4])


def back():
    global entrances
    before = set(traces.glob('lody-simulator-entrance-*.json'))
    ui.axe('tap', '--id', 'BackButton', '--post-delay', '.8')
    ui.element('simulator-preview-expand')
    paths = set(traces.glob('lody-simulator-entrance-*.json')) - before
    completed = [p for p in paths if json.loads(p.read_text())['completed']]
    assert len(completed) == 1, f'Return must play one entrance: {paths}'
    result = json.loads(completed[0].read_text())
    samples = result['samples']
    opacity = [s['opacity'] for s in samples]
    assert any(.05 < a < .95 for a in opacity), 'Preview appeared without a fade'
    assert all(b >= a - .02 for a, b in zip(opacity, opacity[1:])), opacity
    assert opacity[-1] > .99 and samples[-1]['seconds'] < .8, result
    assert any(.05 < s['blurMask'] < .95 for s in samples), 'Entrance blur did not fade'
    assert result['blurRemoved'], 'Entrance left the live stream blurred'
    entrances += 1
    shutil.copy2(completed[0], ui.output / f'entrance-{entrances}.json')


def check_backdrop():
    blur = ui.element('simulator-preview-blur')['frame']
    image = ui.element('simulator-stream')['frame']
    outsets = [(blur[dimension] - image[dimension]) / 2 for dimension in ('width', 'height')]
    assert min(outsets) > 35, (image, blur)
    assert abs(outsets[0] - outsets[1]) < 2, 'Blur thickness differs between horizontal and vertical edges'
    for origin, dimension in (('x', 'width'), ('y', 'height')):
        assert abs(blur[origin] + blur[dimension] / 2 - image[origin] - image[dimension] / 2) < 1, (image, blur)


ui.axe('tap', '--id', 'session-preview', '--post-delay', '.5')
opened = ui.wait(
    lambda items: next((i for i in items if i.get('AXUniqueId') == 'simulator-stream' or i.get('AXLabel') == 'iPhone Simulator'), None),
    'Neither a remembered stream nor the device chooser opened')
if opened.get('AXUniqueId') != 'simulator-stream':
    ui.axe('tap', '--label', 'iPhone Simulator', '--post-delay', '1')
first = stream()
assert first[1] == 1
ui.capture('fullscreen')
ui.axe('swipe', '--start-x', '1', '--start-y', '450', '--end-x', '70', '--end-y', '450', '--duration', '1.2', '--post-delay', '.8')
assert ui.element('simulator-stream')['frame']['width'] > 200, 'A cancelled return left the renderer in the floating host'
assert stream()[0] == first[0], 'A cancelled return replaced the decoder'
ui.capture('cancelled-return')
back()
returned = stream()
assert returned[0] == first[0] and returned[1] == 1 and returned[2] > first[2], (first, returned)
for action in ('expand', 'close'):
    button = ui.element(f'simulator-preview-{action}')
    assert button['AXLabel'] == catalog.text(f'native.simulator.{action}'), button
check_backdrop()
ui.capture('floating')
settled_entrances = set(traces.glob('lody-simulator-entrance-*.json'))

before = ui.element('simulator-preview-expand')['frame']
image = ui.element('simulator-stream')['frame']
ui.axe('drag', '--start-x', str(image['x'] + image['width'] / 2),
       '--start-y', str(image['y'] + image['height'] / 2), '--end-x', '65',
       '--end-y', str(image['y'] + image['height'] / 2 + 90), '--duration', '.8', '--steps', '60', '--post-delay', '.5')
after = ui.element('simulator-preview-expand')['frame']
assert after['x'] < before['x'] - 50, (before, after)
ui.capture('dragged')

ui.axe('tap', '--id', 'session-input')
ui.type_into('session-input', 'draft')
close = ui.element('simulator-preview-close')['frame']
expand = ui.element('simulator-preview-expand')['frame']
image = ui.element('simulator-stream')['frame']
input_frame = ui.element('session-input')['frame']
assert image['y'] + image['height'] < input_frame['y'], (image, input_frame)
assert close['width'] >= 44 and close['height'] >= 44, close
assert expand['width'] >= 44 and expand['height'] >= 44, expand
assert expand['x'] + expand['width'] <= close['x'], (expand, close)
check_backdrop()
ui.capture('keyboard')
assert set(traces.glob('lody-simulator-entrance-*.json')) == settled_entrances, 'Dragging or typing replayed the entrance'

ui.axe('tap', '--id', 'simulator-preview-expand', '--post-delay', '1')
expanded = stream()
assert expanded[0] == first[0] and expanded[1] == 1 and expanded[2] > returned[2], (returned, expanded)
ui.capture('expanded-again')
back()
assert (ui.element('session-input').get('AXValue') or '').casefold() == 'draft', 'Expanding lost the composer draft'
ui.axe('tap', '--id', 'simulator-preview-close', '--post-delay', '.6')
assert not any(i.get('AXUniqueId') in ('simulator-preview-expand', 'simulator-stream') for i in ui.state()), 'Close left the stream visible'
ui.capture('closed')

ui.axe('tap', '--id', 'session-preview', '--post-delay', '1')
reopened = stream()
assert reopened[0] != first[0] and reopened[1] == 1, (first, reopened)
back()
ui.capture('reopened')
ui.axe('tap', '--id', 'BackButton', '--post-delay', '.8')
ui.element('simulator-preview')
ui.axe('tap', '--id', 'simulator-preview', '--post-delay', '.8')
ui.axe('tap', '--id', 'session-preview', '--post-delay', '1')
new_chat = stream()
assert new_chat[0] != reopened[0] and new_chat[1] == 1, (reopened, new_chat)
back()
ui.capture('new-chat')


def preview_menu(action):
    chip = ui.element('session-preview')['frame']
    ui.axe('touch', '-x', str(chip['x'] + chip['width'] / 2), '-y', str(chip['y'] + chip['height'] / 2), '--down', '--up', '--delay', '.8')
    ui.axe('tap', '--label', action, '--post-delay', '.5')


other_name = 'Second Simulator' if ui.element('simulator-stream')['AXLabel'] == 'iPhone Simulator' else 'iPhone Simulator'
preview_menu(catalog.text('simulator.chooseAnother'))
ui.axe('tap', '--label', other_name, '--post-delay', '1')
second = stream()
assert second[0] != new_chat[0] and second[1] == 1, (new_chat, second)
assert ui.element('simulator-stream')['AXLabel'] == other_name
back()
ui.capture('changed-device')
preview_menu(catalog.text('session.preview.stop'))
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'simulator-preview-expand' for i in items), 'Revoking preview did not close the floating stream')
ui.capture('stopped')
print(f'PASS: shared stream {first[0]} kept one connection and decoded frames across navigation; close created a fresh stream {reopened[0]}')
print(f'PASS: {entrances} returns faded in through native blur, removed the effect, and ordinary layout did not replay it')
