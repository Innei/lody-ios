"""Exercise the production notification settings with resettable service outcomes."""
import sys
from driver import UI
ui = UI(sys.argv[1], sys.argv[2])

def text(value):
    return ui.wait(lambda items: next((i for i in items if value in str(i.get('AXLabel', ''))), None), f'Missing {value}')

def tap(value):
    node = text(value)
    frame = node['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2))

text('开启后接收会话完成和授权提醒')
ui.capture('permission-undetermined')
tap('开启通知')
text('通知已关闭，请在系统设置中开启')
ui.capture('permission-denied')
tap('通知设置')
ui.element('notification-settings-opened')
text('已允许通知')
ui.capture('permission-authorized')
ui.axe('tap', '--id', 'notification-reset')
text('开启后接收会话完成和授权提醒')
ui.capture('reset')
