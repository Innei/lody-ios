"""Drive the fixture Live Activity through running, permission, expanded and end states.

iOS hides a Live Activity from the Dynamic Island while its own app is in the
foreground, so every island capture backgrounds the app first.
"""
import re
import subprocess
import sys
import time

import catalog
from driver import UI

udid, output = sys.argv[1:3]
ui = UI(udid, output)
ALLOW = {'Allow', 'Always Allow', '允许', '始终允许'}
OPEN = {'Open', '打开'}


def status():
    return ui.element('live-activity-status').get('AXLabel') or ''


def toggle_value():
    return ui.element('live-activity:toggle').get('AXValue')


def foreground():
    subprocess.run(['xcrun', 'simctl', 'launch', udid, 'app.innei.lody'], check=True, timeout=30)


def allow(timeout, labels=ALLOW):
    """Starting an activity raises a system consent alert: once per device the first
    time, and again as a "continue to allow" prompt on later runs. Leaving either up
    would swallow the next taps and change the Lock Screen capture."""
    def button(items):
        return next((i for i in items if i.get('AXLabel') in labels and i.get('type') == 'Button'), None)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = button(ui.state())
        if found:
            frame = found['frame']
            ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1.0')
            return True
        time.sleep(.3)
    return False


def expand_island(focus_title, message):
    """The expanded island is system UI with no accessibility identifier, so it is
    opened by pressing the island's own coordinates. It then reaches the tree as a
    single Group whose label concatenates every visible string, so its contents are
    matched as substrings. A clipped row still appears in that label: only the capture
    shows whether it survived the island's height."""
    ui.axe('touch', '-x', '201', '-y', '33', '--down', '--up', '--delay', '.9')
    time.sleep(1.5)
    label = ui.wait(
        lambda items: next((found for found in (i.get('AXLabel') for i in items)
                            if found and focus_title in found), None),
        message, timeout=10,
    )
    time.sleep(1.5)  # the island animates its contents in; capture the settled frame
    return label


# A fixture activity outlives a failed run, and starting is a no-op while one exists,
# so the scene resets itself before it asserts anything.
if status() != '0 个活动':
    ui.axe('tap', '--id', 'live-activity-end', '--tap-style', 'physical')
    ui.wait(lambda items: status() == '0 个活动', 'Could not end a leftover fixture activity')

ui.axe('tap', '--id', 'live-activity-start', '--tap-style', 'physical')
allow(8)
ui.wait(lambda items: status() != '0 个活动', 'Fixture activity did not start')

assert toggle_value() == '1', 'Dynamic Island switch did not start on'
ui.axe('tap', '--id', 'live-activity:toggle', '--tap-style', 'physical')
ui.wait(lambda items: toggle_value() == '0', 'Dynamic Island switch did not turn off')
ui.axe('tap', '--id', 'live-activity:toggle', '--tap-style', 'physical')
ui.wait(lambda items: toggle_value() == '1', 'Dynamic Island switch did not turn back on')
assert status() != '0 个活动', 'Toggling the injected switch ended the fixture activity'

ui.axe('button', 'home')
time.sleep(2)
ui.capture('island-running')
running_expanded = expand_island(catalog.text('native.liveActivity.debug.title1'),
                                 'Expanded island never showed the running focus')
assert 'git push origin main --force' not in running_expanded, \
    'A running focus showed the permission command strip'
assert catalog.text('native.liveActivity.status.running') in running_expanded, \
    'Expanded island never showed the running status'
assert re.search(r'\d+:\d\d', running_expanded), \
    'Expanded island never showed the elapsed timer'
assert catalog.text('native.liveActivity.openHint') not in running_expanded, \
    'A running focus showed the permission hint'
for over_ceiling in [catalog.text('native.liveActivity.debug.title2'), catalog.text('native.liveActivity.debug.title3')]:
    assert over_ceiling not in running_expanded, \
        f'The island listed {over_ceiling!r}, which pushes it past the height that renders'
ui.capture('island-running-expanded')
ui.axe('button', 'home')
time.sleep(1)

# The Lock Screen is the one surface that keeps the live timer, so it is captured
# while a session is still running rather than only in the permission state.
ui.axe('button', 'lock')
time.sleep(2)
allow(2)
time.sleep(1)
# A locked device exposes only its own Lock Screen in the accessibility tree, so the
# capsule is evidence by capture alone, as the permission capture below also is.
ui.capture('lockscreen-running')
ui.axe('button', 'lock')
time.sleep(1)
ui.axe('swipe', '--start-x', '200', '--start-y', '780', '--end-x', '200', '--end-y', '300', '--duration', '0.4', '--post-delay', '1.0')
foreground()
ui.element('live-activity-permission')  # the unlock has to land before the tap counts
ui.axe('tap', '--id', 'live-activity-permission', '--tap-style', 'physical')
time.sleep(2)
ui.axe('button', 'home')
time.sleep(2)
ui.capture('island-permission')

expanded = expand_island(catalog.text('native.liveActivity.debug.title2'),
                         'Expanded island never showed the permission focus')
for expected in [
    catalog.text('native.liveActivity.status.permission'),
    'git push origin main --force',
]:
    assert expected in expanded, f'Expanded island never showed {expected!r}'
assert '查看' not in expanded, 'The removed accessory pill is still rendered in the expanded island'
assert catalog.text('native.liveActivity.openHint') not in expanded, \
    'The Lock Screen tap hint leaked into the island, which clips its bottom row'
for over_ceiling in [catalog.text('native.liveActivity.debug.title1'), catalog.text('native.liveActivity.debug.title3')]:
    assert over_ceiling not in expanded, \
        f'The island listed {over_ceiling!r}, which pushes it past the height that renders'
ui.capture('island-expanded')
ui.axe('button', 'home')
time.sleep(1)

ui.axe('button', 'lock')
time.sleep(2)
allow(2)
time.sleep(1)
ui.capture('lockscreen-permission')
ui.axe('button', 'lock')
time.sleep(1)
ui.axe('swipe', '--start-x', '200', '--start-y', '780', '--end-x', '200', '--end-y', '300', '--duration', '0.4', '--post-delay', '1.0')
foreground()
ui.element('live-activity-end')
ui.axe('tap', '--id', 'live-activity-end', '--tap-style', 'physical')
ui.wait(lambda items: status() == '0 个活动', 'Fixture activity did not end')
ui.capture('ended')

subprocess.run(['xcrun', 'simctl', 'openurl', udid, 'lody:///debug/sessions/x'], check=True, timeout=30)
allow(6, OPEN)
ui.wait(
    lambda items: any(i.get('AXUniqueId') == 'live-activity-status' for i in items),
    'An unavailable widget session must leave the current page in place',
)
labels = [i.get('AXLabel') or '' for i in ui.state()]
assert not any('Unmatched' in label for label in labels), 'widget deep link landed on the Unmatched Route screen'
ui.capture('deep-link')
print('PASS: island running, permission and both expanded states captured, switch toggled, activity ended, unavailable widget link preserves the current page', flush=True)
