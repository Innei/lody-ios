"""A visible native close action revokes once, preserves failure/draft, and hides candidates."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def status(create=0, revoke=0, opened=0):
    label = f'Create: {create} · Revoke: {revoke} · Open: {opened} · Copy: 0'
    return ui.wait(lambda items: any(i.get('AXUniqueId') == 'preview-fixture-status' and i.get('AXLabel') == label for i in items), f'Missing {label}')


def hidden(identifier):
    ui.wait(lambda items: not any(i.get('AXUniqueId') == identifier for i in items), f'{identifier} did not leave')


def close(label):
    return ui.wait(lambda items: next((i for i in items if i.get('AXUniqueId') == 'session-preview-close' and i.get('AXLabel') == label), None), f'Missing visible {label}')


def reset():
    ui.axe('tap', '--id', 'preview-reset')
    status()
    close(catalog.text('session.preview.stop'))


reset()
chip = ui.element('session-preview')
button = close(catalog.text('session.preview.stop'))
assert button['frame']['width'] >= 44, button['frame']
assert button['frame']['x'] >= chip['frame']['x'] + chip['frame']['width'], 'Close must be a separate action beside the address'
ui.capture('visible-close')
ui.axe('tap', '--id', 'session-preview')
status(create=1, opened=1)
ui.capture('opened')
ui.axe('tap', '--id', 'session-input')
ui.type_into('session-input', 'Keep this draft')
draft = ui.element('session-input').get('AXValue')
compact = ui.wait(lambda items: next((i for i in items if i.get('AXUniqueId') == 'session-preview' and abs(i['frame']['width'] - i['frame']['height']) < 2), None), 'Typing did not collapse the address')
button = close(catalog.text('session.preview.stop'))
assert button['frame']['x'] > compact['frame']['x'] + compact['frame']['width'], 'Typing obscured close'
ui.capture('compact-close')
# Hit the expanded 44 pt vertical touch area outside the visible capsule.
frame = button['frame']
ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] + 2))
status(create=1, revoke=1, opened=1)
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-preview-close' and not i.get('enabled', True) for i in items), 'Close stayed enabled during revoke')
pending = ui.element('session-preview-close')['frame']
ui.axe('tap', '-x', str(pending['x'] + pending['width'] / 2), '-y', str(pending['y'] + pending['height'] / 2))
status(create=1, revoke=1, opened=1)
ui.capture('stopping')
ui.axe('tap', '--id', 'preview-fail')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('session.preview.stopFailed') for i in items), 'Revoke failure did not explain the result')
ui.wait(lambda items: any(i.get('AXLabel') == 'The machine did not stop sharing.' for i in items), 'Machine failure message missing')
ui.capture('failed-retained')
ui.axe('tap', '--label', catalog.system('ok'))
assert close(catalog.text('session.preview.stop')).get('enabled', True)
assert ui.element('session-input').get('AXValue') == draft, 'Failure changed the draft'
ui.axe('tap', '--id', 'session-preview-close')
status(create=1, revoke=2, opened=1)
ui.axe('tap', '--id', 'preview-succeed')
hidden('session-preview-close')
hidden('session-preview')
assert ui.element('session-input').get('AXValue') == draft, 'Successful stop changed the draft'
ui.capture('stopped-hidden')
ui.axe('tap', '--id', 'preview-reactivate')
close(catalog.text('session.preview.stop'))
ui.capture('reshared')

reset()
ui.axe('tap', '--id', 'preview-candidate')
close(catalog.text('session.preview.dismiss'))
ui.capture('candidate-close')
ui.axe('tap', '--id', 'session-preview-close')
hidden('session-preview')
status()
ui.capture('candidate-hidden')
ui.axe('tap', '--id', 'preview-target')
close(catalog.text('session.preview.dismiss'))
assert ui.element('session-preview')['AXLabel'] == catalog.text('session.preview.open', target='localhost:52921')
ui.capture('new-target')

reset()
ui.axe('tap', '--id', 'preview-combine')
assert ui.element('session-preview')['AXLabel'] == catalog.text('session.context.count', count=2)
close(catalog.text('session.preview.stop'))
ui.capture('combined-resources')
ui.axe('tap', '--id', 'session-preview-close')
status(revoke=1)
ui.axe('tap', '--id', 'preview-succeed')
hidden('session-preview-close')
assert ui.element('session-preview')['AXLabel'] == 'Open Simulator preview', 'Stopping URL preview also hid the Simulator'
ui.capture('simulator-retained')
print('PASS: visible 44 pt close, ordinary opening, compact draft, one pending revoke, failure/retry, candidate hiding and combined-resource routing.')
