"""Home keeps the workspace avatar and view/settings group in the navigation bar, the integrated bottom search beside the create button, long-press Settings opens Debug, and the settings sheet hosts remote and archived pages."""
import sys
import time
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])


def commit(text):
    ui.axe('type', text)
    # A Chinese App Language brings up the pinyin IME, which holds Latin letters as
    # composition until Return commits them verbatim.
    if catalog.LANGUAGE != 'en':
        ui.axe('key', '40')


def dismiss_search():
    labels = {catalog.system('cancel').lower(), catalog.system('close').lower()}
    button = ui.wait(lambda items: next((i for i in items if i.get('type') == 'Button' and (i.get('AXLabel') or '').lower() in labels), None), 'Missing search dismiss button')
    ui.axe('tap', '--label', button['AXLabel'], '--post-delay', '1')


# expo-router's bottom toolbar drops accessibilityLabel (RouterToolbarModule sets the
# UIView label, not routerAccessibilityLabel), so the create button is located by position.
def tap_create():
    buttons = [i for i in ui.state() if i.get('type') == 'Button' and i.get('frame')]
    button = max(buttons, key=lambda i: i['frame']['y'])
    frame = button['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1')


workspace_name = '我的超长工作区名称不能折行'
avatar_label = catalog.text('inbox.workspaceSwitch.accessibility', name=workspace_name)


def home_ready():
    ui.wait(lambda items: any(i.get('AXLabel') == avatar_label for i in items), 'Missing workspace avatar')


def assert_swipe_has_no_selection(action_label):
    ui.wait(lambda items: any(i.get('AXLabel') == action_label for i in items), f'Missing swipe action {action_label}')
    row = ui.element('ui-design')
    assert 'selected' not in str(row.get('traits') or []).lower(), row


close_create = catalog.text('accessibility.closeSheet', title=catalog.text('create.title'))

home_ready()
if any(i.get('AXUniqueId') == 'xmark' and i.get('AXLabel') == catalog.system('close') for i in ui.state()):
    ui.axe('tap', '--id', 'xmark', '--post-delay', '1')
ui.capture('home')
row = ui.element('ui-design')['frame']
y = row['y'] + row['height'] / 2
left = row['x'] + 12
right = row['x'] + row['width'] - 12
middle = row['x'] + row['width'] / 2
ui.axe('swipe', '--start-x', str(right), '--start-y', str(y),
       '--end-x', str(middle), '--end-y', str(y), '--duration', '.6', '--post-delay', '.5')
archive_label = catalog.text('session.action.archive')
assert_swipe_has_no_selection(archive_label)
ui.capture('trailing-action')
ui.axe('swipe', '--start-x', str(middle), '--start-y', str(y),
       '--end-x', str(right), '--end-y', str(y), '--duration', '.4', '--post-delay', '.4')
ui.axe('swipe', '--start-x', str(left), '--start-y', str(y),
       '--end-x', str(middle), '--end-y', str(y), '--duration', '.6', '--post-delay', '.5')
pin_label = catalog.text('session.action.pin')
assert_swipe_has_no_selection(pin_label)
ui.capture('leading-action')
ui.axe('swipe', '--start-x', str(middle), '--start-y', str(y),
       '--end-x', str(left), '--end-y', str(y), '--duration', '.4', '--post-delay', '.4')

# Catalog updates arrive continuously through the CRDT runtime. Pulling the
# inbox must only bounce; a refresh control would stay active because there is
# no request lifecycle for React to finish.
before_pull = ui.element('ui-design')['frame']['y']
ui.axe('swipe', '--start-x', '200', '--start-y', str(before_pull + 20),
       '--end-x', '200', '--end-y', str(before_pull + 240), '--duration', '.7', '--post-delay', '1')
after_pull = ui.element('ui-design')['frame']['y']
assert abs(after_pull - before_pull) <= 2, 'Pulling the CRDT inbox left a refresh control active'

