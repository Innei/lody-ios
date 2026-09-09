"""Tool-detail inline diffs are native, full-height, and scroll with the sheet."""
import sys
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])
ui.axe('tap', '--label', 'Inline Diff Fixture')
ui.wait(
    lambda items: any(
        (i.get('AXUniqueId') or '') == 'inline-diff'
        or 'src/inline.ts' in (i.get('AXLabel') or '')
        for i in items
    ),
    'Inline diff sheet did not open',
)
lines = [
    item
    for item in ui.state()
    if item.get('AXUniqueId') == 'inline-diff-line'
]
assert lines, 'Native inline diff lines were missing from AX'
labels = ' '.join(item.get('AXLabel') or '' for item in lines)
assert 'greeting' in labels, labels
assert any('removed' in (item.get('AXLabel') or '') for item in lines)
assert any('added' in (item.get('AXLabel') or '') for item in lines)
ui.capture('inline')
height = sum(item['frame']['height'] for item in lines)
assert height >= 36, height
xs = {round(item['frame']['x']) for item in lines}
assert len(xs) == 1, xs
sheet = next(
    (item for item in ui.state() if item.get('type') == 'ScrollView'),
    None,
)
if sheet:
    ui.axe(
        'swipe',
        '--start-x',
        str(int(sheet['frame']['x'] + sheet['frame']['width'] / 2)),
        '--start-y',
        str(int(sheet['frame']['y'] + sheet['frame']['height'] - 40)),
        '--end-x',
        str(int(sheet['frame']['x'] + sheet['frame']['width'] / 2)),
        '--end-y',
        str(int(sheet['frame']['y'] + 80)),
        '--duration',
        '0.4',
        '--post-delay',
        '0.4',
    )
    ui.capture('inline-scrolled')
print('Inline native diff lines, height and outer scroll passed')
