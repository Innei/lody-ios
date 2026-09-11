"""Assistant work duration advances while live and freezes when finished."""
import sys
import time
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
copy = {
    'en': {'working': 'Working for ', 'worked': 'Worked for ', 'finished': 'Worked for 1m 05s'},
    'zh-Hans': {'working': '正在工作 ', 'worked': '工作了 ', 'finished': '工作了 1分 05秒'},
}[catalog.LANGUAGE]

ui.axe('tap', '--label', 'Fixtures')
ui.axe('tap', '--label', 'Duration Fixture', '--post-delay', '.5')


def duration_row(items, prefix):
    return next(
        (
            item for item in items
            if item.get('AXUniqueId') == 'duration-preview:duration'
            and (item.get('AXLabel') or '').startswith(prefix)
        ),
        None,
    )


live = ui.wait(
    lambda items: duration_row(items, copy['working']),
    'The live assistant row did not show its work duration',
)
first_label = live['AXLabel']
advanced = ui.wait(
    lambda items: next(
        (
            item for item in [duration_row(items, copy['working'])]
            if item is not None and item.get('AXLabel') != first_label
        ),
        None,
    ),
    'The live assistant work duration did not advance',
)
assert advanced['AXLabel'].startswith(copy['working'])
assert not any(
    child.get('AXValue') == '1' for child in advanced.get('children', [])
), 'The duration row still exposes a loading indicator'
process = ui.element('duration-preview:process')
assert process['frame']['y'] >= advanced['frame']['y'] + advanced['frame']['height'] - 1
assert copy['working'] not in process['AXLabel'], process['AXLabel']
ui.capture('working')
assert not any((item.get('AXUniqueId') or '').startswith('duration-preview:meta') for item in ui.state()), 'Live replies must not show metadata actions'

ui.axe('tap', '--label', 'Finish Duration Fixture', '--post-delay', '.5')
finished = ui.wait(
    lambda items: duration_row(items, copy['worked']),
    'The completed assistant row did not show its frozen work duration',
)
assert copy['finished'] in finished['AXLabel'], finished['AXLabel']
finished_label = finished['AXLabel']
time.sleep(1.2)
assert ui.element('duration-preview:duration')['AXLabel'] == finished_label

answer = ui.element('duration-preview:answer')
finished_process = ui.element('duration-preview:process')
assert finished_process['frame']['y'] >= finished['frame']['y'] + finished['frame']['height'] - 1
assert answer['frame']['y'] >= finished_process['frame']['y'] + finished_process['frame']['height'] - 1
model = ui.element('duration-preview:meta:model')
assert model['AXLabel'].startswith('GPT-5.6 Sol · High · '), model['AXLabel']
assert ':' in model['AXLabel'].rsplit(' · ', 1)[1], 'A same-day reply ends with a clock time'
assert model['frame']['y'] >= answer['frame']['y'] + answer['frame']['height'] - 1
assert abs(model['frame']['x'] - answer['frame']['x']) <= 1, (model['frame'], answer['frame'])
ui.capture('finished')
print('PASS: duration freezes and the metadata bar reads left-aligned under the answer')
