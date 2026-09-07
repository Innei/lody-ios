"""The production Markdown renderer must preserve code when copied to the clipboard."""
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
ui.capture('markdown-code')
print('PASS: production Markdown code copy preserves complete text and indentation')
