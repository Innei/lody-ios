"""Offline Role, MCP and remote-worktree choices in chat and new-session hosts."""
import json
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])

def tap(value):
    ui.element(value)
    ui.axe('tap', '--id', value, '--post-delay', '.4')

def label(value, create_segment=False):
    if create_segment:
        def segment(items):
            groups = [item for item in items if item.get('AXUniqueId') == 'create-type' and item.get('type') == 'TabGroup']
            if not groups:
                return None
            assert len(groups) == 1, 'Creation must own exactly one type segment'
            group = groups[0]
            matches = [item for item in group.get('children', []) if item.get('AXLabel') == value and item.get('type') == 'RadioButton']
            assert len(matches) == 1, 'Creation segment must own exactly one ' + value
            found = matches[0]
            if group.get('enabled') is not True or found.get('enabled') is not True:
                return None
            frame, scope, screen = found['frame'], group['frame'], items[0]['frame']
            assert frame['width'] >= 44 and frame['height'] >= 44, 'Creation segment must be touchable'
            for bounds in (scope, screen):
                assert bounds['x'] <= frame['x'] and bounds['y'] <= frame['y'] and frame['x'] + frame['width'] <= bounds['x'] + bounds['width'] and frame['y'] + frame['height'] <= bounds['y'] + bounds['height'], 'Creation segment must be visible within its scope'
            return {'groupFrame': scope, 'screenFrame': screen, 'target': {key: found.get(key) for key in ('AXLabel', 'AXValue', 'type', 'role', 'enabled', 'frame')}}
        before = ui.wait(segment, 'Missing creation segment ' + value)
        frame = before['target']['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width']/2), '-y', str(frame['y'] + frame['height']/2), '--post-delay', '.4')
        def selected(items):
            found = segment(items)
            return found if found and found['target']['AXValue'] == 1 else None
        after = ui.wait(selected, 'Creation segment did not select ' + value)
        (ui.output / 'create-chat-segment.json').write_text(json.dumps({'before': before, 'after': after}, indent=2))
        return
    found = ui.wait(lambda items: next((item for item in items if (item.get('AXLabel') or '').startswith(value) and item.get('type') == 'Button'), None), 'Missing ' + value)
    ui.axe('tap', '--label', found['AXLabel'], '--post-delay', '.4')

def probe(key, predicate):
    return ui.wait(lambda items: next((json.loads(item.get('AXLabel', '{}')) for item in items
      if item.get('AXUniqueId') == key and item.get('AXLabel', '').startswith('{') and predicate(json.loads(item['AXLabel']))), None), 'Missing choice ' + key)

def create_send(stage):
    # The presenting chat and creation sheet reuse session-send. Resolve the
    # nearest AX ancestor containing the creation input and its own Send.
    def scoped(items):
        scopes = []
        def visit(node, path):
            inputs = [node] if node.get('AXUniqueId') == 'create-session-input' else []
            sends = [{'node': node, 'path': path}] if node.get('AXUniqueId') == 'session-send' else []
            for index, child in enumerate(node.get('children', [])):
                child_inputs, child_sends = visit(child, path + [index])
                inputs.extend(child_inputs)
                sends.extend(child_sends)
            if inputs and sends:
                scopes.append({'path': path, 'frame': node.get('frame'), 'inputs': inputs, 'sends': sends.copy()})
            return inputs, sends
        if not items:
            return None
        _, all_sends = visit(items[0], [])
        if not scopes:
            return None
        scope = max(scopes, key=lambda candidate: len(candidate['path']))
        assert len(scope['inputs']) == 1 and len(scope['sends']) == 1, 'Creation composer must own exactly one input and Send'
        return {'scope': scope, 'allSends': all_sends}
    found = ui.wait(scoped, 'Creation-scoped Send missing')
    def summary(candidate):
        return {'path': candidate['path'], **{key: candidate['node'].get(key)
            for key in ('AXUniqueId', 'AXLabel', 'enabled', 'frame')}}
    scope = found['scope']
    (ui.output / ('create-send-' + stage + '-scope.json')).write_text(json.dumps({
        'creationInput': scope['inputs'][0].get('AXUniqueId'),
        'scopePath': scope['path'], 'scopeFrame': scope['frame'],
        'selectedSend': summary(scope['sends'][0]),
        'allSends': [summary(candidate) for candidate in found['allSends']],
    }, indent=2))
    return scope['sends'][0]['node']

