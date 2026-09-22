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
                            if (item.get('AXLabel') or '').casefold() == copy_label.casefold() and item.get('frame') and
                            tuple(item['frame'][key] for key in ('x', 'y', 'width', 'height')) not in old), None),
        'Long press did not open the selection menu')
    frame = action['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.3')
    selected = subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True, timeout=10).strip()
    assert selected and selected != 'selection sentinel', repr(selected)
    return selected


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
              if i.get('AXLabel') == copy_label and i.get('type') == 'Button'
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
