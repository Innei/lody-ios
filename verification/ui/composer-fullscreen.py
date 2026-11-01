"""The sheet's grabber drags the chat input to full screen with a format bar, back down, and collapses the sheet with the keyboard following."""
import sys
import threading
import time
from driver import UI

ui = UI(*sys.argv[1:])


def frame(identifier):
    return ui.element(identifier)['frame']


# AXe also lists hidden UIKit views, so a clipped control counts only when it has height.
def visible(identifier):
    return any(item.get('AXUniqueId') == identifier and item.get('frame', {}).get('height', 0) > 0 for item in ui.state())


def drag_grabber(to_y, duration='.6'):
    grip = frame('session-grabber')
    x = grip['x'] + grip['width'] / 2
    y = grip['y'] + grip['height'] / 2
    ui.axe('swipe', '--start-x', str(x), '--start-y', str(y), '--end-x', str(x), '--end-y', str(to_y),
           '--duration', duration, '--delta', '2', '--post-delay', '.9')


ui.axe('tap', '--id', 'session-input', '--tap-style', 'physical', '--post-delay', '.8')
ui.axe('type', ' '.join(f'word{index}' for index in range(60)))
ui.wait(lambda items: visible('session-grabber'), 'The open sheet has no grabber')
assert not visible('session-expand'), 'The expand button must be gone'
inline = frame('session-input')
inline_top = frame('session-grabber')['y']
assert inline['height'] <= 142, f'Inline input exceeded its cap: {inline}'
assert not visible('composer-format-bold'), 'Format bar is visible before expanding'
ui.capture('overflow')

drag_grabber(120)
# The sheet's chrome (attachments, grabber, format bar, toolbar) can absorb most of a short host's height, so growth is measured at the sheet's top edge.
ui.wait(lambda items: frame('session-grabber')['y'] < inline_top - 30 and visible('composer-format-bold'),
        'Dragging the grabber up did not open full screen with the format bar')
full = frame('session-input')
assert full['height'] >= inline['height'] - 1, f'Full-screen input shrank: {full}'
for name in ['heading', 'bold', 'italic', 'strikethrough', 'code', 'bulletList', 'quote']:
    assert visible(f'composer-format-{name}'), f'Format bar lacks {name}'
ui.capture('fullscreen')

ui.axe('tap', '--id', 'composer-format-bold', '--post-delay', '.3')
ui.axe('type', 'bold')
ui.wait(lambda items: 'bold' in (ui.element('session-input').get('AXValue') or ''), 'Typing after Bold did not reach the input')
ui.capture('formatted')

grip = frame('session-grabber')
drag_grabber(grip['y'] + 260)
ui.wait(lambda items: frame('session-input')['height'] <= 142 and not visible('composer-format-bold'),
        'Dragging the grabber down did not return to the default sheet')
assert visible('session-send'), 'Dragging down from full screen must keep the sheet open'
ui.capture('collapsed')

ui.axe('tap', '--id', 'session-grabber', '--post-delay', '.9')
ui.wait(lambda items: frame('session-grabber')['y'] < inline_top - 30 and visible('composer-format-bold'), 'Tapping the grabber did not open full screen')
ui.axe('tap', '--id', 'session-send', '--post-delay', '1.2')
ui.wait(lambda items: not visible('composer-format-bold') and not (ui.element('session-input').get('AXValue') or ''),
        'Send did not collapse and clear the full-screen input')
ui.capture('sent')

def keyboard_top():
    keyboard = ui.visible_keyboard(ui.state())
    return keyboard['y'] if keyboard else None


resting_keyboard = keyboard_top()
assert resting_keyboard, 'The software keyboard must be up before collapsing the sheet'
sheet = frame('session-input')
title = frame('chat-navigation-title')
grip = frame('session-grabber')
drag_grabber(grip['y'] + 30, duration='1.2')
ui.wait(lambda items: abs(frame('session-input')['height'] - sheet['height']) <= 1 and (keyboard_top() or 0) == resting_keyboard,
        'A short slow collapse drag must spring back to the sheet with the keyboard up')
ui.capture('collapse-cancelled')

grip = frame('session-grabber')
x = grip['x'] + grip['width'] / 2
y = grip['y'] + grip['height'] / 2
finger_end = y + 160
assert finger_end < resting_keyboard, 'The collapse drag must stay above the resting keyboard to prove it follows from the start'
drag = threading.Thread(target=ui.axe, args=('swipe', '--start-x', str(x), '--start-y', str(y), '--end-x', str(x), '--end-y', str(finger_end),
                                             '--duration', '4', '--delta', '2'))
resting_bottom = sheet['y'] + sheet['height']
drag.start()
time.sleep(2.2)
mid_input = frame('session-input')
mid_title = frame('chat-navigation-title')
ui.capture('collapse-midway')
drag.join()
# The keyboard renders out of process and its accessibility frame lags an interactive drag; the composer is pinned to its top edge.
mid_bottom = mid_input['y'] + mid_input['height']
assert mid_bottom > resting_bottom + 30, \
    f'The keyboard must follow the grabber before the finger reaches it; composer bottom resting {resting_bottom}, midway {mid_bottom}'
assert abs(mid_title['y'] - title['y']) <= 1, f'A collapse drag must not drag the hosting sheet; title {title}, midway {mid_title}'
assert 48 < mid_input['height'] < sheet['height'] - 10, f'The input must shrink with the drag; sheet {sheet}, midway {mid_input}'
ui.wait(lambda items: abs(frame('session-input')['height'] - 48) <= 1 and not ui.visible_keyboard(items),
        'Releasing a collapse drag must land on the capsule with the keyboard down')
ui.capture('closed')
print('PASS: grabber drag to full screen with format bar, drag back, tap toggle, send collapse, cancelled collapse, and keyboard-following collapse')
