"""Mock tool activity stays compact across history, running, failure and completion."""
import sys
import time
from driver import UI
import catalog

ui = UI(*sys.argv[1:])

ui.axe('tap', '--label', 'Fixtures', '--post-delay', '.5')
labels = [item.get('AXLabel') or '' for item in ui.state()]
if 'Failed Tool Fixture' not in labels:
    raise AssertionError('Fixtures menu did not include Failed Tool Fixture: ' + repr([label for label in labels if label]))
ui.axe('tap', '--label', 'Failed Tool Fixture', '--post-delay', '.6')

thinking = catalog.text('native.chat.transcript.activity.thinking')
read = catalog.plural('native.chat.transcript.activity.readFiles', 1)
tools = catalog.plural('native.chat.transcript.activity.tools', 1)


def process_row(items):
    return next(
        (
            item for item in items
            if item.get('AXUniqueId') == 'failed-preview:process:thought'
        ),
        None,
    )


row = ui.wait(
    lambda items: process_row(items),
    'The failed-tool fixture did not show its current process row',
)
label = row.get('AXLabel') or ''
assert thinking not in label, label
assert read in label, label
assert tools in label, label
assert abs(row['frame']['height'] - 44) <= 1, (
    'The failed-tool process row must stay on the 44-point floor: ' + str(row['frame'])
)
ui.capture('failed-live')
historical = ui.element('failed-preview:process')
assert thinking not in historical['AXLabel'], historical['AXLabel']
assert catalog.plural('native.chat.transcript.activity.readFiles', 3) in historical['AXLabel']
assert abs(historical['frame']['height'] - 44) <= 1, historical['frame']
time.sleep(2.2)
still = ui.element('failed-preview:process:thought')
assert thinking not in (still.get('AXLabel') or ''), still.get('AXLabel')
assert abs(still['frame']['height'] - 44) <= 1, still['frame']
ui.capture('failed-shine')

ui.axe('tap', '--id', 'failed-preview:process:thought', '--post-delay', '.7')
running = ui.element('failed-preview:read')
assert 'Read ChatCell.swift' in (running.get('AXLabel') or ''), running.get('AXLabel')
assert 'request failed' in ui.element('failed-preview:tool')['AXLabel']
assert not any(item.get('AXUniqueId') == 'failed-preview:earlier-read-0' for item in ui.state())
ui.capture('process-detail-shine-start')
time.sleep(.35)
still_running = ui.element('failed-preview:read')
assert 'Read ChatCell.swift' in (still_running.get('AXLabel') or ''), still_running.get('AXLabel')
ui.capture('process-detail-shine-end')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('process.title')), '--post-delay', '.5')
ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Finish Tool Fixture', '--post-delay', '.6')
completed = ui.element('failed-preview:duration')
assert thinking not in completed['AXLabel'], completed['AXLabel']
assert read not in completed['AXLabel'], completed['AXLabel']
assert completed['frame']['height'] >= 44, completed['frame']
assert 'one quiet line' in ui.element('failed-preview:answer')['AXLabel']
ui.capture('completed')
ui.axe('tap', '--id', 'failed-preview:duration', '--post-delay', '.7')
ui.element('failed-preview:earlier-read-0')
ui.capture('completed-process')
print('PASS: historical status, single-line summaries, scoped details and completed process disclosure')
