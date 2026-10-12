"""Offline Provider management exercises production pages and deterministic remote outcomes."""
import json
import sys
from driver import UI
import catalog
from project_geometry import viewport, visible_target, scroll_direction, scroll_points

ui = UI(sys.argv[1], sys.argv[2])


def spoken(item):
    return ' '.join(str(item.get(key) or '') for key in ('AXLabel', 'AXValue'))


def tap(identifier):
    ui.element(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.4')


def toolbar(key):
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == catalog.text(key)
                                    and item.get('type') == 'Button'), None), f'Missing {key}')


def save():
    save_frame = toolbar('providers.save')['frame']
    cancel_frame = toolbar('common.cancel')['frame']
    assert abs(save_frame['y'] - cancel_frame['y']) < 10, 'Save must stay in the native navigation bar'
    ui.axe('tap', '--label', catalog.text('providers.save'), '--post-delay', '.5')


def reveal(identifier, upward=True):
    toolbar_labels = {catalog.text(key) for key in ('providers.save', 'common.cancel', 'common.done', 'providers.refresh')}
    for _ in range(12):
        items = ui.state()
        bounds = viewport(items, toolbar_labels)
        node = next((item for item in items if item.get('AXUniqueId') == identifier), None)
        if visible_target(node, bounds):
            return node
        direction = scroll_direction(node, bounds, 'down' if upward else 'up')
        start, end = scroll_points(direction, bounds)
        app = next(item for item in items if item.get('type') == 'Application')
        # The outer ScrollView's 16 pt content inset stays outside every text input.
        # Starting inside the focused environment UITextView scrolls that input instead.
        gutter = str(app['frame']['x'] + 8)
        ui.axe('swipe', '--start-x', gutter, '--start-y', str(start), '--end-x', gutter,
               '--end-y', str(end), '--duration', '.4', '--post-delay', '.3')
    raise AssertionError(f'Could not reveal {identifier}')


def text_state(identifier, key):
    ui.wait(lambda items: any(item.get('AXUniqueId') == identifier and catalog.text(key) in spoken(item)
                             for item in items), f'Missing {key} on {identifier}')


def close_operation():
    toolbar('common.done')
    ui.axe('tap', '--label', catalog.text('common.done'), '--post-delay', '.5')


ui.element('provider:m1:claude')
assert toolbar('providers.refresh')['frame']['y'] < 110, 'Refresh must belong to the production push-host native navigation bar'
ui.axe('tap', '--label', catalog.text('providers.refresh'), '--post-delay', '.3')
ui.element('provider:m1:claude')
assert catalog.text('providers.failed') in spoken(ui.element('provider:m1:pi-task'))
ui.capture('providers-and-task')
tap('provider:m1:large-desktop')
text_state('provider-over-limit', 'providers.overLimit')
assert not any(item.get('AXUniqueId') == 'provider-name' for item in ui.state()), 'Large desktop configuration must not enter a truncating editor'
assert not toolbar('providers.save')['enabled'], 'Large desktop configuration must not be saved through the bounded editor'
assert any(catalog.text('providers.manageOnDesktopHint', machine='Studio Mac') in spoken(item)
           for item in ui.state()), 'Read-only configuration needs a desktop-management path'
ui.capture('large-desktop-read-only')
ui.axe('tap', '--label', catalog.text('common.cancel'), '--post-delay', '.4')
tap('provider:m1:claude')
tap('provider-name')
ui.axe('type', ' Mobile')
name = ui.element('provider-name')['AXValue']
save()
assert catalog.text('providers.saveFailed') in spoken(ui.element('lody.toast'))
assert ui.element('provider-name')['AXValue'] == name, 'Failed save must retain the draft'
ui.capture('save-failure-draft')
save()
ui.wait(lambda items: any(item.get('AXUniqueId') == 'provider:m1:claude' and name in spoken(item)
                         for item in items), 'Rename did not reach provider list')
