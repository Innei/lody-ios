"""Pele Mermaid diagrams render in Markdown documents, keep source, and fail into a readable block."""
import json
import subprocess
import sys
from pathlib import Path
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip()
probe = Path(container) / 'tmp/lody-mermaid.json'
flowchart = 'graph TD\n    A[Start] --> B{Ready?}\n    B -->|Yes| C[Done]\n    B -->|No| A'
pie = 'pie\n    "Swift" : 60\n    "TypeScript" : 40'
broken = 'graph TD\n    A[Start] --> B{Ready?\n    B -->|Yes| C[Done]'


def blocks():
    if not probe.exists():
        return []
    return json.loads(probe.read_text())


def settled(expected):
    def ready(_):
        items = [i for i in blocks() if i['owner'] == 'file-document-content']
        states = sorted((i['source'].strip(), i['state']) for i in items)
        return items if states == sorted(expected) else None
    return ui.wait(ready, f'Mermaid blocks did not settle as {expected}')


def open_document(row):
    probe.unlink(missing_ok=True)
    ui.axe('tap', '--id', row, '--post-delay', '.4')
    ui.element('file-document-content')


def close_document():
    ui.axe('tap', '--id', 'file-back', '--post-delay', '.5')
    ui.element('file:mermaid.md')


def copy(frame, expected):
    subprocess.run(['xcrun', 'simctl', 'pbcopy', ui.udid], input='Mermaid copy pending', text=True, check=True)
    ui.axe('touch', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + min(frame['height'] / 2, 40)),
           '--down', '--up', '--delay', '1')
    action = ui.wait(lambda items: next((i for i in items if i.get('AXLabel') == catalog.text('native.chat.copy')
                                         and i.get('frame', {}).get('height', 0) > 0), None), 'Mermaid block has no copy action')
    tap = action['frame']
    ui.axe('tap', '-x', str(tap['x'] + tap['width'] / 2), '-y', str(tap['y'] + tap['height'] / 2), '--post-delay', '.2')
    ui.wait(lambda _: subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True).strip() == expected,
            'Mermaid source did not reach the clipboard')


def previewing(items):
    return any(i.get('AXUniqueId') == 'chat-image-preview' for i in items)


def tap_center(frame):
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.6')


def preview(frame):
    tap_center(frame)
    ui.wait(lambda items: previewing(items) or None, 'Tapping a diagram did not open the image preview')
    ui.capture('preview')
    ui.axe('tap', '--label', catalog.text('native.chat.image.closePreview'), '--post-delay', '.6')
    ui.wait(lambda items: not previewing(items) or None, 'Diagram preview did not close')


open_document('file:mermaid.md')
items = settled([(flowchart, 'rendered'), (pie, 'rendered')])
for item in items:
    assert 0 < item['width'] <= 410 and item['height'] > 60, item
ui.capture('rendered')
first = next(i for i in items if i['source'].strip() == flowchart)
preview(first)
copy(first, flowchart)
ui.capture('copy-menu')

appearance = subprocess.check_output(['xcrun', 'simctl', 'ui', ui.udid, 'appearance'], text=True).strip()
other = 'dark' if appearance == 'light' else 'light'
before = {i['source']: i['image'] for i in blocks() if i['owner'] == 'file-document-content'}
subprocess.run(['xcrun', 'simctl', 'ui', ui.udid, 'appearance', other], check=True)
ui.wait(lambda _: (lambda now: len(now) == 2 and all(i['state'] == 'rendered' and i['image'] != before.get(i['source']) for i in now) or None)(
    [i for i in blocks() if i['owner'] == 'file-document-content']), 'Diagrams did not re-render for the new appearance')
ui.capture('rendered-' + other)
subprocess.run(['xcrun', 'simctl', 'ui', ui.udid, 'appearance', appearance], check=True)
close_document()

open_document('file:mermaid-invalid.md')
failed = settled([(broken, 'failed')])[0]
assert 80 < failed['height'] < 140, failed
label = failed['label']
assert catalog.text('native.chat.mermaid.failed') in label and 'Parse error on line 3' in label and 'A[Start]' in label, label
ui.capture('failed')
tap_center(failed)
assert not previewing(ui.state()), 'A failed diagram must not open the image preview'
copy(failed, broken)
close_document()
print('PASS: flowchart and pie render through Pele, open the image preview, re-render on appearance change, copy source, and a parse error keeps a readable failure block')
