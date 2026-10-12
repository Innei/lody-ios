"""Native shared queue edit/reorder/delete and uncertain-send recovery stay scoped."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])

def menu(identifier, key):
    ui.axe('tap', '--id', identifier + ':queue-actions')
    ui.wait(lambda items: any(item.get('AXLabel') == catalog.text(key) for item in items), 'Queue action menu missing')
    ui.axe('tap', '--label', catalog.text(key))

def value(identifier):
    return ui.element(identifier).get('AXValue') or ''

def status(fragment):
    return ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-tools-status' and fragment in (item.get('AXLabel') or '') for item in items), 'Fixture status missing: ' + fragment)

def queue_controls_ready(items):
    controls = {item.get('AXUniqueId'): item for item in items}
    for identifier in ('queue-alpha', 'queue-beta'):
        for suffix in ('queued', 'steer', 'queue-actions'):
            item = controls.get(identifier + ':' + suffix, {})
            frame = item.get('frame') or {}
            if not item.get('enabled') or frame.get('height', 0) < 43.99 or frame.get('width', 0) < 43.99:
                return False
    return True

def recovery_confirmation(items):
    sheets = [item for item in items if item.get('type') == 'Sheet'
              and item.get('enabled')
              and item.get('AXLabel') == catalog.text('send.recovery.resumeTitle')]
    if len(sheets) != 1:
        return None

    def descendants(node):
        for child in node.get('children', []):
            yield child
            yield from descendants(child)

    buttons = [item for item in descendants(sheets[0]) if item.get('type') == 'Button'
               and item.get('enabled')
               and item.get('AXLabel') == catalog.text('send.recovery.resume')]
    if len(buttons) != 1:
        return None
    frame = buttons[0].get('frame') or {}
    if frame.get('width', 0) < 44 or frame.get('height', 0) < 44:
        return None
    return buttons[0]

ui.wait(queue_controls_ready, 'Queue controls must be enabled with 44 pt touch targets')
ui.capture('queue-ready')
ui.axe('tap', '--id', 'session-input')
ui.type_into('session-input', 'Independent draft')
ui.wait(queue_controls_ready, 'Typing compressed or disabled the queue controls')
ui.axe('tap', '--id', 'queue-alpha:queued')
ui.element('queue-alpha:queue-editor')
assert value('queue-alpha:queue-editor') == 'Alpha message'
ui.axe('type', ' revised')
edited = value('queue-alpha:queue-editor')
assert 'revised' in edited
ui.capture('queue-edit')
ui.axe('tap', '--id', 'queue-alpha:save-edit')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-alpha:queued' and edited in (item.get('AXLabel') or '') for item in items), 'Saved queue text did not update')
assert value('session-input') == 'Independent draft', 'Queue edit changed the independent composer draft'
assert any('notes.txt' in (item.get('AXLabel') or '') for item in ui.state()), 'Queue edit lost its attachment caption'
ui.capture('queue-saved')

ui.axe('tap', '--id', 'queue-alpha:queued')
ui.element('queue-alpha:queue-editor')
ui.axe('type', ' discarded')
ui.axe('tap', '--id', 'queue-alpha:cancel-edit')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-alpha:queued' and edited in (item.get('AXLabel') or '') and 'discarded' not in (item.get('AXLabel') or '') for item in items), 'Cancelling edit changed the queue text')

ui.axe('tap', '--id', 'queue-tools-fail')
ui.axe('tap', '--id', 'queue-alpha:queued')
ui.element('queue-alpha:queue-editor')
assert value('queue-alpha:queue-editor') == edited, 'Successful cancellation revived its discarded draft'
ui.axe('type', ' retry')
retry = value('queue-alpha:queue-editor')
ui.axe('tap', '--id', 'queue-alpha:save-edit')
status('Fail: false')
ui.element('queue-alpha:queue-editor')
assert value('queue-alpha:queue-editor') == retry, 'Rejected save lost the editor draft'
ui.capture('queue-failed-kept')
ui.axe('tap', '--id', 'queue-alpha:save-edit')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-alpha:queued' and retry in (item.get('AXLabel') or '') for item in items), 'Retry did not save the same queue item')

menu('queue-beta', 'queue.moveUp')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-tools-order' and item.get('AXLabel') == 'queue-beta,queue-alpha' for item in items), 'Move up did not change the shared order')
menu('queue-beta', 'queue.moveDown')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-tools-order' and item.get('AXLabel') == 'queue-alpha,queue-beta' for item in items), 'Move down changed identities or lost a queue item')
ui.capture('queue-reordered')

ui.axe('tap', '--id', 'queue-tools-hold')
menu('queue-beta', 'queue.delete')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-beta:queue-actions' and not item.get('enabled') for item in items), 'Queue delete did not expose pending state')
ui.element('queue-beta:queued')
ui.capture('queue-deleting')
ui.axe('tap', '--id', 'queue-tools-complete')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'queue-tools-order' and item.get('AXLabel') == 'queue-alpha' for item in items), 'Delete changed another queue item')
ui.element('queue-beta:queued')
menu('queue-beta', 'queue.check')
status('Last: check:queue-beta')
ui.capture('queue-delete-unconfirmed')
ui.axe('tap', '--id', 'queue-tools-claim')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'queue-beta:queued' for item in items), 'Machine-owned turn remained falsely deletable')
ui.element('queue-alpha:queued')
ui.capture('queue-claim-race')

ui.axe('tap', '--id', 'queue-tools-unknown')
ui.element('session-send-recovery-check')
status('Send: unknown')
ui.axe('tap', '--id', 'session-send-recovery-check')
ui.element('session-send-recovery-resume')
status('Send: unknown')
ui.capture('send-recovery-unknown')
ui.axe('tap', '--id', 'session-send-recovery-resume')
confirmation = ui.wait(recovery_confirmation, 'Clearing uncertain confirmation did not expose its scoped action')
ui.capture('send-recovery-confirmation')
frame = confirmation['frame']
ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2),
       '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical')
status('Send: idle')
assert value('session-input') == 'Independent draft', 'Clearing uncertain confirmation changed a new draft'
status('Calls: 0')
ui.capture('send-recovery-resumed')

ui.axe('tap', '--id', 'session-send')
status('Calls: 1')
ui.element('session-send-recovery-cancel')
ui.axe('tap', '--id', 'session-send-recovery-cancel')
status('Send: idle')
assert value('session-input') == 'Independent draft', 'Preparation cancellation did not restore the original composer draft'
ui.capture('send-preparation-cancelled')

ui.axe('tap', '--id', 'queue-alpha:steer')
status('Steers: 1')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'queue-alpha:queued' for item in items), 'Steer stopped working after queue edits')
assert value('session-input') == 'Independent draft'
ui.capture('steer-after-queue-tools')
print('PASS: edit/save/cancel, failure draft retention, stable reorder, pending deletion and claim race, read-only confirmation, explicit resume, preparation cancellation, unchanged Steer and independent composer draft')
