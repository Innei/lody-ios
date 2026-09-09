"""Exercise the production notification settings with resettable service outcomes."""
import sys

import catalog
from driver import UI
ui = UI(sys.argv[1], sys.argv[2])

def text(value):
    return ui.wait(lambda items: next((i for i in items if value in str(i.get('AXLabel', ''))), None), f'Missing {value}')

def tap(value):
    node = text(value)
    frame = node['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2))

text(catalog.text('notifications.hint.default'))
text(catalog.text('settings.liveActivity.disabled'))
ui.capture('permission-undetermined')
tap(catalog.text('settings.liveActivity.title'))
ui.element('notification-settings-opened')
ui.axe('tap', '--id', 'notification-reset')
text(catalog.text('notifications.hint.default'))
tap(catalog.text('notifications.permission.turnOn'))
text(catalog.text('notifications.hint.denied'))
ui.capture('permission-denied')
tap(catalog.text('notifications.permission.settings'))
ui.element('notification-settings-opened')
text(catalog.text('notifications.hint.authorized'))
ui.capture('permission-authorized')
ui.axe('tap', '--id', 'notification-reset')
text(catalog.text('notifications.hint.default'))
ui.capture('reset')
