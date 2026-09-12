"""Production iPad search, Glass FAB and chat composer hosts, without cloud."""
import json
import subprocess
import sys
from driver import UI
import catalog
from send_motion import ThrowTrace

ui = UI(sys.argv[1], sys.argv[2])


def labeled(label):
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == label), None), f'Missing {label}')


def tap_label(label):
    frame = labeled(label)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.6')


def tap_row(identifier):
    # UIKit's outline accessory inherits the parent's ID in AXe's tree.
    frame = max((item['frame'] for item in ui.state() if item.get('AXUniqueId') == identifier),
                key=lambda value: value['width'] * value['height'])
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.5')


def assert_selected(stage, identifier='ui-design', selected=True):
    # AXe 1.8 drops the Selected trait even when UIKit reports traits == 9.
    # Read the real cell, without changing app state or introducing a test API.
    processes = subprocess.check_output(['xcrun', 'simctl', 'spawn', ui.udid, 'launchctl', 'list'], text=True)
    pid = next(line.split()[0] for line in processes.splitlines() if 'UIKitApplication:app.innei.lody[' in line)
    expression = '''({ NSMutableArray *q = [NSMutableArray array];
      for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        if ([scene isKindOfClass:[UIWindowScene class]]) [q addObjectsFromArray:(NSArray *)[scene windows]];
      }
      NSMutableArray *result = [NSMutableArray array];
      for (NSUInteger i = 0; i < [q count]; i++) {
        UIView *v = q[i];
        if ([[v accessibilityIdentifier] isEqualToString:@"IDENTIFIER"] && [v isKindOfClass:[UICollectionViewCell class]]) {
          [result addObject:@{@"selected": @([(UICollectionViewCell *)v isSelected]),
            @"selectedTrait": @(([v accessibilityTraits] & UIAccessibilityTraitSelected) != 0)}];
        }
        [q addObjectsFromArray:(NSArray *)[v subviews]];
      }
      [@"SIDEBAR_STATE=" stringByAppendingString:[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:result options:0 error:nil] encoding:NSUTF8StringEncoding]];
    })'''.replace('IDENTIFIER', identifier)
    result = subprocess.run(['lldb', '--batch', '-p', pid, '-o', 'expr -l objc++ -- @import UIKit',
                             '-o', 'expr -l objc++ -O -- ' + expression.replace('\n', ' '), '-o', 'detach'],
                            text=True, capture_output=True, timeout=45)
    (ui.output / f'{stage}-native-selection.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr
    rows = json.loads(result.stdout.rsplit('SIDEBAR_STATE=', 1)[1].splitlines()[0])
    assert len(rows) == 1, (stage, identifier, rows)
    if selected:
        assert rows[0]['selected'] and rows[0]['selectedTrait'], (stage, identifier, rows)
    else:
        assert not rows[0]['selected'] and not rows[0]['selectedTrait'], (stage, identifier, rows)


ui.element('ipad-detail-placeholder')
ui.element('ipad-inbox-list')
panel = ui.element('ipad-panel')['frame']
search = ui.wait(lambda items: next((item for item in items if item.get('subrole') == 'AXSearchField'), None), 'Missing system search')['frame']
settings = labeled(catalog.text('tabs.settings'))['frame']
view_menu = labeled(catalog.text('inbox.settings.section.view'))['frame']
workspace_item = ui.wait(lambda items: next((item for item in items if (item.get('AXLabel') or '').startswith('Switch workspace,')), None), 'Missing workspace switch')
workspace = workspace_item['frame']
fab = labeled(catalog.text('tabs.newSession'))['frame']
assert settings['y'] < search['y'] < panel['y'] + 150
assert settings['x'] < view_menu['x'] < panel['x'] + panel['width'] / 2
assert workspace['y'] > panel['y'] + panel['height'] - 110
assert workspace['x'] < panel['x'] + 40
assert workspace['x'] + workspace['width'] < fab['x']
assert abs(workspace['y'] - fab['y']) < 10
assert fab['width'] >= 44 and fab['height'] >= 44
assert fab['x'] > panel['x'] + panel['width'] - 100
assert fab['y'] > panel['y'] + panel['height'] - 110
ui.capture('sidebar-glass-fab')

tap_label(workspace_item['AXLabel'])
labeled('我的超长工作区名称不能折行')
ui.capture('workspace-menu')
tap_label('我的超长工作区名称不能折行')

# Selection belongs to the sidebar's detail, including across outline updates.
parent_id = 'toggle:ui:local:lody'
if not any(item.get('AXUniqueId') == 'ui-design' for item in ui.state()):
    tap_row(parent_id)
assert 44 <= ui.element('ui-design')['frame']['height'] <= 68
ui.axe('tap', '--id', 'ui-design', '--tap-style', 'physical', '--post-delay', '.6')
ui.element('chat-navigation-title')
assert_selected('selected')
ui.capture('sidebar-selected')

# The same message column must stay readable when the sidebar gives it more room.
split_message = ui.element('a1:answer')['frame']
tap_label(catalog.system('hideSidebar'))
labeled(catalog.system('showSidebar'))
screen = ui.state()[0]['frame']
message = ui.element('a1:answer')['frame']
assert 740 <= message['width'] <= 760.5, ('Message column is not width-limited', message)
assert abs(message['x'] + message['width'] / 2 - screen['x'] - screen['width'] / 2) < 2, ('Message column is not centered', message, screen)
transcript = ui.element('chat-transcript')['frame']
assert abs(transcript['width'] - screen['width']) < 2, ('Transcript must span the screen so the scrollbar stays on the edge', transcript, screen)
assert abs(transcript['x'] - screen['x']) < 2, ('Transcript must start at the screen edge', transcript, screen)
attach = ui.element('session-attach')['frame']
field = ui.element('session-input')['frame']
assert abs(attach['x'] - message['x']) <= 5
assert abs(field['x'] + field['width'] - message['x'] - message['width']) <= 5
ui.capture('reading-column-wide')
ui.axe('tap', '--id', 'session-input', '--tap-style', 'physical', '--post-delay', '.6')
focused = ui.element('session-input')['frame']
assert focused['y'] < field['y'] - 100, 'Keyboard did not lift the composer'
# Focusing moves the attachment button inside the input surface; its outer
# column edges stay aligned even though the editable field itself grows.
assert abs(focused['x'] - attach['x']) < 2 and abs(focused['x'] + focused['width'] - field['x'] - field['width']) < 2, 'Keyboard changed the reading column width'
assert abs(ui.element('a1:answer')['frame']['width'] - message['width']) < 2
ui.capture('reading-column-keyboard')
ui.axe('tap', '--label', 'Hide keyboard', '--tap-style', 'physical', '--post-delay', '.5')
tap_label(catalog.system('showSidebar'))
ui.wait(lambda items: any(item.get('AXUniqueId') == 'a1:answer' and abs(item['frame']['width'] - split_message['width']) < 2
                          for item in items), 'The narrow detail did not restore its available width')
ui.capture('reading-column-split-restored')

tap_row(parent_id)
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'ui-design' for item in items), 'Project did not collapse')
ui.capture('sidebar-collapsed')
tap_row(parent_id)
ui.element('ui-design')
assert_selected('restored')
ui.capture('sidebar-selection-restored')

