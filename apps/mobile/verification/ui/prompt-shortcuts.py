"""Workspace Shortcut management and both production native composer hosts, offline."""
import sys
import time
import json
from driver import UI
import catalog
from project_geometry import viewport, visible_target, scroll_direction, scroll_points

ui = UI(*sys.argv[1:])


def tap(identifier):
    ui.element(identifier)
    ui.axe('tap', '--id', identifier)


def single(identifier):
    ui.element(identifier)
    matches = [item for item in ui.state() if item.get('AXUniqueId') == identifier]
    assert len(matches) == 1, f'Duplicate or missing fixture {identifier}: {len(matches)}'


def reveal(identifier):
    ui.element(identifier)
    toolbar_labels = {catalog.text(key) for key in ('common.save', 'common.cancel')}
    for _ in range(12):
        items = ui.state()
        bounds = viewport(items, toolbar_labels)
        item = next((item for item in items if item.get('AXUniqueId') == identifier), None)
        if visible_target(item, bounds):
            return item
        if not item:
            raise AssertionError(f'Target left the page: {identifier}')
        app = next(item for item in items if item.get('type') == 'Application')['frame']
        direction = scroll_direction(item, bounds, 'down')
        start, end = scroll_points(direction, bounds)
        end = start + max(-80, min(80, end - start))
        assert bounds[0] <= min(start, end) <= max(start, end) <= bounds[1], 'Shortcut drag left the visible content'
        # The outer gutter avoids scrolling inside the multiline text input.
        x = app['x'] + app['width'] - 10
        ui.axe('swipe', '--start-x', str(x), '--start-y', str(start), '--end-x', str(x), '--end-y', str(end), '--duration', '.6', '--post-delay', '.3')
    raise AssertionError(f'Target is not fully visible: {identifier}')


field_sequence = 0


def fill(identifier, value):
    global field_sequence
    field_sequence += 1
    record = {'event': 'shortcut-field-target', 'identifier': identifier, 'sequence': field_sequence}
    try:
        target = reveal(identifier)
        assert target.get('type') in ['TextField', 'TextArea', 'SearchField'], f'Not a typed field: {identifier}'
        assert target.get('enabled', True), f'Typed field is disabled: {identifier}'
        frame = target['frame']
        assert frame['width'] >= 44, f'Typed field has no complete hit region: {identifier}'
        record['target'] = {'id': target['AXUniqueId'], 'frame': frame, 'type': target['type']}
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2))
        focused = ui._focused_input(f'actor-field-{field_sequence}')
        record['focused'] = focused
        assert focused['id'] == identifier, f'Wrong focused field: expected {identifier}, got {focused["id"]}'
        assert focused['firstResponder'], f'Typed field did not become focused: {identifier}'
        items = ui.state()
        bounds = viewport(items, {catalog.text(key) for key in ('common.save', 'common.cancel')})
        assert visible_target(focused, bounds), f'Focused field is outside visible content: {identifier}'
        ui.type_into(identifier, value)
        record['status'] = 'committed'
    except BaseException as error:
        record['status'] = 'rejected'
        record['error'] = str(error)
        raise
    finally:
        with (ui.output / 'field-target.jsonl').open('a') as log:
            log.write(json.dumps(record) + '\n')


def spoken(item):
    return ' '.join(str(item.get(key) or '') for key in ('AXLabel', 'AXValue', 'AXHint'))


def physical_tap(item):
    frame = item['frame']
    assert frame['width'] >= 44 and frame['height'] >= 44, 'Shortcut row has no complete touch target'
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2))


