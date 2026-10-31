"""Scrolling Home springs in a project index that jumps to bands and makes room on the trailing side."""
import sys
import time
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
home_avatar = catalog.workspace_switch('我的超长工作区名称不能折行')


def ids(items):
    return {i.get('AXUniqueId') for i in items}


def frame(items, identifier):
    return next((i['frame'] for i in items if i.get('AXUniqueId') == identifier), None)


ui.wait(lambda items: any(i.get('AXLabel') == home_avatar for i in items), 'Missing workspace avatar')
prefix = catalog.text('inbox.workspaceSwitch.accessibility', name='\0').split('\0')[0]
menu = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').startswith(prefix)), None), 'Missing workspace menu')
ui.axe('tap', '--label', menu['AXLabel'], '--post-delay', '.8')
ui.axe('tap', '--label', 'Design states', '--post-delay', '1.2')
ui.element('project-chip:states:lody-ios')
assert 'project-index' not in ids(ui.state()), 'The index stays away until the list scrolls'
resting = ui.element('st-review')['frame']['width']

screen = ui.state()[0]['frame']['width']
ui.axe('drag', '--start-x', str(screen / 2), '--start-y', '700', '--end-x', str(screen / 2), '--end-y', '520', '--duration', '.4')
shown = ui.wait(lambda items: items if 'project-index' in ids(items) else None, 'Scrolling must show the project index', timeout=4)
row = frame(shown, 'st-review')
if row:
    assert abs((resting - row['width']) - 40) <= 2, ('The list gives up 40 pt while the index shows', resting, row['width'])
ui.capture('index-shown')

ui.axe('tap', '--id', 'project-index:states:lody-cloud', '--post-delay', '1')
bar = ui.element('project-bar')['frame']
band = ui.wait(lambda items: frame(items, 'toggle:states:lody-cloud'), 'Missing the lody-cloud band')
assert abs(band['y'] - (bar['y'] + bar['height'])) <= 2, ('A tapped index item puts its band under the bar', bar, band)
ui.capture('index-jumped')

time.sleep(4.5)
ui.wait(lambda items: 'project-index' not in ids(items), 'The index hides after scrolling stops')
assert abs(ui.element('st-streams')['frame']['width'] - resting) <= 1, 'The trailing room returns when the index hides'
print('PASS: the project index appears while scrolling, jumps to bands and returns the trailing room')
