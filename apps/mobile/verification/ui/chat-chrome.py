"""Connection status and a 30-point scroll visual aligned with send."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def center_x(frame):
    return frame['x'] + frame['width'] / 2


def mid_y(frame):
    return frame['y'] + frame['height'] / 2


def max_y(frame):
    return frame['y'] + frame['height']


def chrome_center():
    transcript = ui.element('chat-transcript')
    return center_x(transcript['frame'])


ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Connecting Chrome', '--post-delay', '.5')
status = ui.element('chat-connection-status')
assert status.get('AXLabel') == catalog.text('native.chat.connection.connecting')
assert 'chat-scroll-to-bottom' not in ui.axe('describe-ui'), 'Connecting at the tail must not show scroll-to-bottom'
assert abs(center_x(status['frame']) - chrome_center()) <= 1, 'Connecting alone is not on the composer center'
assert 28 <= status['frame']['height'] <= 34, 'Status should fit one line with compact padding'
ui.capture('connecting')

ui.axe('swipe', '--start-x', '200', '--start-y', '300', '--end-x', '200', '--end-y', '700', '--duration', '1', '--post-delay', '1')
status = ui.element('chat-connection-status')
scroll = ui.element('chat-scroll-to-bottom')
assert abs(center_x(status['frame']) - chrome_center()) <= 1, 'Showing scroll moved the connection status'
send = ui.element('session-send')['frame']
assert abs(center_x(scroll['frame']) - center_x(send)) <= 1, 'Scroll does not share send center'
assert abs(max_y(status['frame']) - max_y(scroll['frame'])) <= 1, 'Paired glasses do not share a baseline'
assert abs(scroll['frame']['width'] - 30) <= 1
assert abs(scroll['frame']['height'] - 30) <= 1
ui.capture('connecting-and-scroll')

ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Paused Chrome', '--post-delay', '.5')
paused = ui.element('chat-connection-status')
assert paused.get('AXLabel') == catalog.text('native.chat.connection.paused')
ui.element('chat-scroll-to-bottom')
ui.capture('paused-and-scroll')

ui.axe('tap', '-x', str(center_x(scroll['frame']) + 21), '-y', str(mid_y(scroll['frame'])), '--post-delay', '1.2')
paused = ui.element('chat-connection-status')
assert 'chat-scroll-to-bottom' not in ui.axe('describe-ui'), 'Returning to the tail must drop scroll-to-bottom'
assert abs(center_x(paused['frame']) - chrome_center()) <= 1, 'Paused alone did not return to center'
ui.capture('paused')

ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Clear Chrome', '--post-delay', '.5')
assert 'chat-connection-status' not in ui.axe('describe-ui'), 'Clearing chrome must remove the status glass'
ui.axe('swipe', '--start-x', '200', '--start-y', '300', '--end-x', '200', '--end-y', '700', '--duration', '1', '--post-delay', '1')
scroll_only = ui.element('chat-scroll-to-bottom')['frame']
assert abs(scroll_only['x'] - scroll['frame']['x']) <= 1, 'Hiding status moved the scroll action'
ui.capture('scroll-only')
ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Connecting Chrome', '--post-delay', '.5')
ui.axe('tap', '--id', 'session-input', '--post-delay', '1')
ui.wait(lambda items: any((i.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar') for i in items),
        'Software keyboard did not appear')
status_keyboard = ui.element('chat-connection-status')['frame']
scroll_keyboard = ui.element('chat-scroll-to-bottom')['frame']
input_frame = ui.element('session-input')['frame']
assert status_keyboard['y'] < status['frame']['y'] - 100, 'Chrome did not follow the raised composer'
assert abs(max_y(status_keyboard) - max_y(scroll_keyboard)) <= 1, 'Keyboard separated the chrome baseline'
send_keyboard = ui.element('session-send')['frame']
assert abs(center_x(scroll_keyboard) - center_x(send_keyboard)) <= 1, 'Keyboard broke center alignment with send'
assert scroll_keyboard['y'] + scroll_keyboard['height'] < input_frame['y'], 'Scroll action overlaps the input'
ui.capture('keyboard')
print('PASS: 30-point scroll visual aligned with send, independent status, shared baseline, and collapse')