tap_create()
ui.element('create-session-input')
ui.element('create-type')
ui.capture('create')
ui.wait(lambda items: any('Fixture Agent' in (i.get('AXLabel') or '') for i in items), 'Creation options did not load')
# Both tabs expose the machine, including a local project's pinned machine.
ui.axe('tap', '--id', 'machine', '--post-delay', '.6')
ui.wait(lambda items: any('Fixture Mac' in (i.get('AXLabel') or '') for i in items), 'Project machine picker is empty')
ui.axe('tap', '--id', 'ui', '--post-delay', '.6')
ui.element('create-type')

# Exercise actual paging and a cancelled interactive sheet dismissal, not only
# segment taps. The video records the intervening cell motion.
for index in [1, 0, 1, 0]:
    before = ui.element('agent')['frame']
    width = ui.element('create-session-input')['frame']['width']
    start, end = (width - 20, 20) if index == 1 else (20, width - 20)
    y = before['y'] + before['height'] / 2
    ui.axe('swipe', '--start-x', str(start), '--start-y', str(y),
           '--end-x', str(end), '--end-y', str(y), '--duration', '.7', '--post-delay', '.6')
    ui.element('create-type')
    assert any(i.get('AXUniqueId') == 'project' for i in ui.state()) == (index == 0), 'Swipe did not commit the expected page'
    after = ui.element('agent')['frame']
    ui.capture(f'create-swipe-{index}')
    time.sleep(.4)
    settled = ui.element('agent')['frame']
    assert abs(settled['y'] - after['y']) < 1 and abs(settled['height'] - after['height']) < 1, 'Cell geometry changed after paging settled'

header = next(item['frame'] for item in ui.state() if item.get('AXLabel') == close_create)
x, y = header['x'] + header['width'] / 2, header['y'] + header['height'] / 2
ui.axe('swipe', '--start-x', str(x), '--start-y', str(y),
       '--end-x', str(x), '--end-y', str(y + 45), '--duration', '1', '--post-delay', '1')
ui.element('create-session-input')
ui.element('create-type')
ui.capture('create-dismiss-cancelled')


def tap_create_type(index):
    frame = ui.element('create-type')['frame']
    x = frame['x'] + frame['width'] * (0.25 if index == 0 else 0.75)
    y = frame['y'] + frame['height'] / 2
    ui.axe('tap', '-x', str(x), '-y', str(y), '--post-delay', '1')


tap_create_type(1)
ui.wait(
    lambda items: any(i.get('AXUniqueId') == 'machine' for i in items),
    'Chat page must show a computer row',
)
assert not any(i.get('AXUniqueId') == 'project' for i in ui.state())
ui.capture('create-chat')
tap_create_type(0)
ui.element('project')
# Expand from the close control so the title segment does not eat the swipe.
header = next(item['frame'] for item in ui.state() if item.get('AXLabel') == close_create)
start_x = header['x'] + header['width'] / 2
ui.axe(
    'swipe',
    '--start-x', str(start_x),
    '--start-y', str(header['y'] + header['height'] / 2),
    '--end-x', str(start_x),
    '--end-y', '80',
    '--duration', '.6',
    '--post-delay', '.8',
)
expanded_header = next(item['frame'] for item in ui.state() if item.get('AXLabel') == close_create)
assert expanded_header['y'] < header['y'] - 100, 'Creation sheet did not expand to the full detent'
ui.capture('create-full')

# A repository with no existing sessions is discoverable, and can run on a
# teammate's shared machine. Local projects continue to pin their own machine.
ui.axe('tap', '--id', 'project', '--post-delay', '.5')
ui.element('github:LodyAI/FreshProject')
ui.capture('github-repositories')
ui.axe('tap', '--id', 'github:LodyAI/FreshProject', '--post-delay', '.7')
ui.axe('tap', '--id', 'machine', '--post-delay', '.5')
ui.element('shared')
ui.capture('github-machines')
ui.axe('tap', '--id', 'shared', '--post-delay', '.7')
assert 'Teammate Mac' in (ui.element('machine').get('AXLabel') or '')
assert 'Teammate Agent' in (ui.element('agent').get('AXLabel') or '')
ui.axe('tap', '--label', catalog.text('create.branch.label'))
commit('main')
ui.capture('github-create')
# Return through the picker while preserving the native sheet navigation.
ui.axe('tap', '--id', 'project', '--post-delay', '.5')
ui.axe('tap', '--id', 'ui:local:lody', '--post-delay', '.7')
ui.axe('tap', '--id', 'machine', '--post-delay', '.5')
assert not any(i.get('AXUniqueId') == 'shared' for i in ui.state()), 'Local project offered another machine'
ui.axe('tap', '--id', 'ui', '--post-delay', '.5')
ui.element('create-type')

