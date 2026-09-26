"""iPad Sidebar layout and relocated actions, using offline Home fixtures."""
import sys
import catalog
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])


def labeled(label):
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == label), None), f'Missing {label}')


def tap_label(label):
    frame = labeled(label)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.6')


ui.element('ipad-detail-placeholder')
ui.element('ipad-inbox-list')
panel = ui.element('ipad-panel')['frame']
search = ui.wait(lambda items: next((item for item in items if item.get('subrole') == 'AXSearchField'), None), 'Missing system search')['frame']
settings = labeled(catalog.text('tabs.settings'))['frame']
view_menu = labeled(catalog.text('inbox.settings.section.view'))['frame']
workspace_item = ui.wait(lambda items: next((item for item in items if (item.get('AXLabel') or '').startswith('Switch workspace,')), None), 'Missing workspace switch')
workspace = workspace_item['frame']
fab = labeled(catalog.text('tabs.newSession'))['frame']
assert workspace['y'] + workspace['height'] <= search['y'] < panel['y'] + 150
assert workspace['x'] < panel['x'] + 40
assert workspace['x'] + workspace['width'] <= panel['x'] + panel['width'] - 8
assert view_menu['x'] < settings['x'] < fab['x']
for action in (settings, view_menu):
    assert action['y'] > panel['y'] + panel['height'] - 110
    assert abs(action['y'] - fab['y']) < 10
assert workspace['width'] >= 44 and workspace['height'] >= 44
assert fab['width'] >= 44 and fab['height'] >= 44
assert fab['x'] > panel['x'] + panel['width'] - 100
assert fab['y'] > panel['y'] + panel['height'] - 110
ui.capture('sidebar-glass-fab')

tap_label(catalog.text('inbox.settings.section.view'))
for key in ('view.projects', 'view.activity', 'view.chat', 'sort.name', 'sort.activity', 'sort.urgency'):
    labeled(catalog.text(f'inbox.settings.{key}'))
ui.capture('sidebar-view-menu')
tap_label(catalog.text('inbox.settings.view.activity'))
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'toggle:ui:local:lody' for item in items), 'Activity view retained the project outline')
tap_label(catalog.text('inbox.settings.section.view'))
tap_label(catalog.text('inbox.settings.view.projects'))
ui.element('toggle:ui:local:lody')
tap_label(catalog.text('tabs.settings'))
close_settings = catalog.text('accessibility.closeSheet', title=catalog.text('tabs.settings'))
labeled(close_settings)
ui.capture('sidebar-settings')
tap_label(close_settings)
ui.element('ipad-inbox-list')

tap_label(workspace_item['AXLabel'])
labeled(catalog.text('workspace.edit.action'))
ui.capture('workspace-menu')
tap_label('另一个工作区')
ui.element('ipad-detail-placeholder')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'ui-design' for item in items), 'Old workspace content survived switching')
ui.capture('workspace-switched')
tap_label(catalog.text('inbox.workspaceSwitch.accessibility', name='另一个工作区'))
tap_label('我的超长工作区名称不能折行')
ui.element('ui-design')
tap_label(catalog.text('tabs.newSession'))
ui.element('create-session-input')
ui.capture('new-session')
tap_label(catalog.text('accessibility.closeSheet', title=catalog.text('create.title')))
ui.element('ipad-inbox-list')
print('PASS: Workspace at the top; view/settings at the bottom; workspace, view, settings and new-session actions remain usable.')