def back():
    button = ui.wait(lambda items: max((item for item in items if item.get('type') == 'Button' and
      item.get('AXLabel') in ['Back', catalog.text('create.title')]), key=lambda item: item['frame']['y'], default=None), 'Back missing')
    frame = button['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width']/2), '-y', str(frame['y'] + frame['height']/2), '--post-delay', '.4')

tap('session-input')
tap('session-model')
tap('composer-role-menu')
unavailable = ui.wait(lambda items: next((item for item in items if 'Unavailable Role' in (item.get('AXLabel') or '')), None), 'Unavailable Role missing')
assert unavailable.get('enabled') is False, 'An unavailable binding must remain visible and disabled'
unsupported = ui.wait(lambda items: next((item for item in items if 'Unsupported Role' in (item.get('AXLabel') or '')), None), 'Unsupported Role missing')
assert unsupported.get('enabled') is False, 'Unsupported run values must not be selectable'
ui.wait(lambda items: any(catalog.text('runOptions.roles.run_config_unsupported') in (item.get('AXLabel') or '') for item in items), 'Unsupported Role must show its recovery reason')
label('Reviewer')
picked = probe('run-options-choice', lambda value: value.get('agentRoleId') == 'reviewer')
assert picked['modelId'] == 'a' and picked['modeId'] == 'read-only' and picked['agentRoleRevision'] == 3
assert picked['frozenRole']['modelId'] == 'a', 'New choice must freeze the projected role config'
ui.capture('chat-role-selected')
tap('composer-model-menu')
label('Model B')
probe('run-options-choice', lambda value: value.get('agentRoleId', 'unset') is None and value.get('modelId') == 'b')
tap('composer-role-menu')
label('Reviewer')
tap('composer-role-menu')
label(catalog.text('runOptions.roles.none'))
cleared = probe('run-options-choice', lambda value: value.get('agentRoleId', 'unset') is None and value.get('modelId') == 'a')
assert cleared['modeId'] == 'read-only', 'Clearing Role must preserve the chosen run values'
tap('composer-mcp-menu')
label(catalog.text('runOptions.mcp.none'))
probe('run-options-choice', lambda value: value.get('mcpServerIds') == [])
tap('composer-mcp-menu')
label('Browser')
probe('run-options-choice', lambda value: value.get('mcpServerIds') == ['browser'])
ui.capture('chat-mcp-explicit-choice')
# MCP toggles keep the native menu open. Its All off row covers the Role
# button's accessibility activation point, so dismiss it before switching menus.
off = ui.wait(lambda items: next((item for item in items if item.get('type') == 'Button' and
    item.get('AXLabel') == catalog.text('runOptions.mcp.none')), None), 'MCP menu must remain open after a toggle')
role_frame = ui.element('composer-role-menu')['frame']
model_frame = ui.element('composer-model-menu')['frame']
outside = {'x': role_frame['x'] - 8, 'y': model_frame['y'] + model_frame['height'] / 2}
assert outside['x'] < off['frame']['x'], 'Dismissal must be outside the foreground MCP menu'
dismissed = ui.axe('tap', '-x', str(outside['x']), '-y', str(outside['y']), '--post-delay', '.4')
ui.wait(lambda items: not any(item.get('type') == 'Button' and
    item.get('AXLabel') == catalog.text('runOptions.mcp.none') for item in items), 'MCP menu did not dismiss')