def inline_shortcuts():
    tap('session-input')
    ui.type_into('session-input', '/')
    ui.element('mention-item:compact')
    ui.element('mention-item:shortcut-review')
    ui.capture('chat-inline-slash-discovery')
    tap('mention-item:compact')
    assert ui.element('session-input').get('AXValue', '') == '/compact ', 'Legacy Agent slash selection changed'
    tap('shortcut-composer-reset')
    tap('session-input')
    ui.type_into('session-input', '/review-au')
    ui.element('mention-item:shortcut-review')
    ui.capture('chat-inline-shortcut-slug')
    tap('mention-item:shortcut-review')
    assert '@shortcut:shortcut-review' in ui.element('session-input').get('AXValue', ''), 'Slash selection lost the stable Shortcut ID'
    tap('shortcut-composer-reset')
    tap('session-input')
    ui.type_into('session-input', '/claude-only')
    disabled = ui.element('mention-item:shortcut-other-provider')
    assert not disabled.get('enabled', True), 'An exact disabled Shortcut must stay disabled inline'
    assert catalog.text('settings.promptShortcuts.provider_mismatch') in spoken(disabled), 'Inline Shortcut lost its concrete scope reason'
    panel = ui.element('mention-panel')['frame']
    row = disabled['frame']
    assert row['y'] >= panel['y'] and row['y'] + row['height'] <= panel['y'] + panel['height'], 'The inline scope reason is clipped outside the panel'
    ui.capture('chat-inline-disabled-reason')
    physical_tap(disabled)
    assert ui.element('session-input').get('AXValue', '') == '/claude-only', 'Disabled inline selection changed the draft'
    ui.element('mention-item:shortcut-other-provider')
    assert not any(item.get('AXUniqueId') == 'shortcut-expanded-text' for item in ui.state()), 'Disabled inline Shortcut reached expansion'
    ui.capture('chat-inline-disabled-retained')
    tap('shortcut-composer-reset')


def browse(field):
    tap(field)
    tap('session-mention')
    # There are eight categories in the shared native panel.
    for _ in range(5):
        item = next((item for item in ui.state() if item.get('AXUniqueId') == 'mention-item:shortcut'), None)
        panel = ui.element('mention-panel')['frame']
        if item and item['frame']['y'] >= panel['y'] and item['frame']['y'] + item['frame']['height'] <= panel['y'] + panel['height']:
            break
        ui.axe('swipe', '--start-x', '260', '--start-y', str(panel['y'] + panel['height'] - 12), '--end-x', '260', '--end-y', str(panel['y'] + 12), '--duration', '.4')
    tap('mention-item:shortcut')
    ui.element('mention-picker-item:shortcut-review')
    disabled = ui.element('mention-picker-item:shortcut-other-provider')
    assert not disabled.get('enabled', True), 'Wrong-provider Shortcut must stay disabled'
    missing = ui.element('mention-picker-item:shortcut-deleted-target')
    assert not missing.get('enabled', True), 'Missing saved target must stay disabled'
    assert catalog.text('settings.promptShortcuts.provider_mismatch') in spoken(disabled), 'Wrong-provider row lost its concrete reason'
    assert catalog.text('settings.promptShortcuts.dependency_missing') in spoken(missing), 'Missing-target row lost its concrete reason'
    ui.capture(field + '-shortcuts')
    physical_tap(disabled)
    ui.element('mention-picker-item:shortcut-review')
    retained = ui.element('mention-picker-item:shortcut-other-provider')
    assert not retained.get('enabled', True), 'Tapping a disabled row dismissed or changed the picker'
    ui.capture(field + '-disabled-picker-retained')
    tap('mention-picker-item:shortcut-review')
    assert '@shortcut:shortcut-review' in ui.element(field).get('AXValue', ''), 'Native draft lost the stable Shortcut ID'


