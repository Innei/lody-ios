"""Offline production chat pinning, fork state/recovery, unread grouping and archive preferences."""
import json
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def visible(identifier, items=None):
    return any(item.get('AXUniqueId') == identifier for item in (items or ui.state()))


def tap(identifier):
    row = ui.element(identifier)
    assert row['frame']['height'] >= 44, (identifier, row['frame'])
    ui.axe('tap', '--id', identifier, '--post-delay', '.25')


def hold(identifier):
    frame = ui.element(identifier)['frame']
    ui.axe('touch', '-x', str(frame['x'] + frame['width'] - 35),
           '-y', str(frame['y'] + frame['height'] / 2), '--down', '--up', '--delay', '.8')


def back():
    ui.axe('tap', '--id', 'BackButton', '--post-delay', '.25')
    ui.element('tools-pin')


def target():
    ui.wait(lambda items: next((item for item in items
            if item.get('AXUniqueId') == 'chat-navigation-title'
            and 'Forked conversation' in (item.get('AXLabel') or '')), None),
            'Fork did not open the destination through session navigation')


def choose_pin():
    item = ui.wait(lambda items: next((item for item in items
                   if item.get('AXLabel') == catalog.text('native.chat.pin')), None),
                   'Replacement pin action missing')
    frame = item['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2),
           '-y', str(frame['y'] + frame['height'] / 2),
           '--tap-style', 'physical', '--post-delay', '.05')


def capture_pin_refusal(name):
    items = ui.wait(lambda items: items if visible('lody.toast', items) else None,
                    'Pin rejection feedback missing')
    toast = next(item for item in items if item.get('AXUniqueId') == 'lody.toast')
    assert toast.get('AXLabel') == catalog.text('session.toast.contentPinFailed'), toast
    pin = next(item for item in items if item.get('AXUniqueId') == 'chat-pinned-message')
    assert 'Message 0:' in (pin.get('AXLabel') or ''), 'Rejected pin replaced the original: ' + str(pin)
    ui.screenshot(name)
    roots = [item for item in items if item.get('type') == 'Application']
    (ui.output / f'{name}.json').write_text(json.dumps(roots))


def fork_requests():
    row = ui.element('tools-fork-count')
    values = [child.get('AXLabel') for child in row.get('children', [])
              if child.get('type') == 'StaticText' and (child.get('AXLabel') or '').isdecimal()]
    assert len(values) == 1, row
    return values[0]


ui.element('tools-pin')
tap('tools-pin')
hold('tools-0:user')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('native.chat.pin') for item in items), 'Pin action missing')
ui.capture('message-pin-menu')
ui.axe('tap', '--label', catalog.text('native.chat.pin'), '--post-delay', '.25')
pin = ui.element('chat-pinned-message')
assert 'Message 0:' in (pin.get('AXLabel') or ''), pin
tap('chat-pinned-message')
ui.element('tools-0:user')
ui.capture('message-pinned')
tap('chat-pinned-message:unpin')
ui.wait(lambda items: not visible('chat-pinned-message', items), 'Pin did not clear')
back()

tap('tools-pin-failure')
pin = ui.element('chat-pinned-message')
assert 'Message 0:' in (pin.get('AXLabel') or ''), pin
hold('tools-2:user')
choose_pin()
capture_pin_refusal('message-pin-rejected-keeps-original')
ui.wait(lambda items: not visible('lody.toast', items), 'Pin error did not dismiss')
hold('tools-2:user')
choose_pin()
ui.wait(lambda items: any(item.get('AXUniqueId') == 'chat-pinned-message'
        and 'Message 2:' in (item.get('AXLabel') or '') for item in items),
        'Explicit retry did not replace the pin after acknowledgement')
ui.capture('message-pin-explicit-retry')
tap('chat-pinned-message:unpin')
ui.wait(lambda items: not visible('chat-pinned-message', items), 'Retried pin did not clear')
back()

