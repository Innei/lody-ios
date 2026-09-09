"""Real sheet keyboard, duplicate-send suppression and exact rejected-draft restore."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
# The production sheet host must allow rows beneath the floating composer.
ui.capture('half-sheet')
header = next(item['frame'] for item in ui.state() if item.get('AXLabel') == catalog.text('accessibility.closeSheet', title='输入框验收'))
ui.axe('swipe', '--start-x', '200', '--start-y', str(header['y'] + 10),
       '--end-x', '200', '--end-y', '100', '--duration', '.6', '--post-delay', '.8')
expanded = next(item['frame'] for item in ui.state() if item.get('AXLabel') == catalog.text('accessibility.closeSheet', title='输入框验收'))
assert expanded['y'] < header['y'] - 100, 'Sheet did not reach the full detent'
ui.capture('full-sheet')
field = ui.element('create-session-input')['frame']
assert any((item.get('AXUniqueId') or '').startswith('option-')
           and item['frame']['y'] < field['y'] + field['height']
           and item['frame']['y'] + item['frame']['height'] > field['y']
           for item in ui.state()), 'List does not continue beneath the floating input'
ui.axe('tap', '--id', 'option-0', '--post-delay', '.6')
ui.element('sheet-choice-1')
ui.capture('picker-full')
ui.axe('tap', '--id', 'sheet-choice-2', '--post-delay', '.6')
ui.element('create-session-input')
for _ in range(4):
    field = ui.element('create-session-input')['frame']
    ui.axe('swipe', '--start-x', '200', '--start-y', str(field['y'] - 35),
           '--end-x', '200', '--end-y', '280', '--duration', '.5', '--post-delay', '.4')
last = ui.element('option-7')['frame']
field = ui.element('create-session-input')['frame']
assert last['y'] + last['height'] <= field['y'], 'Last option cannot clear the floating input'
assert last['y'] > 0, 'Last option scrolled offscreen'
ui.capture('list-end')
pasted = ui.paste_file('create-session-input')
ui.axe('type', 'Offline draft\nSecond line')
screen_height = ui.state()[0]['frame']['height']
keyboard = ui.wait(lambda items: next((i['frame'] for i in items if (i.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar') and i['frame']['y'] < screen_height - 150), None), 'Software keyboard did not appear')
keyboard_top = min([keyboard['y']] + [i['frame']['y'] for i in ui.state() if i.get('AXLabel') == 'Typing Predictions'])
field = ui.element('create-session-input')['frame']
attach = ui.element('session-attach')['frame']
send = ui.element('session-send')
model = ui.element('session-model')['frame']
assert send['frame']['y'] + send['frame']['height'] <= keyboard_top + 1, 'Keyboard covers the send control'
attach_center = (attach['x'] + attach['width'] / 2, attach['y'] + attach['height'] / 2)
send_center = (send['frame']['x'] + send['frame']['width'] / 2,
               send['frame']['y'] + send['frame']['height'] / 2)
assert abs(attach_center[0] - field['x'] - 24) <= 1, 'Focused Add is not inset 24 points inside the unified input'
assert abs(field['x'] + field['width'] - send_center[0] - 24) <= 1, 'Focused Send is not inset 24 points inside the unified input'
assert abs(attach_center[1] - send_center[1]) <= 1, 'Focused Add and Send do not share a baseline'
assert model['x'] + model['width'] <= send['frame']['x'] + 1, 'Focused model selector moved away from the trailing side'
draft = ui.element('create-session-input')['AXValue']
ui.capture('keyboard')
ui.axe('tap', '--id', 'session-send')
assert not ui.element('session-send')['enabled'], 'Pending send must be disabled'
assert not ui.element('create-session-input').get('AXValue'), 'Pending draft must clear'
assert not any(item.get('AXLabel') == pasted for item in ui.state()), 'Pending attachment must clear'
frame = send['frame']
ui.axe('tap', '-x', str(frame['x'] + frame['width']/2), '-y', str(frame['y'] + frame['height']/2))
ui.axe('tap', '--label', 'Complete Request')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'create-session-input' and i.get('AXValue') == draft for i in items), 'Rejected draft was not restored')
assert any(item.get('AXLabel') == pasted for item in ui.state()), 'Pasted attachment was not restored'
assert ui.element('session-send')['enabled']
assert ui.element('composer-result')['AXLabel'] == 'Requests: 1', 'Duplicate tap dispatched twice'
ui.capture('restored')
print('PASS: sheet file paste, keyboard clearance, exact draft restore and duplicate suppression')
