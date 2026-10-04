"""Production Markdown supports code copy, selection, and full-bleed tables."""
import json
import subprocess
import sys
import time
from pathlib import Path
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def table_bleed_path():
    container = subprocess.check_output(
        ['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'],
        text=True,
        timeout=10,
    ).strip()
    return Path(container) / 'tmp' / 'lody-table-bleed.json'


def table_bleed_rows():
    path = table_bleed_path()
    ui.wait(lambda _: path.exists() and path.stat().st_size > 2, 'Table bleed probe did not write')
    return json.loads(path.read_text())


def widest_table(rows):
    wide = [row for row in rows if row['contentWidth'] > row['boundsWidth'] + 8]
    assert wide, ('No horizontally scrollable table', rows)
    return max(wide, key=lambda row: row['y'])


def save_probe(name):
    path = table_bleed_path()
    if path.exists():
        (ui.output / f'{name}.probe.json').write_text(path.read_text())


copy_label = catalog.system('copy')


def copy_frames():
    return {
        tuple(item['frame'][key] for key in ('x', 'y', 'width', 'height'))
        for item in ui.state() if (item.get('AXLabel') or '').casefold() == copy_label.casefold() and item.get('frame')
    }


def long_press_copy(x, y):
    old = copy_frames()
    subprocess.run(['xcrun', 'simctl', 'pbcopy', ui.udid], input='selection sentinel', text=True, check=True, timeout=10)
    ui.axe('touch', '-x', str(x), '-y', str(y), '--down', '--up', '--delay', '.7')
    action = ui.wait(
        lambda items: next((item for item in items
                            if (item.get('AXLabel') or '').casefold() == copy_label.casefold() and item.get('type') == 'GenericElement' and item.get('frame') and
                            tuple(item['frame'][key] for key in ('x', 'y', 'width', 'height')) not in old), None),
        'Long press did not open the selection menu')
    ui.capture('word-selection-before-copy')
    probe = table_bleed_path().with_name('lody-markdown-selection.json')
    (ui.output / 'word-selection-before-copy.probe.json').write_text(probe.read_text())
    action = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').casefold() == copy_label.casefold() and i.get('type') == 'GenericElement'), None), 'Copy menu disappeared')
    frame = action['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.3')
    def copied(_):
        value = subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True, timeout=10).strip()
        return value if value and value != 'selection sentinel' else None
    return ui.wait(copied, 'Selection did not reach the clipboard', timeout=5)


rest = widest_table(table_bleed_rows())
assert rest['x'] <= 1, rest
assert rest['x'] + rest['width'] >= rest['boundsWidth'] - 1, rest
assert rest['offsetX'] <= 1, rest
save_probe('table-bleed')
ui.capture('table-bleed')
assert '<ruby>日本語<rt>にほんご</rt></ruby>' in ui.element('preview:answer')['AXLabel']
ui.capture('ruby-annotations')
cell_word = long_press_copy(rest['x'] + rest['contentLeft'] + 24, rest['y'] + 16)
assert cell_word in 'table-bleed-start', repr(cell_word)
ui.capture('table-selection')
mid_y = rest['y'] + min(40, rest['height'] / 2)
for _ in range(3):
    if widest_table(table_bleed_rows())['offsetX'] > 20:
        break
    ui.axe(
        'swipe',
        '--start-x', str(rest['x'] + rest['width'] - 48),
        '--start-y', str(mid_y),
        '--end-x', str(rest['x'] + 48),
        '--end-y', str(mid_y),
        '--duration', '.35',
        '--post-delay', '.5',
    )
ui.wait(
    lambda _: widest_table(table_bleed_rows())['offsetX'] > 20,
    'Wide table did not scroll horizontally',
)
scrolled = widest_table(table_bleed_rows())
assert scrolled['x'] <= 1, scrolled
assert scrolled['x'] + scrolled['width'] >= scrolled['boundsWidth'] - 1, scrolled
save_probe('table-bleed-scrolled')
ui.capture('table-bleed-scrolled')

for _ in range(16):
    # AX exposes code actions beneath the transparent navigation bar; scroll them clear before tapping.
    copies = [i['frame'] for i in ui.state()
              if (i.get('AXLabel') or '').casefold() == copy_label.casefold() and i.get('type') == 'Button'
              and i.get('frame', {}).get('height', 0) >= 40
              and 140 <= i.get('frame', {}).get('y', 0) <= 650]
    if copies:
        copy = max(copies, key=lambda frame: frame['y'])
        break
    ui.axe('swipe', '--start-x', '200', '--start-y', '400', '--end-x', '200', '--end-y', '500', '--duration', '.8', '--post-delay', '1')
else:
    raise AssertionError('Markdown code copy action not visible')