ui.axe('tap', '--label', close_create, '--post-delay', '1')
home_ready()
tap_create()
ui.element('create-session-input')
ui.axe('tap', '--label', close_create, '--post-delay', '1')
ui.capture('returned')

ui.axe('tap', '--id', 'magnifyingglass', '--post-delay', '.8')
commit('Search')
ui.element('ui-search')
assert not any(i.get('AXUniqueId') == 'ui-design' for i in ui.state())
ui.capture('search')
ui.axe('tap', '--label', catalog.system('clear'))
commit('Lody')
ui.element('project:ui:local:lody')
ui.capture('project-search')
ui.axe('tap', '--label', catalog.system('clear'))
commit('NoSuchSession')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('search.placeholder.noMatch') for i in items), 'Missing empty search state')
ui.capture('empty-search')
dismiss_search()
ui.element('ui-design')
assert not any(i.get('AXUniqueId') == 'ui-search' for i in ui.state())
ui.capture('cancelled')

view_label = catalog.text('inbox.settings.section.view')
ui.axe('tap', '--label', view_label, '--post-delay', '.8')
ui.capture('view-menu')
ui.axe('tap', '--label', catalog.text('inbox.settings.view.activity'), '--post-delay', '.8')
ui.element('ui-design')
assert not any(i.get('AXUniqueId') == 'toggle:ui:local:lody' for i in ui.state())
ui.capture('activity-view')
ui.axe('tap', '--label', view_label, '--post-delay', '.8')
ui.axe('tap', '--label', catalog.text('inbox.settings.view.chat'), '--post-delay', '.8')
ui.element('ui-chat')
assert not any(i.get('AXUniqueId') == 'toggle:ui:local:lody' for i in ui.state())
ui.capture('chat-view')
ui.axe('tap', '--label', view_label, '--post-delay', '.8')
ui.axe('tap', '--label', catalog.text('inbox.settings.sort.activity'), '--post-delay', '.8')
ui.axe('tap', '--label', view_label, '--post-delay', '.8')
ui.axe('tap', '--label', catalog.text('inbox.settings.view.projects'), '--post-delay', '.8')
ui.element('toggle:chat')
project = ui.element('toggle:ui:local:lody')
# The outline parent is an accessibility container; its content view carries the label.
assert any('Lody iOS' in (child.get('AXLabel') or '') for child in project.get('children') or []), project
assert catalog.system('collapse') in (project.get('custom_actions') or []), project


# The outline disclosure accessory shares the parent's identifier, so tap by frame.
def tap_project():
    frame = ui.element('toggle:ui:local:lody')['frame']
    ui.axe('tap', '-x', str(frame['x'] + 120), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.8')


tap_project()
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'ui-design' for i in items), 'Collapsing the project must hide its sessions')
ui.capture('project-collapsed')
tap_project()
ui.element('ui-design')
ui.capture('project-expanded')

empty = ui.element('project:ui:empty')
empty_label = empty.get('AXLabel') or ''
if not empty_label:
    empty_label = ' '.join(
        child.get('AXLabel') or '' for child in empty.get('children') or []
    )
assert '0' in empty_label, empty


def hold(identifier):
    frame = ui.element(identifier)['frame']
    ui.axe(
        'touch',
        '-x', str(frame['x'] + min(120, frame['width'] / 2)),
        '-y', str(frame['y'] + frame['height'] / 2),
        '--down', '--up', '--delay', '1.2',
    )
    time.sleep(1)