ui.axe('tap', '--id', 'project:ui:empty', '--tap-style', 'physical', '--post-delay', '.6')
ui.element('ipad-project-list')
labeled(catalog.text('project.empty'))
assert_selected('empty-project-push', 'project:ui:empty')
assert_selected('empty-project-session-yields', selected=False)
ui.capture('sidebar-project')
ui.axe('tap', '--id', 'BackButton', '--tap-style', 'physical', '--post-delay', '.6')
ui.element('ipad-inbox-list')
assert_selected('empty-project-return', 'project:ui:empty', selected=False)
assert_selected('empty-project-session-restored')

# Business entry points share the same owner: workspace switching clears both
# columns, then a real system deep link resolves its workspace and opens detail.
tap_label(workspace_item['AXLabel'])
tap_label('另一个工作区')
ui.element('ipad-detail-placeholder')
ui.wait(lambda items: not any(item.get('AXUniqueId') in ('ui-design', 'session-input') for item in items), 'Old workspace content survived the switch')
ui.capture('workspace-isolated')
subprocess.run(['xcrun', 'simctl', 'openurl', ui.udid, 'lody://ui-home/sessions/ui-design'], check=True, timeout=20)
destination = ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == 'Open' or item.get('AXUniqueId') == 'session-input'), None), 'Deep link did not offer an app destination')
if destination.get('AXLabel') == 'Open':
    tap_label('Open')
