"""iOS 26 composer glass merges on focus with balanced controls."""
import sys
from driver import UI

ui = UI(*sys.argv[1:])
field = ui.element('create-session-input')['frame']
attach = ui.element('session-attach')['frame']
assert abs(field['x'] - attach['x'] - attach['width'] - 8) <= 1, \
    'Unfocused Add and input glass do not keep the current 8-point gap'
ui.capture('separate')

ui.axe('tap', '--id', 'create-session-input', '--post-delay', '.8')
field = ui.element('create-session-input')['frame']
attach = ui.element('session-attach')['frame']
send = ui.element('session-send')['frame']
model = ui.element('session-model')['frame']
attach_center = (attach['x'] + attach['width'] / 2, attach['y'] + attach['height'] / 2)
send_center = (send['x'] + send['width'] / 2, send['y'] + send['height'] / 2)
assert abs(attach_center[0] - field['x'] - 24) <= 1, \
    'Focused Add is not inset 24 points inside the unified input'
assert abs(field['x'] + field['width'] - send_center[0] - 24) <= 1, \
    'Focused Send is not inset 24 points inside the unified input'
assert abs(attach_center[1] - send_center[1]) <= 1, \
    'Focused Add and Send do not share a baseline'
assert model['x'] + model['width'] <= send['x'] + 1, \
    'Focused model selector moved away from the trailing side'
ui.capture('merged')
print('PASS: iOS 26 focus merges Add into one balanced glass while Model stays trailing')
