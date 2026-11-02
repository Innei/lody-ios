"""The sheet's grabber drags the chat input to full screen with a format bar, back down, and collapses the sheet with the keyboard following."""
import json
import sys
import threading
import time
from driver import UI

ui = UI(*sys.argv[1:])


def frame(identifier, items=None):
    if items is None:
        return ui.element(identifier)['frame']
    return next(item['frame'] for item in items if item.get('AXUniqueId') == identifier)


# AXe also lists hidden UIKit views, so a clipped control counts only when it has height.
def visible(identifier, items=None):
    return any(item.get('AXUniqueId') == identifier and item.get('frame', {}).get('height', 0) > 0
               for item in (ui.state() if items is None else items))


def drag_grabber(to_y, duration='.6'):
    grip = frame('session-grabber')
    x = grip['x'] + grip['width'] / 2
    y = grip['y'] + grip['height'] / 2
    ui.axe('drag', '--start-x', str(x), '--start-y', str(y), '--end-x', str(x), '--end-y', str(to_y),
           '--duration', duration, '--steps', '90', '--post-delay', '.9')


ui.axe('tap', '--id', 'session-input', '--tap-style', 'physical', '--post-delay', '.8')
ui.axe('type', ' '.join(f'word{index}' for index in range(60)))
ui.wait(lambda items: visible('session-grabber', items), 'The open sheet has no grabber')
assert not visible('session-expand'), 'The expand button must be gone'
inline = frame('session-input')
inline_top = frame('session-grabber')['y']
assert inline['height'] <= 142, f'Inline input exceeded its cap: {inline}'
assert not visible('composer-format-bold'), 'Format bar is visible before expanding'
ui.capture('overflow')

drag_grabber(120)
# The sheet's chrome (attachments, grabber, format bar, toolbar) can absorb most of a short host's height, so growth is measured at the sheet's top edge.
ui.wait(lambda items: frame('session-grabber', items)['y'] < inline_top - 30 and visible('composer-format-bold', items),
        'Dragging the grabber up did not open full screen with the format bar')
full = frame('session-input')
assert full['height'] >= inline['height'] - 1, f'Full-screen input shrank: {full}'
format_items = ui.state()
for name in ['heading', 'bold', 'italic', 'strikethrough', 'code', 'bulletList', 'quote']:
    assert visible(f'composer-format-{name}', format_items), f'Format bar lacks {name}'
ui.capture('fullscreen')

ui.axe('tap', '--id', 'composer-format-bold', '--post-delay', '.3')
ui.axe('type', 'bold')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'session-input' and 'bold' in (item.get('AXValue') or '') for item in items),
        'Typing after Bold did not reach the input')
ui.capture('formatted')

grip = frame('session-grabber')
drag_grabber(grip['y'] + 260)
ui.wait(lambda items: frame('session-input', items)['height'] <= 142 and not visible('composer-format-bold', items),
        'Dragging the grabber down did not return to the default sheet')
assert visible('session-send'), 'Dragging down from full screen must keep the sheet open'
ui.capture('collapsed')

ui.axe('tap', '--id', 'session-grabber', '--post-delay', '.9')
ui.wait(lambda items: frame('session-grabber', items)['y'] < inline_top - 30 and visible('composer-format-bold', items), 'Tapping the grabber did not open full screen')
ui.axe('tap', '--id', 'session-grabber', '--post-delay', '.9')
ui.wait(lambda items: not visible('composer-format-bold', items), 'Tapping the grabber did not return to the sheet')

def keyboard_top(items=None):
    keyboard = ui.visible_keyboard(ui.state() if items is None else items)
    return keyboard['y'] if keyboard else None


resting_items = ui.state()
resting_keyboard = keyboard_top(resting_items)
assert resting_keyboard, 'The software keyboard must be up before collapsing the sheet'
sheet = frame('session-input', resting_items)
title = frame('chat-navigation-title', resting_items)
grip = frame('session-grabber', resting_items)
drag_grabber(grip['y'] + 30, duration='1.2')
ui.wait(lambda items: abs(frame('session-input', items)['height'] - sheet['height']) <= 1 and (keyboard_top(items) or 0) == resting_keyboard,
        'A short slow collapse drag must spring back to the sheet with the keyboard up')
ui.capture('collapse-cancelled')

grip = frame('session-grabber')
x = grip['x'] + grip['width'] / 2
y = grip['y'] + grip['height'] / 2
finger_end = y + 160
assert finger_end < resting_keyboard, 'The collapse drag must stay above the resting keyboard to prove it follows from the start'
drag = threading.Thread(target=ui.axe, args=('drag', '--start-x', str(x), '--start-y', str(y), '--end-x', str(x), '--end-y', str(finger_end),
                                             '--duration', '8', '--steps', '240'))
resting_bottom = sheet['y'] + sheet['height']
drag_started = time.monotonic()
drag.start()
time.sleep(4)
# AX collection can take several seconds; capture the framebuffer first, while held.
ui.screenshot('collapse-midway')
sample_started = time.monotonic()
mid_items = ui.state()
sample_finished = time.monotonic()
mid_input = next(item['frame'] for item in mid_items if item.get('AXUniqueId') == 'session-input')
mid_title = next(item['frame'] for item in mid_items if item.get('AXUniqueId') == 'chat-navigation-title')
mid_grip = next(item['frame'] for item in mid_items if item.get('AXUniqueId') == 'session-grabber')
(ui.output / 'collapse-midway.json').write_text(json.dumps(mid_items, indent=2))
(ui.output / 'drag-geometry.json').write_text(json.dumps({
    'duration': 8, 'fingerDistance': 160, 'sampleSeconds': [sample_started - drag_started, sample_finished - drag_started],
    'startGrabber': grip, 'midGrabber': mid_grip, 'startInput': sheet, 'midInput': mid_input,
}, indent=2))
drag.join()
# The keyboard renders out of process and its accessibility frame lags an interactive drag; the composer is pinned to its top edge.
mid_bottom = mid_input['y'] + mid_input['height']
assert mid_bottom > resting_bottom + 30, \
    f'The keyboard must follow the grabber before the finger reaches it; composer bottom resting {resting_bottom}, midway {mid_bottom}'
assert abs(mid_title['y'] - title['y']) <= 1, f'A collapse drag must not drag the hosting sheet; title {title}, midway {mid_title}'
assert 48 < mid_input['height'] < sheet['height'] - 10, f'The input must shrink with the drag; sheet {sheet}, midway {mid_input}'
ui.wait(lambda items: abs(frame('session-input', items)['height'] - 48) <= 1 and not ui.visible_keyboard(items),
        'Releasing a collapse drag must land on the capsule with the keyboard down')
ui.capture('closed')
print('PASS: grabber drag to full screen with format bar, drag back, tap toggle, cancelled collapse, and keyboard-following collapse')
