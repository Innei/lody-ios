"""The composer context chip morphs between preview states in place and yields to typing and work."""
import sys
from driver import UI

ui = UI(*sys.argv[1:])


def replies(items=None):
    return [i for i in (items or ui.state()) if (i.get('AXUniqueId') or '').startswith('quick-reply:') and i['frame']['height'] > 0]


def chip(predicate, message):
    return ui.wait(lambda items: next((i for i in items if i.get('AXUniqueId') == 'session-preview' and predicate(i)), None), message)


def cycle(label):
    ui.axe('tap', '--id', 'quick-preview', '--post-delay', '.8')
    return chip(lambda i: i.get('AXLabel') == label, f'Context chip did not show {label}')


ui.axe('tap', '--id', 'quick-reset', '--post-delay', '.8')
ui.element('quick-reply:continue')
assert not any(i.get('AXUniqueId') == 'session-preview' for i in ui.state()), 'The fixture starts without a resource'
widths = {}
for step, label in enumerate(['Connecting…', 'localhost:5173', 'iPhone 17 Pro', 'Preview Unavailable']):
    frame = cycle(label)['frame']
    widths[label] = frame['width']
    first = min(replies(), key=lambda i: i['frame']['x'])['frame']
    assert 32 <= frame['height'] <= 40, frame
    assert first['x'] - frame['x'] - frame['width'] > 12, 'A separator must divide the context chip from suggestions'
    ui.capture(f'state-{step}')
assert len(set(widths.values())) > 2, f'The context chip must follow its label width: {widths}'

ui.axe('tap', '--id', 'quick-preview', '--post-delay', '.8')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'session-preview' for i in items), 'Context chip did not leave')
cycle('Connecting…')
cycle('localhost:5173')

ui.axe('tap', '--id', 'session-input')
ui.type_into('session-input', 'draft')
compact = chip(lambda i: abs(i['frame']['width'] - i['frame']['height']) < 2, 'Typing did not collapse the context chip')
assert not replies(), 'Suggestions must leave while typing'
ui.capture('typing')
for _ in range(5):
    ui.axe('key', '42')
chip(lambda i: i['frame']['width'] > compact['frame']['width'] + 40, 'Clearing the draft did not restore the label')
ui.wait(lambda items: len(replies(items)) == 3, 'Suggestions did not return')
ui.capture('restored')

ui.axe('tap', '--id', 'quick-running', '--post-delay', '.8')
ui.wait(lambda items: not replies(items), 'Suggestions must leave while the agent works')
chip(lambda i: i.get('AXLabel') == 'localhost:5173', 'Work must keep the context chip')
ui.capture('running')
print('PASS: context chip morphs in place, compacts while typing and survives work')
