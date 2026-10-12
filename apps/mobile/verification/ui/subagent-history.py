"""Read retained subtask runs through the production native transcript without writes."""
import sys
import time
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
CARD = 'offline-parent-reply:task-one'
record_open = False
started = time.monotonic()


def phase(name):
    print(f'PHASE {name}: {time.monotonic() - started:.2f}s', flush=True)


def unique(items, key, value):
    matches = [item for item in items if item.get(key) == value]
    assert len(matches) <= 1, f'Duplicate {value} surfaces: {len(matches)}'
    return matches[0] if matches else None


def tap_id(identifier):
    ui.wait(lambda items: unique(items, 'AXUniqueId', identifier), f'Missing {identifier}')
    ui.axe('tap', '--id', identifier, '--post-delay', '.3')


def tap_label(label):
    ui.wait(lambda items: unique(items, 'AXLabel', label), f'Missing {label}')
    ui.axe('tap', '--label', label, '--post-delay', '.3')


def has_id(identifier):
    return any(i.get('AXUniqueId') == identifier for i in ui.state())


def close_sheet(title):
    global record_open
    tap_label(catalog.text('accessibility.closeSheet', title=title))
    ui.wait(lambda items: not any(i.get('AXUniqueId') in ['subagent-history-description', 'subagent-history-state'] for i in items), 'The record sheet did not dismiss')
    record_open = False
    ui.wait(lambda items: (unique(items, 'AXUniqueId', 'subagent-history-subscriptions') or {}).get('AXLabel') == 'Subtask subscriptions: 0', 'Leaving the active record retained its subscription')
    phase('subscription-released')


def open_record(mode):
    global record_open
    phase(f'open-{mode}')
    if record_open:
        close_sheet(catalog.text('native.chat.transcript.subtask'))
    # The runner entered the preview once. Reset its service through the real
    # fixture menu instead of presenting another copy behind the active sheet.
    fixture = ui.wait(lambda items: unique(items, 'AXUniqueId', 'subagent-history-preview-ready'), 'Missing the active fixture')
    menu = ui.wait(lambda items: unique(items, 'AXLabel', 'Subtask fixtures'), 'Missing the fixture menu')
    assert fixture['frame']['y'] >= menu['frame']['y'] + menu['frame']['height'], 'The fixture content overlaps its native navigation bar'
    tap_label('Subtask fixtures')
    tap_label(mode)
    ui.wait(lambda items: (unique(items, 'AXUniqueId', 'subagent-history-preview-ready') or {}).get('AXLabel') == f'Subtask history fixture · {mode}', f'The {mode} fixture did not reset')
    ui.wait(lambda items: (unique(items, 'AXUniqueId', 'subagent-history-subscriptions') or {}).get('AXLabel') == 'Subtask subscriptions: 0', 'The reset fixture still owns a record subscription')
    tap_id(CARD)
    ui.element('subagent-history-description') if mode != 'unsupported' else ui.element('subagent-history-state')
    record_open = True
    phase(f'opened-{mode}')


def assert_read_only():
    forbidden = ['session-input', 'session-send', 'session-stop', 'session-steer']
    assert not any(i.get('AXUniqueId') in forbidden for i in ui.state()), 'Run record exposed composer or execution controls'


open_record('loading')
assert ui.element('subagent-history-state')['AXLabel'] == catalog.text('subagent.history.loading')
phase('loading-observed')
ui.capture('loading')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'subagent-history-state' and i.get('AXLabel') == catalog.text('subagent.history.loading') for i in items), 'Loading did not settle')
open_record('running')
assert_read_only()
assert ui.element('subagent-history-status')['AXLabel'] == catalog.text('native.chat.subagent.running')
phase('running-observed')
ui.capture('running')

# The real tool result request advances the fixture service and emits the usual
# changed signal; the production controller must re-read and render completion.
for _ in range(3):
    if has_id('subagent:run-one:retained:tool'):
        break
    ui.axe('swipe', '--start-x', '200', '--start-y', '270', '--end-x', '200', '--end-y', '560', '--duration', '.4', '--post-delay', '.3')
tap_id('subagent:run-one:retained:tool')
ui.element('subagent-history-tool')
ui.wait(lambda items: any('History protocol: PASS' in (i.get('AXLabel') or '') for i in items), 'The retained tool result is missing')
phase('tool-result-observed')
ui.capture('tool-result')
# Tool detail is pushed inside the record sheet; the native back button returns to the record.
tap_id('BackButton')
ui.element('subagent-history-description')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'subagent-history-status' and i.get('AXLabel') == catalog.text('native.chat.subagent.completed') for i in items), 'Live execution records did not complete')
assert ui.element('subagent:run-one:retained:result')['AXLabel'] == 'Live record completed without restarting the task.'
assert_read_only()
phase('completion-observed')
ui.capture('live-completed')
close_sheet(catalog.text('native.chat.transcript.subtask'))
ui.capture('released')

open_record('multiple')
ui.element('subagent:run-one:retained:run-prose')
assert_read_only()
tap_label(catalog.text('subagent.history.runs'))
tap_label(catalog.text('subagent.history.run', number=2, state=catalog.text('native.chat.subagent.failed')))
ui.element('subagent:run-two:retained:run-prose')
assert not has_id('subagent:run-one:retained:run-prose'), 'Different runs mixed their messages'
assert ui.element('subagent-history-status')['AXLabel'] == catalog.text('native.chat.subagent.failed')
ui.capture('second-run')
close_sheet(catalog.text('native.chat.transcript.subtask'))

open_record('pagination')
ui.capture('latest-page')
for _ in range(5):
    if not has_id('subagent-history-more'):
        break
    tap_id('subagent-history-more')
assert not has_id('subagent-history-more'), 'Earlier record pagination did not reach its end'
for _ in range(12):
    if has_id('subagent:run-one:retained:older-0'):
        break
    ui.axe('swipe', '--start-x', '200', '--start-y', '270', '--end-x', '200', '--end-y', '650', '--duration', '.4', '--post-delay', '.25')
ui.element('subagent:run-one:retained:older-0')
ui.capture('earliest-page')

for mode, key in [('empty', 'subagent.history.empty'), ('unsupported', 'subagent.history.unsupported'), ('load-failed', 'subagent.history.failed')]:
    open_record(mode)
    assert ui.element('subagent-history-state')['AXLabel'] == catalog.text(key)
    assert_read_only()
    ui.capture(mode)
    if mode == 'unsupported':
        ui.element('subagent-detail-result')
    if mode == 'load-failed':
        tap_id('subagent-history-retry')
        ui.wait(lambda items: not any(i.get('AXUniqueId') == 'subagent-history-retry' for i in items), 'Explicit read retry did not recover')
        ui.capture('read-recovered')

open_record('truncated')
assert ui.element('subagent-history-incomplete')['AXLabel'] == catalog.text('subagent.history.incomplete')
assert_read_only()
ui.capture('incomplete')
close_sheet(catalog.text('native.chat.transcript.subtask'))
print('PASS: retained live history, native tool detail, separate runs, complete paging, unsupported/empty/failure states and released subscriptions')
