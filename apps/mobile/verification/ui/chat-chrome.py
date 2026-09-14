"""Connection chrome shares the scroll-to-bottom baseline and 22-point pairing."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def center_x(frame):
    return frame['x'] + frame['width'] / 2


def mid_y(frame):
    return frame['y'] + frame['height'] / 2


def group_center(left, right):
    return (left['x'] + right['x'] + right['width']) / 2


def chrome_center():
    transcript = ui.element('chat-transcript')
    return center_x(transcript['frame'])


ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Connecting Chrome', '--post-delay', '.5')
status = ui.element('chat-connection-status')
assert status.get('AXLabel') == catalog.text('native.chat.connection.connecting')
assert 'chat-scroll-to-bottom' not in ui.axe('describe-ui'), 'Connecting at the tail must not show scroll-to-bottom'
assert abs(center_x(status['frame']) - chrome_center()) <= 1, 'Connecting alone is not on the composer center'
assert abs(status['frame']['height'] - 44) <= 1
ui.capture('connecting')

ui.axe('swipe', '--start-x', '200', '--start-y', '300', '--end-x', '200', '--end-y', '700', '--duration', '1', '--post-delay', '1')
status = ui.element('chat-connection-status')
scroll = ui.element('chat-scroll-to-bottom')
assert abs(scroll['frame']['x'] - status['frame']['x'] - status['frame']['width'] - 22) <= 1, \
    'Paired glasses do not keep a half-button gap'
assert abs(mid_y(status['frame']) - mid_y(scroll['frame'])) <= 1, 'Paired glasses do not share a baseline'
assert abs(group_center(status['frame'], scroll['frame']) - chrome_center()) <= 1, \
    'Paired glasses are not centered as a group'
assert abs(scroll['frame']['width'] - 22) <= 1 and abs(scroll['frame']['height'] - 22) <= 1
ui.capture('connecting-and-scroll')

ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Paused Chrome', '--post-delay', '.5')
paused = ui.element('chat-connection-status')
assert paused.get('AXLabel') == catalog.text('native.chat.connection.paused')
ui.element('chat-scroll-to-bottom')
ui.capture('paused-and-scroll')

ui.axe('tap', '--id', 'chat-scroll-to-bottom', '--post-delay', '1.2')
paused = ui.element('chat-connection-status')
assert 'chat-scroll-to-bottom' not in ui.axe('describe-ui'), 'Returning to the tail must drop scroll-to-bottom'
assert abs(center_x(paused['frame']) - chrome_center()) <= 1, 'Paused alone did not return to center'
ui.capture('paused')

ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Clear Chrome', '--post-delay', '.5')
assert 'chat-connection-status' not in ui.axe('describe-ui'), 'Clearing chrome must remove the status glass'
print('PASS: connecting/paused chrome, shared baseline, 22-point pairing, and collapse')
