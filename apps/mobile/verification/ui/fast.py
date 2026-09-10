"""Fast in both native composer hosts keeps its value through the RN round trip."""
import sys
import time
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
field = 'create-session-input' if 'fast-sheet' in str(ui.output) else 'session-input'
def tap(identifier):
    ui.element(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.5')
def state(enabled):
    value = catalog.text('native.chat.composer.fastOn' if enabled else 'native.chat.composer.fastOff')
    return ui.wait(lambda _: ui.element('composer-fast') if ui.element('composer-fast').get('AXValue') == value else None, 'Fast state did not return from RN')

tap(field)
tap('session-model')
state(False)
frame = ui.element('composer-fast')['frame']
assert frame['width'] >= 44 and frame['height'] >= 44, 'Fast must have a 44 pt touch target'
ui.capture('off')
tap('composer-fast')
state(True)
ui.capture('on')
# Wait with the view on screen to record the non-Ultra Fast animation.
time.sleep(1)
ui.capture('flow')
ui.axe('tap', '-x', '20', '-y', '160', '--post-delay', '.5')
tap('session-model')
state(True)
ui.capture('reopened')
if field == 'session-input':
    slider = ui.element('composer-effort-slider')['frame']
    ui.axe('tap', '-x', str(slider['x'] + slider['width'] - 16), '-y', str(slider['y'] + slider['height']/2), '--post-delay', '1')
    assert 'Ultra' in ui.element('composer-model-menu')['AXLabel']
    state(True)
    ui.capture('ultra-fast')
tap('composer-fast')
state(False)
ui.capture('disabled')
print('PASS: Fast toggle, 44 pt target, RN echo, reopen and disabling in native composer host')
