"""Real native links open catalog sessions above one Home, including repeated opens and JS restarts."""
import json
import os
import subprocess
import sys
import time
from driver import UI
import catalog
from inspector import inspector

udid = sys.argv[1]
ui = UI(udid, sys.argv[2])


def stack(expected):
    def matches(items):
        assert not any(i.get('AXUniqueId') == 'redbox-dismiss' for i in items), 'React Native reported a runtime error'
        probe = next((i for i in items if i.get('AXUniqueId') == 'ui-navigation-state'), None)
        return probe is not None and json.loads(probe['AXValue']) == expected
    ui.wait(matches, f'Expected navigation stack {expected}')


def swipe_back():
    ui.axe('swipe', '--start-x', '1', '--start-y', '650', '--end-x', '350',
           '--end-y', '650', '--duration', '.5', '--post-delay', '1')


def home(name):
    stack(['index'])
    assert not any(i.get('AXUniqueId') == 'BackButton' for i in ui.state()), 'Home has a back button'
    swipe_back()
    stack(['index'])
    ui.capture(name)


def open_url(path):
    subprocess.run(['xcrun', 'simctl', 'openurl', udid, f'lody:///{path}'], check=True, timeout=30)
    # First use of the custom scheme may show a system confirmation.
    time.sleep(1)
    for item in ui.state():
        if item.get('type') == 'Button' and item.get('AXLabel') in ['Open', '打开']:
            ui.axe('tap', '--label', item['AXLabel'], '--post-delay', '1')
            break


def session(title):
    stack(['index', 'presented/[presentationId]'])
    ui.element('session-input')
    ui.wait(lambda items: any(title in (i.get('AXLabel') or '') for i in items), f'Missing session title {title}')


home('initial-home')
# Exercise the production row push, then cancel an edge pop before completing
# it. The recording also covers toolbar retirement during the push itself.
ui.axe('tap', '--id', 'ui-design', '--post-delay', '.6')
session('首页交互设计')
search_label = catalog.text('search.field.placeholder')


def no_home_search():
    assert not any(i.get('AXValue') == search_label for i in ui.state()), 'Home search leaked over the session'


no_home_search()
ui.capture('toolbar-pushed')
ui.axe('swipe', '--start-x', '1', '--start-y', '650', '--end-x', '65',
       '--end-y', '650', '--duration', '1', '--post-delay', '.6')
session('首页交互设计')
no_home_search()
ui.capture('toolbar-pop-cancelled')
swipe_back()
home('toolbar-returned')
ui.wait(lambda items: any(i.get('AXValue') == search_label for i in items), 'Home search did not return')

for index in range(2):
    open_url('ui-home/sessions/ui-design')
    session('首页交互设计')
    ui.capture(f'linked-session-{index}')
    swipe_back()
    home(f'returned-{index}')

# A fresh link while a session is already open replaces the external path above Home.
open_url('ui-home/sessions/ui-design')
session('首页交互设计')
open_url('ui-home/sessions/ui-chat')
session('纯对话草稿')
ui.capture('relinked-session')
ui.axe('tap', '--id', 'BackButton', '--post-delay', '1')
home('relinked-return')

# Sheets and an old workspace must not remain below the newly opened session.
ui.axe('tap', '--label', catalog.text('tabs.settings'), '--post-delay', '1')
ui.element('account')
open_url('other/sessions/ui-design')
session('首页交互设计')
swipe_back()
home('workspace-return')
avatar = catalog.text('inbox.workspaceSwitch.accessibility', name='另一个工作区')
ui.wait(lambda items: any(i.get('AXLabel') == avatar for i in items), 'Link did not select the target workspace')

# Missing Router pages return to the existing root, never replace the top with another Home.
for _ in range(2):
    open_url('missing-page')
    home('unknown-return')

# Expo Linking retains the last native URL. Reload JS from Home to exercise the
# initial-URL path with no mounted coordinator, while keeping --ui-verify active.
# Launching a terminated dev client via openurl would lose that native safety flag.
open_url('ui-home/sessions/ui-design')
session('首页交互设计')
swipe_back()
home('before-restart')
inspector(udid, os.environ['LODY_UI_METRO_PORT'], 'Page.reload')
session('首页交互设计')
ui.capture('restart-session')
swipe_back()
home('restart-return')
print('PASS: warm, repeated, sheet, workspace and initial-URL links after JS restart return to one Home; unknown URLs and root edge swipes cannot add or reveal another page.')