ui.element('session-input')
ui.element('ui-design')
ui.element('ipad-inbox-list')
routes = json.loads(ui.element('ui-navigation-state')['AXValue'])
assert routes == ['index'], f'Deep link pushed onto the iPhone route stack: {routes}'
assert ui.element('session-input')['frame']['x'] > ui.element('ipad-panel')['frame']['width']
assert_selected('deeplink-selected')
ui.capture('deeplink-business-detail')

tap_label(catalog.text('tabs.newSession'))
creation_input = ui.element('create-session-input')['frame']
assert creation_input['width'] > panel['width'], 'Creation is still constrained to the sidebar'
ui.axe('tap', '--id', 'project', '--tap-style', 'physical', '--post-delay', '.5')
ui.element('BackButton')
ui.axe('tap', '--id', 'BackButton', '--tap-style', 'physical', '--post-delay', '.5')
ui.element('create-session-input')
ui.capture('fab-opens-new-session')
tap_label(catalog.text('accessibility.closeSheet', title=catalog.text('create.title')))
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'create-session-input' for item in items), 'New session did not close')

ui.axe('tap', '-x', str(search['x'] + search['width'] / 2), '-y', str(search['y'] + search['height'] / 2), '--post-delay', '.3')
ui.axe('type', 'lody')
ui.element('ui-design')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'project:ui:empty' for item in items), 'Search did not filter projects')
ui.element('project:ui:local:lody')
ui.capture('sidebar-search')
ui.axe('tap', '--id', 'project:ui:local:lody', '--tap-style', 'physical', '--post-delay', '.6')
ui.element('ipad-project-list')
assert_selected('search-project-push', 'project:ui:local:lody')
ui.axe('tap', '--id', 'BackButton', '--tap-style', 'physical', '--post-delay', '.6')
ui.element('ipad-inbox-list')
assert_selected('search-project-return', 'project:ui:local:lody', selected=False)
ui.axe('tap', '--id', 'ui-design', '--tap-style', 'physical', '--post-delay', '.8')
ui.element('session-input')
ui.element('chat-navigation-title')
ui.capture('chat-glass-resting')
ui.axe('tap', '--id', 'session-input', '--tap-style', 'physical', '--post-delay', '.6')
ui.capture('chat-glass-focused')

# A fresh first turn must travel from the window-level form into the right column.
ui.axe('tap', '--label', 'Hide keyboard', '--tap-style', 'physical', '--post-delay', '.5')
tap_label(catalog.text('tabs.newSession'))
ui.element('create-session-input')
trace = ThrowTrace(ui)
draft = 'Carry this message into the iPad conversation'
ui.axe('tap', '--id', 'create-session-input', '--tap-style', 'physical', '--post-delay', '.3')
ui.type_into('create-session-input', draft)
draft = ui.element('create-session-input')['AXValue']
ui.capture('handoff-source')
field = ui.element('create-session-input')['frame']
send = next(item['frame'] for item in ui.state()
            if item.get('AXUniqueId') == 'session-send'
            and field['x'] <= item['frame']['x'] < field['x'] + field['width']
            and abs(item['frame']['y'] - field['y'] - field['height']) < 50)
ui.axe('tap', '-x', str(send['x'] + send['width'] / 2), '-y', str(send['y'] + send['height'] / 2), '--tap-style', 'physical', '--post-delay', '1')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'create-session-input' for item in items), 'Creation sheet did not dismiss after sending')
ui.wait(lambda items: any(item.get('AXLabel') == draft and (item.get('AXUniqueId') or '').endswith(':user') for item in items), 'The first message did not reach the chat')
ui.element('session-input')
ui.capture('handoff-landed')
trace.verify(1)

print('PASS: Native toolbar, window form navigation, search, navigating-row selection until return, and first-message handoff into the iPad detail.')