subprocess.run(['xcrun', 'simctl', 'pbcopy', ui.udid], input='clipboard sentinel', text=True, check=True, timeout=10)
ui.axe('tap', '-x', str(copy['x'] + copy['width'] / 2), '-y', str(copy['y'] + copy['height'] / 2), '--post-delay', '.3')
text = subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True, timeout=10)
assert text.strip() == 'let layout = UICollectionViewFlowLayout()\nlet list = UICollectionView(\n  frame: .zero,\n  collectionViewLayout: layout\n)', repr(text)

for _ in range(8):
    answer = ui.element('preview:answer')
    frame = answer['frame']
    if frame['y'] + frame['height'] <= 750:
        break
    ui.axe('swipe', '--start-x', '200', '--start-y', '650', '--end-x', '200', '--end-y', '350', '--duration', '.5', '--post-delay', '.3')
selected = long_press_copy(frame['x'] + 70, frame['y'] + frame['height'] - 25)
assert selected in answer['AXLabel'], repr(selected)
ui.capture('markdown-code')

grown = table_bleed_path().with_name('lody-context-view-grown.json')
grown.unlink(missing_ok=True)
hit_testing = grown.with_name('lody-markdown-hit-testing.json')
hit_testing.unlink(missing_ok=True)
ui.axe('tap', '--label', 'Fast Replay', '--post-delay', '.5')
ui.wait(
    lambda items: any(i.get('AXUniqueId') == 'preview:answer' and (i.get('AXLabel') or '').endswith('收尾段落。') for i in items),
    'Fast replay did not complete',
)
time.sleep(1)
assert not grown.exists(), ('Code or table view animated its frame after completion', grown.read_text())
ui.wait(lambda _: hit_testing.exists(), 'Fold hit-testing checks did not run')
checks = json.loads(hit_testing.read_text())
assert checks and all(checks.values()), checks
(ui.output / 'markdown-hit-testing.json').write_text(hit_testing.read_text())
ui.capture('markdown-folded')
print('PASS: production Markdown code copy, long-press selection in body and table, gutter bleed, and fold without regrowth')

# Small production rows make both boundaries reachable without scrolling.
ui.axe('tap', '--label', 'Fixtures', '--post-delay', '.3')
ui.axe('tap', '--label', 'Selection Fixture', '--post-delay', '.5')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'selection:first' for i in items), 'Selection fixture did not load')
selection_path = table_bleed_path().with_name('lody-markdown-selection.json')


def labels():
    return json.loads(selection_path.read_text())


def label(text):
    return next((item for item in labels() if item['text'].strip() == text), None)


def press(text):
    item = ui.wait(lambda _: label(text), f'Missing rendered label: {text}')
    ui.axe('touch', '-x', str(item['x'] + 15), '-y', str(item['y'] + item['height'] / 2), '--down', '--up', '--delay', '.7')
    return ui.wait(lambda _: next((i for i in labels() if i['text'].strip() == text and i.get('rects')), None), 'Word selection did not appear')


def extend(selected, target):
    rect = selected['rects'][-1]
    ui.axe('drag', '--start-x', str(rect['x'] + rect['width']), '--start-y', str(rect['y'] + rect['height'] + 4),
           '--end-x', str(target['x'] + target['width'] - 3), '--end-y', str(target['y'] + target['height'] / 2 + 8),
           '--duration', '1', '--steps', '60', '--post-delay', '.5')


def copy_selection():
    action = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').casefold() == 'copy' and i.get('type') == 'GenericElement' and i.get('frame')), None), 'Selection Copy menu missing')
    frame = action['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.3')
    return subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True, timeout=10)


selected = press('Alpha begins here.')
extend(selected, label('Bravo finishes here.'))
ui.wait(lambda _: sum(bool(i.get('selected')) for i in labels()) >= 2, 'Handle did not cross Markdown rows')
ui.capture('cross-row-selection')
copied = copy_selection()
assert 'Alpha begins here.' in copied and 'Bravo finishes here' in copied, repr(copied)
(ui.output / 'cross-row-copy.txt').write_text(copied)

selected = press('Fruit')
extend(selected, label('Red'))
ui.wait(lambda _: sum(bool(i.get('selected')) for i in labels()) >= 4, 'Handle did not cross table cells')
ui.capture('cross-table-selection')
copied = copy_selection()
assert 'Fruit\tColor\nApple\tRed' in copied, repr(copied)
(ui.output / 'cross-table-copy.txt').write_text(copied)
ui.axe('tap', '--label', 'Fast Replay', '--post-delay', '.5')
# Selection pauses bottom-following; replacement history need not scroll to its last row.
ui.wait(lambda items: any((i.get('AXUniqueId') or '').startswith('history-') for i in items), 'Replacement transcript did not display history')
ui.wait(lambda _: not any(i.get('selected') for i in labels()), 'Replaced rows retained stale selection')
ui.capture('selection-reset')
print('PASS: drag handles cross Markdown rows and table cells; copy preserves order and tab/newline separators; replaced rows clear selection')