tap('provider:m1:claude')
assert ui.element('provider-name')['AXValue'] == name
tap('provider-name')
ui.axe('type', ' ')
reveal('provider-verify')
tap('provider-verify')
ui.element('provider-model:fixture-model')
ui.capture('verified-models')
close_operation()
text_state('provider-verification-state', 'providers.verified')
assert not any(catalog.text('providers.conflict') in spoken(item) for item in ui.state()), 'Machine field normalization must not be treated as another client’s edit'
reveal('provider-env', upward=False)
tap('provider-env')
ui.axe('type', 'EXTRA=1')
reveal('provider-verification-state')
text_state('provider-verification-state', 'providers.unverified')
ui.capture('verification-invalidated')

reveal('provider-authenticate')
tap('provider-authenticate')
tap('provider-auth-field:apiKey')
ui.axe('type', 'fixture-key')
tap('provider-submit-auth')
text_state('provider-operation-state', 'providers.completed')
ui.capture('authenticated')
close_operation()
reveal('provider-install')
tap('provider-install')
ui.element('provider-operation-progress')
ui.capture('install-progress')
ui.element('provider-operation-retry')
ui.capture('install-failure')
tap('provider-operation-retry')
text_state('provider-operation-state', 'providers.completed')
ui.capture('install-retried')
close_operation()
ui.axe('tap', '--label', catalog.text('common.cancel'), '--post-delay', '.5')

tap('provider:m1:pi-task')
reveal('provider-retry-setup')
tap('provider-retry-setup')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'provider:m1:pi-task' and catalog.text('providers.queued') in spoken(item)
                         for item in items), 'Failed task did not become queued')
ui.capture('task-retried')

tap('provider-add:m1')
reveal('provider-choice:custom')
ui.capture('custom-choice')
tap('provider-choice:custom')
tap('provider-command')
ui.axe('type', '/usr/local/bin/custom-acp')
save()
custom = ui.wait(lambda items: next((item for item in items if str(item.get('AXUniqueId', '')).startswith('provider:m1:00000000')
                                   and 'Custom ACP' in spoken(item)), None), 'New custom Provider missing')
assert catalog.text('providers.configured') in spoken(custom), 'Custom Provider must show its configuration state'
assert 'custom-00000000' not in spoken(custom), 'Custom Provider must not display its generated runtime type ID'
custom_id = custom['AXUniqueId']
ui.capture('custom-created')
tap(custom_id)
assert ui.element('provider-command')['AXValue'] == '/usr/local/bin/custom-acp'
reveal('provider-auto-title')
tap('provider-auto-title')
save()
tap(custom_id)
reveal('provider-auto-title')
assert ui.element('provider-auto-title').get('AXValue') == '1', 'Automatic-title setting did not persist'
ui.capture('custom-titles')
reveal('provider-delete')
tap('provider-delete')
toolbar('common.delete')
ui.capture('delete-confirmation')
ui.axe('tap', '--label', catalog.text('common.delete'), '--post-delay', '.5')
ui.element('provider:m1:claude')
assert not any(item.get('AXUniqueId') == custom_id for item in ui.state()), 'Deleted provider stayed in the list'
ui.capture('custom-deleted')

reveal('provider-add:m2')
tap('provider-add:m2')
assert not any(item.get('AXUniqueId') == 'provider-name' for item in ui.state()), 'Another owner’s machine must be read-only'
assert any(catalog.text('providers.readOnly') in spoken(item) for item in ui.state()), 'Read-only restriction needs an explanation'
ui.capture('read-only-machine')
tap('providers-reset')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'provider:m1:claude' and 'Mobile' not in spoken(item)
                         for item in items), 'Preview reset did not restore provider list')
ui.capture('reset')
print(json.dumps({'crud': True, 'failedSaveRetainedDraft': True, 'connectionEditInvalidatedProbe': True,
                  'authentication': True, 'installProgressAndRetry': True, 'taskRetry': True,
                  'automaticTitle': True, 'readOnly': True, 'largeDesktopReadOnly': True, 'reset': True}))