started = time.monotonic()
single('shortcut-fixture-ready')
ui.element('shortcut-review')
ui.capture('workspace-catalog')
tap('list-search')
ui.axe('type', 'no-shortcut-found')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('settings.promptShortcuts.noMatches') for item in items), 'No-match feedback missing')
ui.capture('no-matches')
ui.axe('tap', '--label', catalog.system('clear'))
ui.element('shortcut-review')
ui.axe('tap', '--label', catalog.text('settings.promptShortcuts.add'))
fill('prompt-shortcut-name', 'Mobile review')
fill('prompt-shortcut-prompt', 'Review the mobile change.')
ui.capture('create-template')
ui.axe('tap', '--label', catalog.text('common.save'))
new = ui.wait(lambda items: next((item for item in items if 'Mobile review' in (item.get('AXLabel') or '') and item.get('AXUniqueId')), None), 'Created workspace Shortcut missing')
ui.capture('created-shortcut')
tap(new['AXUniqueId'])
ui.element('prompt-shortcut-name')
ui.capture('loaded-template')
fill('prompt-shortcut-description', 'Updated from mobile')
ui.capture('edited-template')
ui.axe('tap', '--label', catalog.text('common.save'))
ui.wait(lambda items: any(item.get('AXUniqueId') == new['AXUniqueId'] and 'Updated from mobile' in (item.get('AXLabel') or '') for item in items), 'Edited Shortcut description did not persist')
ui.capture('updated-shortcut')
row = reveal(new['AXUniqueId'])['frame']
ui.axe('swipe', '--start-x', str(row['x'] + row['width'] - 10), '--start-y', str(row['y'] + row['height'] / 2), '--end-x', str(row['x'] + row['width'] * .55), '--end-y', str(row['y'] + row['height'] / 2), '--duration', '.4')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('common.delete') and item.get('type') == 'Button' for item in items), 'Owned Shortcut delete action missing')
ui.axe('tap', '--label', catalog.text('common.delete'))
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('settings.promptShortcuts.deleteTitle') for item in items), 'Shortcut delete confirmation missing')
ui.capture('delete-confirmation')
ui.axe('tap', '--label', catalog.text('common.delete'))
ui.wait(lambda items: not any(item.get('AXUniqueId') == new['AXUniqueId'] for item in items) and any(item.get('AXUniqueId') == 'shortcut-review' for item in items), 'Deleted Shortcut remains in the list')
ui.capture('deleted-shortcut')

tap('shortcut-fixture-offline')
ui.wait(lambda items: any('unavailable offline' in (item.get('AXLabel') or '').lower() for item in items), 'Offline Shortcut state must be explicit')
ui.capture('offline-catalog')
tap('shortcut-fixture-offline')
ui.element('shortcut-review')

# Chat uses the production useComposerMentions and useSessionSend boundaries.
tap('shortcut-fixture-chat')
single('shortcut-composer-ready')
tap('shortcut-composer-reset')
inline_shortcuts()
browse('session-input')
tap('session-send')
expanded = ui.element('shortcut-expanded-text').get('AXLabel', '')
assert '/fixture/auth/SKILL.md' in expanded and 'role-reviewer' in expanded, 'Structured template references were not expanded before sending'
assert '@shortcut:shortcut-review' not in expanded
ui.capture('chat-expanded')
tap('shortcut-composer-reset')
browse('session-input')
tap('shortcut-composer-delete')
tap('session-send')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('send.alert.title') for item in items), 'Deleted Shortcut must reject send')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('settings.promptShortcuts.not_found') for item in items), 'Deleted Shortcut must show an actionable localized error')
ui.capture('chat-shortcut-error')
ui.axe('tap', '--label', catalog.system('ok'))
retained = ui.wait(lambda items: any('@shortcut:shortcut-review' in (item.get('AXValue') or item.get('AXLabel') or '') for item in items), 'Failed send lost the Shortcut draft')
assert retained
ui.capture('chat-failed-retained')

# Return to the runner-entered fixture; reopening the deep link stacks scenes.
tap('shortcut-composer-close')
single('shortcut-fixture-ready')
tap('shortcut-fixture-create')
single('shortcut-composer-ready')
ui.element('create-session-input')
tap('shortcut-composer-reset')
browse('create-session-input')
tap('session-send')
ui.element('shortcut-expanded-text')
ui.capture('first-turn-expanded')
tap('shortcut-composer-reset')
browse('create-session-input')
tap('shortcut-composer-delete')
tap('session-send')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('send.alert.title') for item in items), 'Deleted Shortcut must reject the first turn')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('settings.promptShortcuts.not_found') for item in items), 'Failed first turn must show the localized Shortcut error')
ui.capture('first-turn-shortcut-error')
ui.axe('tap', '--label', catalog.system('ok'))
assert '@shortcut:shortcut-review' in ui.element('create-session-input').get('AXValue', ''), 'Failed first turn lost the native draft'
ui.capture('first-turn-failed-retained')
tap('shortcut-composer-close')
single('shortcut-fixture-ready')
print(f'PASS: Shortcut CRUD, explicit offline state, scope/dependency gates, chat + CreateSession expansion and retained failure draft; total={time.monotonic() - started:.2f}s')