retained = probe('run-options-choice', lambda value: value.get('mcpServerIds') == ['browser'])
(ui.output / 'mcp-menu-dismiss.json').write_text(json.dumps({
    'outsideTap': outside, 'foregroundAllOff': off['frame'], 'underlyingRole': role_frame,
    'tapResult': dismissed, 'retainedChoice': retained,
}, indent=2))
ui.capture('chat-mcp-menu-dismissed')
tap('composer-role-menu')
label('Reviewer')
ui.axe('tap', '-x', '18', '-y', '112', '--post-delay', '.4')
label(catalog.text('common.more'))
label('Fail run options lookup')
ui.wait(lambda items: any(catalog.text('runOptions.chatUnavailable') in (item.get('AXLabel') or '') for item in items), 'Chat options failure must be visible')
preserved = probe('run-options-choice', lambda value: value.get('agentRoleId') == 'reviewer' and value.get('mcpServerIds') == ['browser'])
assert preserved['agentRoleRevision'] == 3 and preserved['frozenRole']['modelId'] == 'a', 'Catalog failure must preserve the explicit frozen choices'
ui.capture('chat-run-options-unavailable')
label(catalog.text('common.more'))
label(catalog.text('runOptions.retry'))
ui.element('run-options-ready')
probe('run-options-choice', lambda value: value.get('agentRoleId') == 'reviewer' and value.get('mcpServerIds') == ['browser'])
ui.capture('chat-run-options-retry')

label(catalog.text('common.more'))
label('New session options unavailable')
ui.element('create-session-input')
ui.axe('swipe', '--start-x', '200', '--start-y', '380', '--end-x', '200', '--end-y', '45', '--duration', '.4', '--post-delay', '.6')
ui.element('run-options-retry')
assert create_send('unavailable').get('enabled') is True, 'An optional run catalog failure must keep ordinary creation available'
ui.capture('create-run-options-unavailable')
tap('run-options-retry')
ui.element('worktree')
ui.element('role')
ui.element('mcp')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'run-options-retry' for item in items), 'Creation retry must replace the unavailable catalog')
tap('role')
tap('reviewer')
ui.capture('create-run-options-retry')
tap('agent')
tap('ui:legacy')
assert 'Legacy Claude' in str(ui.element('agent')), 'The catalog legacy assistant must be selectable in the real native picker'
ui.capture('create-legacy-assistant')
tap('agent')
tap('ui:agent')
tap('role')
tap('reviewer')
assert 'Fixture Agent' in str(ui.element('agent')), 'Reviewer must remain bound to the original assistant after switching'
ui.capture('create-role-assistant-binding')
close = catalog.text('accessibility.closeSheet', title=catalog.text('create.title'))
label(close)

tap('run-options-open-create')
ui.element('create-session-input')
ui.axe('swipe', '--start-x', '200', '--start-y', '380', '--end-x', '200', '--end-y', '45', '--duration', '.4', '--post-delay', '.6')
tap('worktree')
tap('worktree')
tap('role')
tap('reviewer')
tap('mcp')
tap('docs:toggle')
tap('browser:toggle')
ui.capture('create-mcp-picker')
back()
ui.capture('create-project-role-worktree')
send = create_send('submit')['frame']
ui.axe('tap', '-x', str(send['x'] + send['width']/2), '-y', str(send['y'] + send['height']/2), '--post-delay', '.4')
result = probe('run-options-result', lambda value: value.get('creation', {}).get('useWorktree') is True)
assert result['creation']['agentRoleId'] == 'reviewer' and result['creation']['agentRoleRevision'] == 3
assert result['choice']['mcpServerIds'] == ['browser'] and result['choice']['frozenRole']['modelId'] == 'a'
ui.capture('create-frozen-outbox-choice')

