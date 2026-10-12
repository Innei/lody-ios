"""Production project management: owner fences, retained drafts, remote removal and Skills."""
import json
import shlex
import sys
import time
from driver import UI
import catalog
from project_geometry import viewport, visible_target, scroll_direction, scroll_points

ui = UI(sys.argv[1], sys.argv[2])


def spoken(item):
    return ' '.join(str(item.get(key) or '') for key in ('AXLabel', 'AXValue')) + ' ' + ' '.join(spoken(child) for child in item.get('children') or [])


def show(identifier):
    if identifier.startswith(('project-preflight', 'project-removal', 'project-affected')):
        first_row = 'project-removal-conversations'
    elif identifier.startswith('project-script'):
        first_row = 'project-script-bash'
    elif identifier.startswith('project-skill'):
        first_row = 'project-skill:.agents/skills/review/SKILL.md'
    elif identifier.startswith('managed-project'):
        first_row = 'managed-project:studio:local:demo'
    else:
        first_row = 'project-source'
    toolbar_labels = {catalog.text(key) for key in ('projectManagement.refresh', 'projectManagement.remove', 'projectManagement.save', 'common.cancel')}
    for missing_direction in ('down', 'up'):
        for _ in range(8):
            items = ui.state()
            bounds = viewport(items, toolbar_labels)
            row = next((item for item in items if item.get('AXUniqueId') == identifier), None)
            if visible_target(row, bounds):
                return row
            direction = scroll_direction(row, bounds, missing_direction)
            first = next((item for item in items if item.get('AXUniqueId') == first_row), None)
            if direction == 'up' and visible_target(first, bounds):
                break  # Pulling farther at the top would dismiss the removal sheet.
            start, end = scroll_points(direction, bounds)
            ui.axe('swipe', '--start-x', '190', '--start-y', str(start), '--end-x', '190', '--end-y', str(end), '--duration', '.4', '--post-delay', '.3')
    raise AssertionError(f'Missing row {identifier}')


def tap(identifier):
    frame = show(identifier)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.4')


def text(key):
    value = catalog.text(key)
    return ui.wait(lambda items: any(value in spoken(item) for item in items), f'Missing {key}')


def toolbar(key):
    value = catalog.text(key)
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == value and item.get('type') == 'Button' and item.get('frame', {}).get('y', 999) < 160 and str(item.get('AXUniqueId') or '').startswith(('project-script-', 'project-removal-', 'project-management-', 'project-skills-'))), None), f'Missing native toolbar {key}')


def action(key):
    frame = toolbar(key)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.4')


def alert_action(key):
    value = catalog.text(key)
    button = ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == value and item.get('type') == 'Button' and not str(item.get('AXUniqueId') or '').startswith('project-') and item.get('frame', {}).get('y', 0) > 160), None), f'Missing alert action {key}')
    frame = button['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.4')


def back():
    ui.axe('tap', '--id', 'BackButton', '--post-delay', '.4')


def confirm_remove():
    action('projectManagement.remove')
    text('projectManagement.confirmTitle')
    alert_action('projectManagement.remove')


