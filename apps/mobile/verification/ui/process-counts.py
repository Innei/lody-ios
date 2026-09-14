"""Process-row counts roll with numericText and keep the 44 pt floor."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])

ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Process Counts Fixture', '--post-delay', '.6')


def process_row(items):
    return next(
        (
            item for item in items
            if item.get('AXUniqueId') == 'counts-preview:process'
        ),
        None,
    )


first = ui.wait(
    lambda items: process_row(items),
    'The process counts fixture did not show a process row',
)
first_label = first.get('AXLabel') or ''
assert catalog.plural('native.chat.transcript.activity.tools', 1) in first_label, first_label
assert catalog.plural('native.chat.transcript.activity.editedFiles', 1) in first_label, first_label
height = first['frame']['height']
assert abs(height - 44) <= 1, 'Process row started off the 44-point floor: ' + str(height)
ui.capture('counts-one')

changed = ui.wait(
    lambda items: next(
        (
            item for item in [process_row(items)]
            if item is not None and (item.get('AXLabel') or '') != first_label
        ),
        None,
    ),
    'Process counts did not increment',
)
changed_label = changed.get('AXLabel') or ''
assert catalog.plural('native.chat.transcript.activity.tools', 2) in changed_label, changed_label
assert abs(changed['frame']['height'] - height) <= 0.5, (
    'Incrementing process counts changed the row height: '
    + str((height, changed['frame']['height']))
)
ui.capture('counts-two')
print('PASS: process counts increment without raising the row')
