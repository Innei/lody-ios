"""The compact Home filters projects with a glass bar and finds them with a scroll-time index."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
home_avatar = catalog.workspace_switch('我的超长工作区名称不能折行')


def ids(items):
    return {i.get('AXUniqueId') for i in items}


def switch(name):
    prefix = catalog.text('inbox.workspaceSwitch.accessibility', name='\0').split('\0')[0]
    menu = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').startswith(prefix)), None), 'Missing workspace menu')
    ui.axe('tap', '--label', menu['AXLabel'], '--post-delay', '.8')
    ui.axe('tap', '--label', name, '--post-delay', '1.2')


ui.wait(lambda items: any(i.get('AXLabel') == home_avatar for i in items), 'Missing workspace avatar')
ui.element('project-bar')
switch('Design states')
ui.element('project-chip:states:lody-ios')
chips = sorted((i for i in ui.state() if (i.get('AXUniqueId') or '').startswith('project-chip:')), key=lambda i: i['frame']['x'])
assert [c['AXUniqueId'] for c in chips][:3] == ['project-chip:all', 'project-chip:states:lody-cloud', 'project-chip:states:lody-ios'], [c['AXUniqueId'] for c in chips]
bar = ui.element('project-bar')['frame']
first_band = ui.element('toggle:pinned')['frame']
assert first_band['y'] >= bar['y'] + bar['height'] - 1, ('The list starts under the bar', bar, first_band)
ui.capture('bar-all')

ui.axe('tap', '--id', 'project-chip:states:lody-ios', '--post-delay', '.8')
ui.wait(lambda items: 'st-streams' not in ids(items) and 'st-review' in ids(items), 'Filtering lody-ios must hide lody-cloud sessions')
assert 'toggle:pinned' not in ids(ui.state()), 'The Pinned group hides while filtered'
ui.capture('bar-filtered')

def assert_creation_project(name):
    ui.axe('tap', '--label', catalog.text('tabs.newSession'), '--post-delay', '.8')
    ui.element('create-session-input')
    project = ui.element('project')
    ui.capture('create-' + name)
    assert name in (project.get('AXLabel') or ''), f'New session must preselect {name}: {project}'
    close = catalog.text('accessibility.closeSheet', title=catalog.text('create.title'))
    ui.axe('tap', '--label', close, '--post-delay', '.8')
    ui.element('project-bar')


assert_creation_project('lody-ios')
ui.axe('tap', '--id', 'project-chip:states:lody-cloud', '--post-delay', '.5')
assert_creation_project('lody-cloud')

ui.axe('tap', '--id', 'project-chip:all', '--post-delay', '.8')
ui.wait(lambda items: 'st-streams' in ids(items) or 'toggle:states:lody-cloud' in ids(items), 'All must restore every project')

ui.axe('tap', '--id', 'magnifyingglass', '--post-delay', '.8')
ui.axe('type', 'Loro')
ui.wait(lambda items: 'project-bar' not in ids(items), 'Searching hides the project bar')
ui.axe('tap', '--label', catalog.system('clear'))
labels = {catalog.system('cancel').lower(), catalog.system('close').lower()}
dismiss = ui.wait(lambda items: next((i for i in items if i.get('type') == 'Button' and (i.get('AXLabel') or '').lower() in labels), None), 'Missing search dismiss button')
ui.axe('tap', '--label', dismiss['AXLabel'], '--post-delay', '1')
ui.element('project-bar')

switch('另一个工作区')
ui.wait(lambda items: 'solo-session' in ids(items), 'Missing the one-project workspace')
assert 'project-bar' not in ids(ui.state()), 'One project needs no project bar'
ui.capture('bar-single')
switch('Design states')
bar = ui.element('project-bar')['frame']
band = ui.wait(lambda items: next((i['frame'] for i in items if i.get('AXUniqueId') == 'toggle:pinned'), None), 'Missing the Pinned band')
assert bar['y'] + bar['height'] - 1 <= band['y'] <= bar['y'] + bar['height'] + 12, ('A bar that appears keeps the first band under it', bar, band)
print('PASS: the glass project bar filters projects, hides for search and single projects')
