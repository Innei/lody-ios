"""Resolve inherited model/effort in chat and creation without changing inheritance."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def foreground(identifier):
    return ui.wait(lambda items: next((i for i in reversed(items) if i.get('AXUniqueId') == identifier), None),
                   f'Missing foreground {identifier}')


def tap(identifier):
    f = foreground(identifier)['frame']
    ui.axe('tap', '-x', str(f['x'] + f['width'] / 2), '-y', str(f['y'] + f['height'] / 2), '--post-delay', '.4')


def contains(identifier, *values):
    def matches(items):
        return next((i for i in reversed(items) if i.get('AXUniqueId') == identifier
                     and all(value in (i.get('AXLabel') or '') for value in values)), None)
    return ui.wait(matches, f'{identifier} must reveal {values}')


def effort(fraction):
    f = foreground('composer-effort-slider')['frame']
    ui.axe('tap', '-x', str(f['x'] + 16 + fraction * (f['width'] - 32)),
           '-y', str(f['y'] + f['height'] / 2), '--post-delay', '.4')


tap('session-input')
contains('session-model', 'Agent Model', 'Medium')
tap('session-model')
contains('composer-model-menu', 'Agent Model', 'Medium')
ui.capture('chat-inherited')
tap('composer-model-menu')
ui.axe('tap', '--label', 'Alternate Model', '--element-type', 'Button', '--post-delay', '.4')
contains('composer-model-menu', 'Alternate Model', 'Medium')
tap('composer-model-menu')
ui.axe('tap', '--label', catalog.format_value(catalog.text('model.followAgent'), ['Agent Model']), '--post-delay', '.4')
contains('composer-model-menu', 'Agent Model', 'Medium')
effort(1)
contains('composer-model-menu', 'High')
effort(0)
contains('composer-model-menu', 'Agent Model', 'Medium')
ui.capture('chat-restored')

# Re-enter a fresh fixture; no popover or keyboard state crosses host boundaries.
ui.open_case('model-memory')
contains('model', catalog.text('model.unavailable'))
tap('agent')
tap('ui:claude')
contains('model', 'Claude', 'low')
ui.capture('create-inherited-summary')
tap('create-session-input')
contains('session-model', 'Claude', 'Low')
tap('session-model')
contains('composer-model-menu', 'Claude', 'Low')
ui.capture('create-inherited')
effort(1)
contains('composer-model-menu', 'High')
effort(0)
contains('composer-model-menu', 'Claude', 'Low')
ui.capture('create-restored')
print('PASS: actual inherited model/effort, explicit overrides and restoration in chat and creation; unavailable model is explicit')
