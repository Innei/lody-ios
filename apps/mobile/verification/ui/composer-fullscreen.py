"""Overflowing chat input expands in place to full screen with a format bar, and collapses on demand and on send."""
import sys
from driver import UI

ui = UI(*sys.argv[1:])


def frame(identifier):
    return ui.element(identifier)['frame']


# AXe also lists hidden UIKit views, so a clipped control counts only when it has height.
def visible(identifier):
    return any(item.get('AXUniqueId') == identifier and item.get('frame', {}).get('height', 0) > 0 for item in ui.state())


ui.axe('tap', '--id', 'session-input', '--tap-style', 'physical', '--post-delay', '.8')
ui.axe('type', ' '.join(f'word{index}' for index in range(60)))
ui.wait(lambda items: visible('session-expand'), 'Expand button did not appear for overflowing text')
inline = frame('session-input')
assert inline['height'] <= 142, f'Inline input exceeded its cap: {inline}'
assert not visible('composer-format-bold'), 'Format bar is visible before expanding'
ui.capture('overflow')

ui.axe('tap', '--id', 'session-expand', '--post-delay', '.8')
ui.wait(lambda items: frame('session-input')['height'] > inline['height'] + 30, 'Input did not grow to full screen')
full = frame('session-input')
assert full['y'] < inline['y'] - 30, f'Full-screen input did not grow upward: {full}'
for name in ['heading', 'bold', 'italic', 'strikethrough', 'code', 'bulletList', 'quote']:
    assert visible(f'composer-format-{name}'), f'Format bar lacks {name}'
ui.capture('fullscreen')

ui.axe('tap', '--id', 'composer-format-bold', '--post-delay', '.3')
ui.axe('type', 'bold')
ui.wait(lambda items: 'bold' in (ui.element('session-input').get('AXValue') or ''), 'Typing after Bold did not reach the input')
ui.capture('formatted')

ui.axe('tap', '--id', 'session-expand', '--post-delay', '.8')
ui.wait(lambda items: frame('session-input')['height'] <= 142, 'Collapse did not restore the inline height')
assert not visible('composer-format-bold'), 'Format bar stayed after collapsing'
ui.capture('collapsed')

ui.axe('tap', '--id', 'session-expand', '--post-delay', '.8')
ui.wait(lambda items: frame('session-input')['height'] > inline['height'] + 30, 'Input did not expand a second time')
ui.axe('tap', '--id', 'session-send', '--post-delay', '1.2')
ui.wait(lambda items: not visible('composer-format-bold') and not (ui.element('session-input').get('AXValue') or ''), 'Send did not collapse and clear the full-screen input')
ui.capture('sent')
print('PASS: overflow expand button, upward full-screen morph with format bar, collapse, and send from full screen')
