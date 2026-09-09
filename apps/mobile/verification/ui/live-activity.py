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


def status():
    return ui.element('live-activity-status').get('AXLabel') or ''


def foreground():
    subprocess.run(['xcrun', 'simctl', 'launch', udid, 'app.innei.lody'], check=True, timeout=30)


ui.axe('tap', '--id', 'live-activity-start', '--tap-style', 'physical')
ui.wait(lambda items: status() != '0 个活动', 'Fixture activity did not start')
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
time.sleep(3)
ui.capture('lockscreen-permission')
ui.axe('button', 'lock')
time.sleep(1)
ui.axe('swipe', '--start-x', '200', '--start-y', '780', '--end-x', '200', '--end-y', '300', '--duration', '0.4', '--post-delay', '1.0')
foreground()
ui.element('live-activity-end')
ui.axe('tap', '--id', 'live-activity-end', '--tap-style', 'physical')
ui.wait(lambda items: status() == '0 个活动', 'Fixture activity did not end')
ui.capture('ended')
print('PASS: running and permission island states captured, activity ended', flush=True)
