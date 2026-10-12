"""Scheduled-task management uses production pages and an offline service boundary."""
import json
import sys
from driver import UI
import catalog
from project_geometry import viewport, scroll_points

ui = UI(sys.argv[1], sys.argv[2])


def spoken(item):
    return ' '.join(str(item.get(key) or '') for key in ('AXLabel', 'AXValue')) + ' ' + ' '.join(spoken(child) for child in item.get('children') or [])


def find(identifier):
    return next((item for item in ui.state() if item.get('AXUniqueId') == identifier), None)


def reach(identifier):
    for _ in range(8):
        item = find(identifier)
        if item:
            return item
        ui.axe('swipe', '--start-x', '185', '--start-y', '690', '--end-x', '185', '--end-y', '290', '--duration', '.35', '--post-delay', '.2')
    for _ in range(8):
        item = find(identifier)
        if item:
            return item
        ui.axe('swipe', '--start-x', '185', '--start-y', '290', '--end-x', '185', '--end-y', '690', '--duration', '.35', '--post-delay', '.2')
    raise AssertionError(f'Missing row {identifier}')


def reach_reason(key):
    text = catalog.text(key)
    for _ in range(8):
        items = ui.state()
        bounds = viewport(items, [catalog.text('schedules.edit'), catalog.text('schedules.refresh')])
        for item in items:
            label = ' '.join(str(item.get(name) or '') for name in ('AXLabel', 'AXValue'))
            frame = item.get('frame') or {}
            if text in label and frame.get('height', 0) > 0 and frame.get('y', -1) >= bounds[0] and frame.get('y', 0) + frame.get('height', 0) <= bounds[1]:
                return item
        start, end = scroll_points('down', bounds)
        ui.axe('swipe', '--start-x', '185', '--start-y', str(start), '--end-x', '185', '--end-y', str(end), '--duration', '.35', '--post-delay', '.2')
    raise AssertionError(f'Missing visible restriction reason {text}')


def prompt_readable():
    row = reach('prompt')
    outer = row['frame']
    def labels(item):
        for child in item.get('children') or []:
            if child.get('type') == 'StaticText' and child.get('AXLabel'):
                yield child
            yield from labels(child)
    content = list(labels(row))
    assert any(item.get('AXLabel') == catalog.text('schedules.prompt') for item in content), 'Prompt title must remain visible'
    assert any(item.get('AXLabel') != catalog.text('schedules.prompt') for item in content), 'Prompt text must remain visible'
    for item in content:
        frame = item['frame']
        assert frame['width'] > 0 and frame['x'] >= outer['x'] and frame['x'] + frame['width'] <= outer['x'] + outer['width'] + 1, 'Prompt text must stay inside the task card'


def tap(identifier):
    reach(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.3')


def button(key):
    label = catalog.text(key)
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == label and item.get('type') == 'Button'), None), f'Missing button {label}')


def action(key):
    assert button(key).get('enabled', True), f'Disabled action {key}'
    ui.axe('tap', '--label', catalog.text(key), '--post-delay', '.3')


def confirmation_button(items, title, label, bounds):
    dialogs = [item for item in items if item.get('type') in ('Alert', 'Sheet') and item.get('AXLabel') == title]
    if not dialogs:
        return None
    assert len(dialogs) == 1, f'Multiple confirmation dialogs for {title}'
    dialog = dialogs[0]
    def descendants(item):
        for child in item.get('children') or []:
            yield child
            yield from descendants(child)
    matches = [item for item in descendants(dialog) if item.get('type') == 'Button' and item.get('AXLabel') == label]
    if not matches:
        return None
    assert len(matches) == 1, f'Multiple confirmation buttons for {label}'
    target = matches[0]
    assert target.get('enabled') is True, f'Disabled confirmation {label}'
    frame, outer = target['frame'], dialog['frame']
    assert frame['width'] >= 44 and frame['height'] >= 44, f'Confirmation {label} must have a 44pt touch target'
    for axis, size in [('x', 'width'), ('y', 'height')]:
        assert frame[axis] >= outer[axis] and frame[axis] + frame[size] <= outer[axis] + outer[size], f'Confirmation {label} is outside its dialog'
    assert bounds[0] <= frame['y'] and frame['y'] + frame['height'] <= bounds[1], f'Confirmation {label} is outside the visible content'
    return target


def dialog_button(key, title_key):
    title, label = catalog.text(title_key), catalog.text(key)
    return ui.wait(lambda items: confirmation_button(items, title, label, viewport(items, [catalog.text('schedules.edit'), catalog.text('schedules.refresh')])), f'Missing dialog action {label}')


def dialog_action(key, title_key):
    frame = dialog_button(key, title_key)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.3')
    title = catalog.text(title_key)
    ui.wait(lambda items: not any(item.get('type') in ('Alert', 'Sheet') and item.get('AXLabel') == title for item in items), f'Confirmation {title} did not settle')


def back():
    ui.axe('swipe', '--start-x', '2', '--start-y', '450', '--end-x', '365', '--end-y', '450', '--duration', '.35', '--post-delay', '.3')


def reset():
    ui.open_case('schedules')
    ui.element('schedules-preview-ready')


def choose_rule(key):
    tap('rule-kind')
    ui.axe('tap', '--label', catalog.text(key), '--post-delay', '.3')


