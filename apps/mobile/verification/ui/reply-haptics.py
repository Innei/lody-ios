"""Offline adjustable reply demo. Pulse counts prove scheduling, not physical feel."""
import sys
import time
from driver import UI

ui = UI(*sys.argv[1:])


def tap(identifier):
    ui.axe('tap', '--id', identifier, '--tap-style', 'physical', '--post-delay', '.2')


def wait_status(expected):
    ui.wait(lambda items: any(expected in (item.get('AXLabel') or '') for item in items),
            f'Missing status: {expected}', timeout=12)


def choose(identifier, value):
    tap(identifier)
    ui.axe('tap', '--label', value, '--tap-style', 'physical', '--post-delay', '.3')


ui.capture('parameters')
tap('reply-haptics-start')
wait_status('完成 · 3 次触感')
ui.capture('streamed')
choose('delay', '6000')
tap('reply-haptics-start')
wait_status('完成 · 0 次触感')
ui.capture('outside-window')
choose('delay', '0')
# Speed is lower in the parameter list.
ui.axe('swipe', '--start-x', '200', '--start-y', '650', '--end-x', '200', '--end-y', '350', '--duration', '.4', '--post-delay', '.3')
choose('speed', '0')
ui.axe('swipe', '--start-x', '200', '--start-y', '300', '--end-x', '200', '--end-y', '700', '--duration', '.4', '--post-delay', '.3')
tap('reply-haptics-start')
wait_status('完成 · 1 次触感')
ui.capture('single-batch')
choose('delay', '2000')
tap('reply-haptics-start')
tap('reply-haptics-stop')
time.sleep(2.2)
wait_status('已停止')
ui.capture('stopped')
print('PASS: streamed, late, single-batch and cancelled replies; real-device haptics remain manual')