tap('tools-pin-failure')
assert 'Message 0:' in (ui.element('chat-pinned-message').get('AXLabel') or '')
hold('tools-2:user')
choose_pin()
capture_pin_refusal('message-pin-failure-reset')
ui.wait(lambda items: not visible('lody.toast', items), 'Reset pin error did not dismiss')
back()

tap('tools-old-pin')
pin = ui.element('chat-pinned-message')
assert catalog.text('native.chat.loadPinned') in (pin.get('AXLabel') or ''), pin
assert not visible('tools-0:user'), 'Old source must begin outside the visible history window'
ui.capture('older-pin-before-load')
tap('chat-pinned-message')
ui.element('tools-0:user')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'chat-pinned-message'
        and 'Message 0:' in (item.get('AXLabel') or '') for item in items),
        'Loaded pin preview did not update')
ui.capture('older-pin-loaded')
tap('chat-pinned-message:unpin')
ui.wait(lambda items: not visible('chat-pinned-message', items), 'Old pin did not clear')
back()

tap('tools-fork')
tap('fork-start')
ui.element('fork-state')
ui.capture('fork-preparing')
target()
ui.capture('fork-opened')
back()

tap('tools-dirty-fork')
tap('fork-worktree')
tap('fork-start')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('session.fork.dirty') for item in items), 'Dirty-worktree confirmation missing')
ui.capture('fork-dirty-confirmation')
tap('fork-confirm')
target()
ui.capture('fork-worktree-opened')
back()
assert fork_requests() == '2', 'Dirty confirmation should submit exactly twice'

tap('tools-unknown-fork')
tap('fork-start')
ui.element('fork-check')
assert not visible('fork-start'), 'Unknown outcome must offer a status check without another write'
ui.capture('fork-unknown')
tap('fork-check')
ui.element('fork-check')
assert not visible('fork-start')
ui.axe('tap', '--label', catalog.text('common.cancel'), '--post-delay', '.25')
ui.element('tools-pin')
assert fork_requests() == '1', 'Checking and cancellation must not replay the fork'
ui.capture('fork-unknown-cancelled')

tap('tools-failed-fork')
tap('fork-start')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('session.fork.failed') for item in items), 'Known rejection missing')
ui.capture('fork-failed')
tap('fork-start')
target()
ui.capture('fork-explicit-retry')
back()

tap('tools-unread')
hold('tools-receipt')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('session.action.unread') for item in items), 'Mark unread menu missing')
ui.axe('tap', '--label', catalog.text('session.action.unread'), '--post-delay', '.25')
ui.wait(lambda items: any(item.get('type') == 'Heading'
        and item.get('AXLabel') == catalog.text('inbox.section.unread') for item in items),
        'Unread session did not move to its Inbox group')
ui.capture('marked-unread')
hold('tools-receipt')
ui.axe('tap', '--label', catalog.text('session.action.read'), '--post-delay', '.25')
ui.wait(lambda items: not any(item.get('type') == 'Heading'
        and item.get('AXLabel') == catalog.text('inbox.section.unread') for item in items),
        'Read session did not leave the unread group')
ui.capture('marked-read')
back()

tap('tools-auto-archive')
for identifier in ('auto-archive-merged:toggle', 'auto-archive-closed:toggle'):
    assert ui.element(identifier).get('AXValue') == '0', identifier
    assert ui.element(identifier.removesuffix(':toggle'))['frame']['height'] >= 44
    ui.axe('tap', '--id', identifier, '--post-delay', '.25')
    ui.wait(lambda _: ui.element(identifier).get('AXValue') == '1', 'Archive preference did not change')
ui.capture('auto-archive-enabled')
for identifier in ('auto-archive-merged:toggle', 'auto-archive-closed:toggle'):
    ui.axe('tap', '--id', identifier, '--post-delay', '.25')
    ui.wait(lambda _: ui.element(identifier).get('AXValue') == '0', 'Archive preference did not restore')
ui.capture('auto-archive-restored')
print('PASS: pin rejection retains the original, explicit retry and reset, pinned history including older rows; fork preparation, confirmation, explicit retry and unknown recovery; unread grouping; archive preferences')
