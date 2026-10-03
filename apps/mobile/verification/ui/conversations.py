"""Child tabs switch in place, side chats open as sheets, and tabs/side chats can be created and forked."""
import json
import sys
import time
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])


def probe():
    return json.loads(ui.element('conversation-probe').get('AXValue') or '{}')


def wait_probe(check, message):
    ui.wait(lambda items: check(json.loads(next((i.get('AXValue') or '{}') for i in items if i.get('AXUniqueId') == 'conversation-probe'))), message)


def labelled(prefix):
    def smallest(items):
        hits = [i for i in items if (i.get('AXLabel') or '').startswith(prefix) and i.get('frame')]
        return min(hits, key=lambda i: i['frame']['width'] * i['frame']['height'], default=None)
    return ui.wait(smallest, f'Missing element labelled {prefix!r}')


def tap_frame(item, delay='.8'):
    frame = item['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', delay)


def tap_row(identifier):
    frame = ui.element(identifier)['frame']
    assert frame['height'] >= 44, frame
    ui.axe('tap', '-x', str(frame['x'] + min(140, frame['width'] / 2)), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1')


def open_sheet():
    tap_frame(labelled('Conversations'), '1.2')
    ui.element('main')


def dismiss_sheet():
    ui.axe('swipe', '--start-x', '200', '--start-y', '140', '--end-x', '200', '--end-y', '820', '--duration', '0.3', '--post-delay', '1.2')


assert probe()['active'] == 'main'
ui.capture('main')

def expand_sheet():
    grabber = ui.element('main')['frame']['y'] - 90
    ui.axe('swipe', '--start-x', '200', '--start-y', str(grabber), '--end-x', '200', '--end-y', '90', '--duration', '0.4', '--post-delay', '1')


open_sheet()
for identifier in ['main', 'tests', 'explore', 'new-tab']:
    ui.element(identifier)
ui.capture('sheet')
expand_sheet()
for identifier in ['cookie', 'new-side-chat', 'legacy']:
    ui.element(identifier)
ui.capture('sheet-expanded')

tap_row('tests')
wait_probe(lambda p: p.get('active') == 'tests', 'Selecting a tab must switch in place')
labelled('Refactor tests')
ui.capture('child-tab')

open_sheet()
tap_row('cookie')
labelled('Side Chat')
assert probe()['active'] == 'tests', 'Opening a side chat must not switch the tab'
ui.capture('side-chat')
dismiss_sheet()

open_sheet()
tap_row('new-tab')
wait_probe(lambda p: p.get('active', '').startswith('draft-'), 'New Tab must open a draft tab')
labelled('Review the changes on this branch')
ui.capture('draft-tab')

open_sheet()
tap_row('main')
wait_probe(lambda p: p.get('active') == 'main', 'Main must be selectable again')
before = len(probe()['sessions'])
ui.axe('tap', '--id', 'm2:meta:actions', '--post-delay', '1')
side = labelled('Ask on the Side')
labelled('Fork to New Tab')
labelled('Fork to New Worktree')
ui.capture('fork-menu')
tap_frame(side, '0.5')
labelled('Side Chat')
wait_probe(lambda p: len(p.get('sessions', [])) == before + 1, 'Forking must add one side chat')
ui.capture('forked-side-chat')
dismiss_sheet()

for _ in range(3):
    tap_frame(labelled('Fixture controls'), '1.2')
    if any((i.get('AXLabel') or '').startswith('Mac offline') for i in ui.state()):
        break
tap_frame(labelled('Mac offline'), '1')
ui.axe('tap', '--id', 'm2:meta:actions', '--post-delay', '1')
offline = labelled('Ask on the Side')
assert 'MacBook Pro is offline' in (offline.get('AXLabel') or ''), offline.get('AXLabel')
ui.capture('fork-offline')
ui.axe('tap', '-x', '200', '-y', '120', '--post-delay', '1')

open_sheet()
expand_sheet()
row = ui.element('new-side-chat')
assert 'MacBook Pro is offline' in json.dumps(row), row
frame = ui.element('cookie')['frame']
y = str(frame['y'] + frame['height'] / 2)
ui.axe('swipe', '--start-x', '330', '--start-y', y, '--end-x', '120', '--end-y', y, '--duration', '0.3', '--post-delay', '1')
ui.capture('swipe-delete')
swipe_delete = ui.wait(lambda items: next((i for i in items if i.get('AXLabel') == 'Delete' and i.get('frame', {}).get('height', 0) >= 30), None), 'Missing swipe delete action')
tap_frame(swipe_delete, '1')
alert = ui.wait(lambda items: next((i for i in items if i.get('AXLabel') == 'Delete this side chat?' and i.get('type') == 'Sheet'), None), 'Missing delete alert')['frame']
confirm = ui.wait(
    lambda items: next(
        (
            i for i in items
            if i.get('AXLabel') == 'Delete' and i.get('type') == 'Button' and i.get('frame')
            and alert['y'] <= i['frame']['y'] <= alert['y'] + alert['height']
        ),
        None,
    ),
    'Missing delete confirmation',
)
tap_frame(confirm, '1.5')
wait_probe(lambda p: 'cookie' not in p.get('sessions', []), 'Deleting must remove the side chat')
ui.capture('deleted')
print('Tabs switch in place, side chats open as sheets, New Tab drafts, reply forks, offline gating and side chat deletion all work in both appearances.')