hold('project:ui:empty')
ui.wait(
    lambda items: any(catalog.text('project.action.copyPath') in (i.get('AXLabel') or '') for i in items),
    'Project long-press must show the copy-path action',
)
assert any(catalog.text('project.action.open') in (i.get('AXLabel') or '') for i in ui.state())
assert any(catalog.text('session.action.newSession') in (i.get('AXLabel') or '') for i in ui.state())
ui.capture('project-menu')
ui.axe('tap', '-x', '24', '-y', '120', '--post-delay', '.6')

hold('ui-design')
ui.wait(
    lambda items: any(catalog.text('session.action.pin') in (i.get('AXLabel') or '') for i in items),
    'Session long-press must show pin',
)
assert any(catalog.text('session.action.archive') in (i.get('AXLabel') or '') for i in ui.state())
user_turn = ui.wait(
    lambda items: next((i for i in items if (i.get('AXLabel') or '') == '设计首页'), None),
    'Session long-press must preview the cached user turn',
)
answer = next((i for i in ui.state() if (i.get('AXLabel') or '') == '用项目分组。'), None)
assert answer, 'Preview must show the assistant answer as readable text'
assert user_turn['frame']['width'] >= 200, user_turn
assert answer['frame']['width'] >= 200, answer
ui.capture('session-menu')
ui.axe('tap', '-x', '24', '-y', '120', '--post-delay', '.6')

settings_label = catalog.text('tabs.settings')


def settings_button():
    return ui.wait(
        lambda items: next((i for i in items if i.get('type') == 'Button' and i.get('AXLabel') == settings_label), None),
        'Missing settings button',
    )


def hold_settings():
    frame = settings_button()['frame']
    ui.axe(
        'touch',
        '-x', str(frame['x'] + frame['width'] / 2),
        '-y', str(frame['y'] + frame['height'] / 2),
        '--down', '--up', '--delay', '1.2',
    )
    time.sleep(1)


hold_settings()
ui.element('permission-preview')
assert not any(i.get('AXUniqueId') == 'account' for i in ui.state())
ui.capture('debug')
ui.axe('tap', '--id', 'BackButton', '--post-delay', '1')
home_ready()
assert not any(i.get('AXUniqueId') == 'permission-preview' for i in ui.state())


def tap_sheet_back():
    # The inbox gear behind the sheet shares the Settings label; the back button is the leftmost.
    buttons = [i for i in ui.state() if i.get('type') == 'Button' and i.get('AXLabel') == settings_label]
    frame = min(buttons, key=lambda i: i['frame']['x'])['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.5')
ui.axe('tap', '--label', settings_label, '--post-delay', '1')
ui.element('account')
ui.element('archived')
ui.capture('settings')
for kind in ('machine', 'agent', 'mcp'):
    row = ui.element(f'remote-{kind}')
    assert catalog.text(f'settings.remote.{kind}') in (row.get('AXLabel') or '')
    assert row['frame']['height'] >= 44
    ui.axe('tap', '--id', f'remote-{kind}', '--post-delay', '.5')
    ui.element('retry')
    ui.wait(lambda items: any(catalog.text('settings.remote.loadFailed') in (item.get('AXLabel') or '') for item in items), 'Remote settings must show a recoverable offline error')
    ui.capture(f'remote-{kind}')
    tap_sheet_back()
    ui.element(f'remote-{kind}')
row = ui.element('archived')
assert catalog.text('settings.archived.title') in (row.get('AXLabel') or '')
ui.axe('tap', '--id', 'archived', '--post-delay', '.8')
archived = ui.element('ui-search')
spoken = ' '.join((i.get('AXLabel') or '') for i in [archived, *(archived.get('children') or [])])
assert '搜索历史会话 Search' in spoken and catalog.text('inbox.badge.archived') in spoken, spoken
assert archived['frame']['height'] >= 44
ui.capture('archived-sessions')
tap_sheet_back()
ui.element('archived')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=settings_label), '--post-delay', '1')
home_ready()
assert not any(i.get('AXUniqueId') == 'archived' for i in ui.state())
ui.capture('settings-closed')
print('Create opens repeatedly from the bottom toolbar; integrated search finds archived sessions and cancels back; the view menu regroups; long-press Settings opens Debug and returns; the settings sheet pushes remote and archived pages and closes back to the inbox.')
