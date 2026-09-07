"""Production Markdown supports code copy and long-press text selection."""
import subprocess
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
# The rich answer is longer than one screen. Find its actual code button by scrolling.
for _ in range(8):
    if any(i.get('AXLabel') == catalog.system('copy') and i.get('type') == 'Button' for i in ui.state()):
        break
    ui.axe('swipe', '--start-x', '200', '--start-y', '300', '--end-x', '200', '--end-y', '650', '--duration', '.5', '--post-delay', '.3')
else:
    raise AssertionError('Markdown code copy action not visible')
subprocess.run(['xcrun', 'simctl', 'pbcopy', ui.udid], input='clipboard sentinel', text=True, check=True, timeout=10)
ui.axe('tap', '--label', catalog.system('copy'), '--element-type', 'Button', '--post-delay', '.3')
text = subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True, timeout=10)
assert text.strip() == 'let layout = UICollectionViewFlowLayout()\nlet list = UICollectionView(\n  frame: .zero,\n  collectionViewLayout: layout\n)', repr(text)

answer = ui.element('preview:answer')
copy_label = catalog.system('copy')
old_copy_frames = {
    tuple(item['frame'][key] for key in ('x', 'y', 'width', 'height'))
    for item in ui.state() if item.get('AXLabel') == copy_label and item.get('frame')
}
frame = answer['frame']
subprocess.run(['xcrun', 'simctl', 'pbcopy', ui.udid], input='selection sentinel', text=True, check=True, timeout=10)
ui.axe('touch', '--x', str(frame['x'] + 70), '--y', str(frame['y'] + frame['height'] - 25),
       '--down', '--up', '--delay', '.7')
copy_action = ui.wait(
    lambda items: next((item for item in items
                        if item.get('AXLabel') == copy_label and item.get('frame') and
                        tuple(item['frame'][key] for key in ('x', 'y', 'width', 'height')) not in old_copy_frames), None),
    'Long press did not open the selection menu')
action_frame = copy_action['frame']
ui.axe('tap', '--x', str(action_frame['x'] + action_frame['width'] / 2),
       '--y', str(action_frame['y'] + action_frame['height'] / 2), '--post-delay', '.3')
selected = subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True, timeout=10).strip()
assert selected and selected != 'selection sentinel' and selected in answer['AXLabel'], repr(selected)
ui.capture('markdown-code')
print('PASS: production Markdown code copy and long-press selection')
