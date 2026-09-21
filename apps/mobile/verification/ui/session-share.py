"""Publish only after confirmation; failed upload, retry, update, reset and revoke offline."""
import subprocess
import sys
from driver import UI

ui = UI(*sys.argv[1:])

def tap(identifier):
    ui.axe('tap', '--id', identifier, '--post-delay', '.4')

def wait(identifier):
    ui.wait(lambda items: any(i.get('AXUniqueId') == identifier for i in items), f'Missing {identifier}', timeout=20)

def pasted():
    return subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True).strip()

def confirm(label):
    sheet = ui.wait(lambda items: next((i for i in items if i.get('role') == 'AXSheet' and i.get('AXLabel') == label), None), 'Confirmation missing')
    def walk(node):
        yield node
        for child in node.get('children', []):
            yield from walk(child)
    button = next(i for i in walk(sheet) if i.get('type') == 'Button' and i.get('AXLabel') == label)
    frame = button['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.6')

tap('open-session-share')
wait('share-publish')
assert not any(i.get('AXUniqueId') == 'share-copy' for i in ui.state())
ui.capture('scope-before-publication')
tap('share-include-children')
tap('share-publish')
wait('share-progress')
ui.capture('publication-progress')
wait('share-reload')
assert not any(i.get('AXUniqueId') == 'share-copy' for i in ui.state())
ui.capture('upload-failure-no-link')
tap('share-reload')
wait('share-copy')
assert 'fixture-v1' in pasted()
ui.capture('published-link')
tap('share-publish')
wait('share-progress')
wait('share-copy')
assert 'fixture-v1' in pasted(), 'Updating changed the link'
tap('share-system')
wait('ActivityListView')
ui.capture('system-share')
frame = ui.element('ActivityListView')['frame']
ui.axe('tap', '-x', '20', '-y', str(max(50, frame['y'] - 40)), '--post-delay', '.6')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'ActivityListView' for i in items), 'System share did not dismiss')
tap('share-reset')
ui.axe('tap', '--label', 'Cancel')
tap('share-copy')
assert 'fixture-v1' in pasted()
tap('share-reset')
confirm('Reset link')
tap('share-copy')
assert 'fixture-v2' in pasted()
ui.capture('reset-link')
tap('share-revoke')
confirm('Revoke share')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'share-copy' for i in items), 'Revoked link is still offered')
ui.capture('revoked')
ui.axe('tap', '--label', 'Done', '--post-delay', '.6')
wait('open-session-share')
print('PASS: scope, publishing progress, failure without a link, retry, stable update, system sharing, reset cancellation, rotation and revocation')