tap('run-options-open-create')
ui.element('create-session-input')
ui.axe('swipe', '--start-x', '200', '--start-y', '380', '--end-x', '200', '--end-y', '45', '--duration', '.4', '--post-delay', '.6')
label(catalog.text('create.type.chat'), create_segment=True)
tap('role')
tap('reviewer')
ui.capture('create-chat-role')
close = catalog.text('accessibility.closeSheet', title=catalog.text('create.title'))
label(close)
tap('run-options-open-roles')
ui.element('unsupported')
ui.capture('settings-role-list')
def role_list(items):
    expected = {
        'missing': ('Unavailable Role', catalog.text('runOptions.roles.agent_config_missing')),
        'unsupported': ('Unsupported Role', catalog.text('runOptions.roles.run_config_unsupported')),
    }
    screen = items[0]['frame']
    rows = {}
    for identifier, (title, reason) in expected.items():
        matches = [item for item in items if item.get('AXUniqueId') == identifier]
        if len(matches) != 1:
            return None
        row = matches[0]
        pending, text = list(row.get('children', [])), []
        while pending:
            child = pending.pop()
            if child.get('type') == 'StaticText':
                text.append(child)
            pending.extend(child.get('children', []))
        titles = [child for child in text if child.get('AXLabel') == title]
        reasons = [child for child in text if reason in (child.get('AXLabel') or '')]
        if len(titles) != 1 or len(reasons) != 1:
            return None
        for child, bounds in ((row, screen), (titles[0], row['frame']), (reasons[0], row['frame'])):
            frame = child['frame']
            if not (bounds['x'] <= frame['x'] and bounds['y'] <= frame['y'] and
                    frame['x'] + frame['width'] <= bounds['x'] + bounds['width'] and
                    frame['y'] + frame['height'] <= bounds['y'] + bounds['height'] and
                    frame['width'] > 0 and frame['height'] > 0):
                return None
        rows[identifier] = {
            'cardFrame': row['frame'],
            'title': {key: titles[0].get(key) for key in ('AXLabel', 'frame')},
            'reason': {key: reasons[0].get(key) for key in ('AXLabel', 'frame')},
        }
    return rows
list_fields = ui.wait(role_list, 'Unavailable and Unsupported Role titles and complete reasons must fit their visible cards')
(ui.output / 'settings-role-list-fields.json').write_text(json.dumps(list_fields, indent=2))
tap('reviewer')
def role_details(items):
    expected = {
        'name': ('Reviewer',),
        'agent': (catalog.text('create.label.agent'), 'Fixture Agent'),
        'machine': (catalog.text('create.label.machine'), 'ui'),
        'model': (catalog.text('create.label.model'), 'a'),
        'mode': (catalog.text('runOptions.roles.permission'), 'read-only'),
        'revision': (catalog.text('runOptions.roles.revision'), '3'),
    }
    screen = items[0]['frame']
    fields = {}
    for identifier, values in expected.items():
        matches = [item for item in items if item.get('AXUniqueId') == identifier]
        if len(matches) != 1:
            return None
        field = matches[0]
        frame = field['frame']
        if not (screen['x'] <= frame['x'] and screen['y'] <= frame['y'] and
                frame['x'] + frame['width'] <= screen['x'] + screen['width'] and
                frame['y'] + frame['height'] <= screen['y'] + screen['height'] and
                frame['width'] > 0 and frame['height'] > 0):
            return None
        pending, labels = [field], set()
        while pending:
            node = pending.pop()
            labels.update(node.get(key) for key in ('AXLabel', 'AXValue') if node.get(key) is not None)
            pending.extend(node.get('children', []))
        if not (set(values).issubset(labels) or ', '.join(values) in labels):
            return None
        fields[identifier] = {key: field.get(key) for key in ('AXUniqueId', 'AXLabel', 'AXValue', 'type', 'frame')}
    return fields
details = ui.wait(role_details, 'Reviewer detail fields must show the original assistant, machine, model, mode and revision')
(ui.output / 'settings-role-detail-fields.json').write_text(json.dumps(details, indent=2))
ui.wait(lambda items: any(catalog.text('runOptions.roles.desktopHint') in (item.get('AXLabel') or '') for item in items), 'Desktop creation guidance missing')
ui.capture('settings-role-details')
print('PASS: chat Role pin/detach/clear and MCP ids, chat/Create catalog failures and retry, new project worktree+frozen Role outbox, Chat Role picker and readonly Settings details')