ui.element('schedules-preview-ready')
ui.capture('scenes')
tap('schedules-list')
ui.element('schedule:morning')
ui.element('list-search')
ui.capture('task-list')
tap('list-search')
ui.type_into('list-search', 'Morning')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'schedule:morning' for item in items) and not any(item.get('AXUniqueId') == 'schedule:offline' for item in items), 'Task search must exclude nonmatching tasks')
ui.capture('task-search')
ui.axe('tap', '--label', catalog.system('clear'), '--post-delay', '.3')
restored_rows = {'schedule:morning', 'schedule:offline', 'schedule:old', 'schedule:shared'}
ui.wait(lambda items: any(item.get('AXUniqueId') == 'list-search' and item.get('AXValue') in (None, '', catalog.text('schedules.search')) for item in items) and restored_rows <= {item.get('AXUniqueId') for item in items}, 'Clearing task search must restore the full list')
ui.capture('task-search-cleared')
reset()
tap('schedules-edit')
ui.element('name')
assert button('schedules.save').get('enabled', True)
tap('name')
ui.element('schedule-field')
ui.axe('type', ' mobile')
name = ui.element('schedule-field').get('AXValue') or ''
assert 'mobile' in name
action('common.done')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'name' and name in spoken(item) for item in items), 'Edited name did not reach the task form')
prompt_readable()
ui.capture('editor')
tap('rule')
ui.element('rule-kind')
assert 'Asia/Shanghai' in spoken(ui.element('zone'))
choose_rule('schedules.rule.weekly')
tap('weekday:1:toggle')
ui.element('schedule-rule-error')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('common.done') and item.get('type') == 'Button' and not item.get('enabled', True) for item in items), 'A weekly rule without a day must not be saved')
reach_reason('schedules.invalidTime')
ui.capture('rule-invalid')
tap('weekday:3:toggle')
assert button('common.done').get('enabled', True)
reach('schedule-preview:0')
ui.capture('weekly-preview')
action('common.done')
tap('destination')
ui.axe('tap', '--label', catalog.text('schedules.destination.own_session'), '--post-delay', '.3')
assert not find('project'), 'A task-owned conversation must not retain a separate project'
prompt_readable()
ui.capture('own-conversation')
tap('destination')
ui.axe('tap', '--label', catalog.text('schedules.destination.existing_session'), '--post-delay', '.3')
tap('session')
ui.axe('tap', '--label', 'Existing review conversation', '--post-delay', '.3')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'session' and 'Existing review conversation' in spoken(item) for item in items), 'Existing conversation selection did not reach the editor')
prompt_readable()
ui.capture('existing-conversation')
action('schedules.save')
ui.element('schedule-editor-error')
assert catalog.text('schedules.writeUnknown') in spoken(ui.element('schedule-editor-error'))
assert name in spoken(reach('name')), 'An uncertain acknowledgement lost the draft'
assert button('schedules.retrySave').get('enabled', True)
prompt_readable()
ui.capture('uncertain-save')
action('schedules.retrySave')
ui.element('schedules-preview-ready')
ui.capture('save-confirmed')

reset()
tap('schedules-offline')
reach('run')
assert ui.element('run').get('type') != 'Button', 'Run must be unavailable on an offline machine'
reach_reason('schedules.machineOffline')
assert any(catalog.text('schedules.machineOffline') in spoken(item) for item in ui.state())
ui.capture('offline-restriction')
reset()
tap('schedules-owner')
reach('delete')
assert ui.element('delete').get('type') != 'Button', 'Another owner’s task must not be deletable'
assert not button('schedules.edit').get('enabled', True)
ui.capture('owner-restriction')
reset()
tap('schedules-upgrade')
reach('resume')
assert ui.element('resume').get('type') != 'Button', 'Unsupported CLI must not resume a task'
reach_reason('schedules.upgrade')
assert any(catalog.text('schedules.upgrade') in spoken(item) for item in ui.state())
ui.capture('upgrade-restriction')

reset()
tap('schedules-proposal')
ui.element('name')
assert any(catalog.text('schedules.proposalHint') in spoken(item) for item in ui.state()), 'Proposal must explain that it has not been created'
assert button('schedules.create').get('enabled', True)
ui.capture('proposal-review')
action('schedules.create')
ui.element('schedule-editor-error')
action('schedules.retrySave')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'schedules-preview-ready' and 'Proposal confirmed' in spoken(item) for item in items), 'Proposal confirmation did not settle with a created task')
ui.capture('proposal-confirmed')

reset()
tap('schedules-history')
tap('pause')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'resume' for item in items), 'Pause did not change the action to Resume')
ui.capture('paused')
tap('resume')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'pause' for item in items), 'Resume did not change the action to Pause')
tap('run')
dialog_button('schedules.runNow', 'schedules.runNow')
ui.capture('run-confirmation')
dialog_action('schedules.runNow', 'schedules.runNow')
back()
ui.wait(lambda items: any(item.get('AXUniqueId') == 'schedules-preview-ready' and 'Run requested' in spoken(item) for item in items), 'Run now did not reach the service boundary')
ui.capture('run-requested')
tap('schedules-history')
reach('schedule-history:result-chat')
ui.capture('history')
tap('schedule-history:result-chat')
ui.element('schedule-result-ready')
ui.capture('result-conversation')
back()
reach('delete')
tap('delete')
ui.wait(lambda items: any(catalog.text('schedules.deleteTitle') in spoken(item) for item in items), 'Delete must require confirmation')
dialog_button('common.cancel', 'schedules.deleteTitle')
ui.capture('delete-confirmation')
dialog_action('common.cancel', 'schedules.deleteTitle')
assert find('schedule-title') or find('delete'), 'Cancel incorrectly deleted the task'
tap('delete')
dialog_action('schedules.delete', 'schedules.deleteTitle')
ui.element('schedules-preview-ready')
ui.capture('deleted')
print(json.dumps({'searchAndClear': True, 'rules': True, 'destinations': True, 'uncertainRetryPreserved': True, 'ownershipAndOfflineGates': True, 'proposalRequiresConfirmation': True, 'historyOpened': True, 'deleteConfirmed': True}))
