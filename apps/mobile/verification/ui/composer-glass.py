"""iOS 26 composer glass merges on focus with balanced controls."""
import sys
from driver import UI

ui = UI(*sys.argv[1:])
input_id = 'session-input' if 'composer-glass-chat' in str(ui.output) else 'create-session-input'
field = ui.element(input_id)['frame']
attach = ui.element('session-attach')['frame']
assert abs(field['x'] - attach['x'] - attach['width'] - 8) <= 1, \
    'Unfocused Add and input glass do not keep the current 8-point gap'
ui.capture('separate')

ui.axe('tap', '--id', input_id, '--post-delay', '.8')
field = ui.element(input_id)['frame']
attach = ui.element('session-attach')['frame']
send = ui.element('session-send')['frame']
model = ui.element('session-model')['frame']
attach_center = (attach['x'] + attach['width'] / 2, attach['y'] + attach['height'] / 2)
send_center = (send['x'] + send['width'] / 2, send['y'] + send['height'] / 2)
assert abs(attach_center[0] - field['x'] - 28) <= 1, \
    'Focused Add is not inset 28 points inside the unified input'
assert abs(field['x'] + field['width'] - send_center[0] - 24) <= 1, \
    'Focused Send is not inset 24 points inside the unified input'
assert abs(attach_center[1] - send_center[1]) <= 1, \
    'Focused Add and Send do not share a baseline'
assert model['x'] + model['width'] <= send['x'] + 1, \
    'Focused model selector moved away from the trailing side'
ui.capture('merged')
# Hold the empty accessory area: UIKit's interactive glass must carry Add too.
x = (attach['x'] + attach['width'] + model['x']) / 2
y = send_center[1]
ui.axe('touch', '-x', str(x), '-y', str(y), '--down')
try:
    ui.capture('pressed')
finally:
    ui.axe('touch', '-x', str(x), '-y', str(y), '--up')
ui.capture('released')
if input_id == 'session-input':
    ui.axe('tap', '-x', '200', '-y', str(field['y'] - 90), '--post-delay', '.5')
else:
    ui.axe('swipe', '--start-x', '200', '--start-y', str(field['y'] - 90),
           '--end-x', '200', '--end-y', str(field['y'] - 30), '--duration', '.3', '--post-delay', '.5')
collapsed = ui.element(input_id)['frame']
separate_add = ui.element('session-attach')['frame']
assert abs(collapsed['x'] - separate_add['x'] - separate_add['width'] - 8) <= 1, 'Closing did not restore the separate glass'
ui.capture('collapsed-again')
ui.axe('tap', '--id', input_id, '--post-delay', '.8')
ui.capture('reopened')
print('PASS: iOS 26 focus merges Add into one balanced glass; held/released input interaction captured')