def timeout_number_keys(digits, prior):
    """Exercise the numeric validity boundary through the observed NumberPad."""
    name = f'timeout-keys-{prior + digits}'
    record = {'event': 'timeout-number-pad', 'digits': digits, 'udid': ui.udid, 'keys': []}
    started = time.monotonic()
    try:
        before = ui._focused_input(name + '-before')
        record['before'] = before
        assert before['id'] == 'project-script-timeout' and before['firstResponder']
        assert before['text'] == prior and before['selection'] == {'start': len(prior), 'end': len(prior)}
        before_ax = ui.element('project-script-timeout')['AXValue']
        record['beforeAXValue'] = before_ax
        expected_ax = prior or '600000'  # UIKit exposes the visible placeholder when native text is empty.
        assert before_ax == expected_ax

        def descendants(node):
            for child in node.get('children') or []:
                yield child
                yield from descendants(child)

        def keys(items):
            keyboards = [item for item in items if str(item.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar')]
            if len(keyboards) != 1:
                return None
            keyboard = keyboards[0]
            if keyboard.get('pid') != before['pid']:
                return None
            bounds = keyboard['frame']
            children = list(descendants(keyboard))
            matches = []
            for digit in digits:
                buttons = [item for item in children if item.get('AXLabel') == digit and item.get('type') == 'Button' and item.get('enabled') and item['frame']['width'] >= 44 and item['frame']['height'] >= 44 and item['frame']['x'] >= bounds['x'] and item['frame']['x'] + item['frame']['width'] <= bounds['x'] + bounds['width'] and item['frame']['y'] >= bounds['y'] and item['frame']['y'] + item['frame']['height'] <= bounds['y'] + bounds['height']]
                if len(buttons) != 1:
                    return None
                matches.append(buttons[0])
            record['keyboard'] = {key: keyboard[key] for key in ['pid', 'AXUniqueId', 'type', 'frame']}
            return matches
        buttons = ui.wait(keys, 'Missing unique visible NumberPad buttons')
        steps = []
        for digit, button in zip(digits, buttons):
            frame = button['frame']
            record['keys'].append({'label': digit, 'frame': frame})
            steps += ['--step', shlex.join(['tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.3'])]
        record['batchSteps'] = steps[1::2]
        record['batchResult'] = ui.axe('batch', '--ax-cache', 'perStep', '--tap-style', 'physical', *steps, recover=False)
        after = ui._focused_input(name + '-after')
        record['after'] = after
        expected = prior + digits
        assert all(after[key] == before[key] for key in ['pid', 'id', 'class']) and after['firstResponder']
        assert after['text'] == expected and after['selection'] == {'start': len(expected), 'end': len(expected)}
        assert ui.element('project-script-timeout')['AXValue'] == expected
        record['committedCharacters'] = len(after['text']) - len(before['text'])
        record['status'] = 'performed'
    except BaseException as error:
        record['status'], record['error'] = 'failed', str(error)
        raise
    finally:
        record['seconds'] = round(time.monotonic() - started, 3)
        with (ui.output / 'timeout-number-keys.jsonl').open('a') as output:
            output.write(json.dumps(record) + '\n')


show('managed-project:studio:local:demo')
assert toolbar('projectManagement.refresh')['enabled'], 'The production push host must expose Refresh'
ui.capture('sources')
tap('managed-project:studio:local:demo')
show('project-shared:toggle')
assert ui.element('project-shared:toggle')['AXValue'] == '0', 'Owned local projects start private'
ui.capture('local-settings')
tap('project-setup')
tap('project-script-bash')
ui.axe('type', ' # mobile')
draft = ui.element('project-script-bash')['AXValue']
assert 'mobile' in draft
action('projectManagement.save')
text('projectManagement.requestFailed')
assert ui.element('project-script-bash')['AXValue'] == draft, 'Rejected script save lost the draft'
ui.capture('script-failure-retains-draft')
action('projectManagement.save')
show('project-setup')
tap('project-setup')
assert ui.element('project-script-bash')['AXValue'] == draft, 'Saved script did not survive reopening'
action('common.cancel')
tap('project-shared:toggle')
text('projectManagement.readOnly')
assert ui.element('project-shared:toggle')['AXValue'] == '0', 'Server rejection must restore the previous sharing scope'
ui.capture('sharing-denied')
tap('project-shared:toggle')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'project-shared:toggle' and item.get('AXValue') == '1' for item in items), 'Sharing result not confirmed')
ui.capture('sharing-confirmed')
tap('project-skills')
assert toolbar('projectManagement.refresh')['enabled'], 'Pushed Skills must expose Refresh'
tap('project-skill:.agents/skills/review/SKILL.md')
assert 'Inspect the project' in spoken(ui.element('project-skill-content'))
text('projectManagement.skillScope.project')
ui.capture('skill-detail')
back()
back()

