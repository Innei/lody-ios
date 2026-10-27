"""Native read-only session page: cached then live transcript, title menu, header actions, find, offline reconnect and deletion return."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
more = catalog.text('common.more')


def spoken(item):
    return ' '.join([str(item.get(key) or '') for key in ('AXLabel', 'AXValue')] + [spoken(child) for child in item.get('children') or []])


def probe(items=None):
    match = next((i for i in items or ui.state() if i.get('AXUniqueId') == 'session-preview-probe'), None)
    return (match or {}).get('AXValue') or ''


def wait_probe(entry, message):
    ui.wait(lambda items: entry in probe(items).split(','), message)


def wait_text(text):
    ui.wait(lambda items: any(text in spoken(i) for i in items), f'Missing {text}')


def tap_label(label):
    ui.wait(lambda items: any(i.get('AXLabel') == label for i in items), f'Missing {label}')
    ui.axe('tap', '--label', label, '--post-delay', '.6')


def tap_menu_item(title):
    # Menu items with a subtitle expose "title, subtitle" as one label.
    item = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').startswith(title)), None), f'Missing {title}')
    frame = item['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.6')


wait_probe('live', 'Live envelope was not delivered')
wait_text('Live reply with a needle')
assert not any('Cached reply' in spoken(i) for i in ui.state()), 'The live revision must replace the cached history'
title = ui.element('chat-navigation-title')
assert 'Native session preview' in spoken(title), title
wait_text('src/App.tsx')
ui.capture('live')

ui.axe('tap', '--id', 'preview-answer:meta:details', '--post-delay', '.5')
assert 'Native fixture model' in spoken(ui.element('model'))
ui.capture('message-details')
tap_label(catalog.text('common.done'))
assert probe().split(',').count('watch') == 1, 'Opening details started another runtime subscription'
assert 'unwatch' not in probe().split(','), 'Closing details stopped the owning session feed'


ui.axe('tap', '--id', 'chat-navigation-title', '--post-delay', '.6')
tap_menu_item(catalog.text('session.title.copyBranch'))
wait_text(catalog.text('session.title.branchCopied'))

tap_label(more)
tap_label(catalog.text('session.action.archive'))
wait_probe('archive', 'Archive did not reach the session service')
tap_label(more)
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('session.action.unarchive') for i in items), 'Archive state did not refresh the menu')
ui.capture('archived-menu')
tap_label(catalog.text('session.action.unarchive'))
wait_probe('unarchive', 'Unarchive did not reach the session service')

tap_label(more)
tap_label(catalog.text('session.action.find'))
ui.element('chat-find-field')
ui.axe('type', 'needle')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'chat-find-count' and (i.get('AXLabel') or i.get('AXValue')) for i in items), 'Find did not match the transcript')
ui.capture('find')
ui.axe('tap', '--id', 'chat-find-close', '--post-delay', '.5')

tap_label(more)
tap_label(catalog.text('session.action.delete'))
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('session.delete.title') for i in items), 'Missing deletion confirmation')
buttons = [i for i in ui.state() if i.get('type') == 'Button' and i.get('AXLabel') == catalog.text('session.action.delete')]
frame = max(buttons, key=lambda i: i['frame']['y'])['frame']
ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.5')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'session-preview-probe' for i in items), 'Deleted session page did not return', timeout=10)

ui.open_case('session-preview-offline')
wait_probe('offline', 'Offline scenario did not start')
ui.element('chat-overlay-status')
ui.capture('offline')
ui.axe('tap', '--id', 'chat-overlay-status', '--post-delay', '.5')
wait_probe('reconnect', 'Reconnect did not reach the session feed')
wait_text('Live reply with a needle')

ui.open_case('session-preview-find')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'chat-find-field' and 'needle' in (i.get('AXValue') or '') for i in items), 'Find query did not open the find bar')
ui.capture('find-query')

print('PASS: native session page renders cached then live history, title and header actions, find, deletion return, offline reconnect and an incoming find query.')
