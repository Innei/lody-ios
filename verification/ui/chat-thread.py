"""A multi-file change block starts folded to one summary row and expands in place above the meta row; a later turn sits below a divider."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
files = ['src/App.tsx', 'docs/notes.md', 'packages/cloud-runtime/src/replica.ts']


def summary(items):
    return next((i for i in items if i.get('AXUniqueId') == 'preview-answer:changes'), None)


def probe(items):
    match = next((i for i in items if i.get('AXUniqueId') == 'session-preview-probe'), None)
    return ((match or {}).get('AXValue') or '').split(',')


ui.wait(lambda items: 'settled' in probe(items), 'The streamed reply did not settle')
first = ui.wait(summary, 'The file summary did not appear')
assert 41.5 <= first['frame']['height'] <= 42.5, first['frame']['height']
assert first.get('AXValue') == catalog.text('native.chat.changes.collapsed'), first.get('AXValue')
assert first['AXLabel'] == catalog.text(
    'native.chat.file.diffStats', text=catalog.plural('native.chat.transcript.fileCount', 3), add=33, **{'del': 7}
), first['AXLabel']
items = ui.state()
assert not any(i.get('AXUniqueId') == 'preview-answer:changes:' + path for path in files for i in items), 'Files show while folded'
ui.capture('folded')

ui.axe('tap', '--id', 'preview-answer:changes', '--post-delay', '.6')
ui.wait(lambda items: (summary(items) or {}).get('AXValue') == catalog.text('native.chat.changes.expanded'), 'The summary did not expand')
rows = [ui.element('preview-answer:changes:' + path) for path in files]
for path, row in zip(files, rows):
    assert 39.5 <= row['frame']['height'] <= 40.5, (path, row['frame']['height'])
assert not any(i.get('AXUniqueId') == 'preview-answer:changesReview' for i in ui.state()), 'An unreviewable session offers no Review all changes'
model = ui.element('preview-answer:meta:details')
last = rows[-1]['frame']
assert last['y'] + last['height'] <= model['frame']['y'] + 1, 'The meta row follows the file block'
ui.capture('expanded')

follow = ui.element('preview-follow-up:user')
meta_bottom = model['frame']['y'] + model['frame']['height']
assert follow['frame']['y'] - meta_bottom >= 40, f"The next turn sits below a divider, gap {follow['frame']['y'] - meta_bottom}"

ui.axe('tap', '--id', 'preview-answer:changes', '--post-delay', '.6')
ui.wait(lambda items: (summary(items) or {}).get('AXValue') == catalog.text('native.chat.changes.collapsed'), 'The summary did not fold again')
assert not any(i.get('AXUniqueId') == 'preview-answer:changes:' + files[0] for i in ui.state()), 'Folding hides the files'
ui.capture('refolded')
print('Chat thread: file block folds and expands in place; turns are divided')