tap('project-remove')
ui.element('project-removal-conversations')
ui.capture('removal-sheet-entered')
show('project-affected:build')
assert 'Build the feature' in spoken(ui.element('project-affected:build'))
show('project-removal-cleanup:toggle')
assert ui.element('project-removal-cleanup:toggle')['AXValue'] == '0', 'Cleanup must be opt-in'
show('project-preflight:clean:clean')
show('project-preflight:dirty:dirty')
show('project-preflight:failed:failed')
text('projectManagement.preflight.dirty')
ui.capture('preflight-dirty-preserved')
action('projectManagement.remove')
text('projectManagement.confirmTitle')
ui.capture('remove-confirmation')
alert_action('common.cancel')
show('project-removal-cleanup:toggle')
assert ui.element('project-removal-cleanup:toggle')['AXValue'] == '0'
tap('project-removal-cleanup:toggle')
confirm_remove()
text('projectManagement.requestFailed')
assert ui.element('project-removal-cleanup:toggle')['AXValue'] == '1', 'Failed removal lost the cleanup choice'
ui.capture('remove-failure')
confirm_remove()
text('projectManagement.removal.pending')
assert not any(item.get('AXUniqueId') == 'project-remove' for item in ui.state()), 'Pending projects must not offer a duplicate removal'
ui.capture('removal-pending')
action('projectManagement.refresh')
text('projectManagement.removal.completed')
show('project-cleanup:deleted:clean')
show('project-cleanup:skippedDirty:dirty')
show('project-cleanup:failed:failed')
ui.capture('cleanup-partial-result')
back()
show('managed-project:studio:local:demo')
assert catalog.text('projectManagement.removal.completed') in spoken(ui.element('managed-project:studio:local:demo')), 'Completed result must remain accessible'

tap('managed-project:shared:local:readonly')
show('project-shared:toggle')
assert not ui.element('project-shared:toggle')['enabled'], 'A teammate cannot change the project owner scope'
text('projectManagement.readOnly')
tap('project-setup')
assert not any(item.get('AXUniqueId') == 'project-script-bash' for item in ui.state()), 'Read-only project opened a script editor'
ui.capture('read-only')
back()

tap('managed-project:travel:local:offline')
text('projectManagement.offline')
tap('project-remove')
text('projectManagement.preflightFailed')
show('project-removal-cleanup:toggle')
assert ui.element('project-removal-cleanup:toggle')['AXValue'] == '0'
assert not ui.element('project-removal-cleanup:toggle')['enabled'], 'Offline inspection cannot enable cleanup'
ui.capture('offline-preflight')
confirm_remove()
text('projectManagement.removal.pending')
text('projectManagement.offline')
ui.capture('offline-removal-pending')
back()

tap('managed-project:studio:local:empty')
tap('project-skills')
text('projectManagement.skillsEmpty')
ui.capture('skills-empty')
back()
back()

tap('managed-project:github:LodyAI/Lody')
tap('project-setup')
assert ui.element('project-script-bash')['AXValue'] == 'pnpm install'
tap('project-script-powershell')
ui.axe('type', ' # windows')
powershell = ui.element('project-script-powershell')['AXValue']
assert 'windows' in powershell
tap('project-script-timeout')
timeout_number_keys('0', '')
assert not toolbar('projectManagement.save')['enabled'], 'Zero timeout must be rejected'
ui.capture('invalid-timeout')
timeout_number_keys('600000', '0')
assert toolbar('projectManagement.save')['enabled'], 'A positive timeout must recover the Save action'
action('projectManagement.save')
tap('project-setup')
assert ui.element('project-script-powershell')['AXValue'] == powershell
assert ui.element('project-script-bash')['AXValue'] == 'pnpm install', 'Editing PowerShell changed Bash'
assert int(ui.element('project-script-timeout')['AXValue']) == 600000
ui.capture('github-scripts-saved')
print(json.dumps({'permissionFenced': True, 'draftRetainedOnFailure': True, 'originalDirectoryPreserved': True, 'dirtyWorktreesPreserved': True, 'offlineRemovalVisible': True, 'projectSkillsSharedSource': True}))
