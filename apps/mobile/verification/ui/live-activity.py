"""Drive the fixture Live Activity through running, permission and end states.

iOS hides a Live Activity from the Dynamic Island while its own app is in the
foreground, so every island capture backgrounds the app first.
"""
import subprocess
import sys
import time
from driver import UI

udid, output = sys.argv[1:3]
ui = UI(udid, output)
ALLOW = {'Allow', 'Always Allow', '允许', '始终允许'}


def status():
    return ui.element('live-activity-status').get('AXLabel') or ''


def toggle_value():
    return ui.element('live-activity:toggle').get('AXValue')


def foreground():
    subprocess.run(['xcrun', 'simctl', 'launch', udid, 'app.innei.lody'], check=True, timeout=30)


def allow(timeout):
    """Starting an activity raises a system consent alert: once per device the first
    time, and again as a "continue to allow" prompt on later runs. Leaving either up
    would swallow the next taps and change the Lock Screen capture."""
    def button(items):
        return next((i for i in items if i.get('AXLabel') in ALLOW and i.get('type') == 'Button'), None)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        found = button(ui.state())
        if found:
            frame = found['frame']
            ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1.0')
            return True
        time.sleep(.3)
    return False


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
foreground()
ui.axe('tap', '--id', 'live-activity-permission', '--tap-style', 'physical')
time.sleep(2)
ui.axe('button', 'home')
time.sleep(2)
ui.capture('island-permission')
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
print('PASS: island running and permission states captured, switch toggled, activity ended', flush=True)
