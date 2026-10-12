"""Public client feedback: edit, review, native images, scrubbed diagnostics, offline copy/share and retained cancellation."""
import json
import statistics
import subprocess
import sys
from pathlib import Path

import catalog
from driver import UI
from project_geometry import viewport, visible_target, scroll_direction, scroll_points

ui = UI(*sys.argv[1:])
close_hits = []


def tap(identifier):
    ui.axe('tap', '--id', identifier, '--post-delay', '.4')


def reveal(identifier, down=True):
    toolbar_labels = {
        catalog.text('feedback.github'), catalog.text('common.save'), catalog.text('common.cancel'),
        catalog.text('accessibility.closeSheet', title=catalog.text('feedback.title')),
        catalog.text('accessibility.closeSheet', title=catalog.text('tabs.settings')),
    }
    for _ in range(16):
        items = ui.state()
        bounds = viewport(items, toolbar_labels)
        element = next((item for item in items if item.get('AXUniqueId') == identifier), None)
        frame = (element or {}).get('frame', {})
        if (visible_target(element, bounds) and frame.get('height', 0) >= 44
                and frame.get('width', 0) >= 44 and element.get('enabled', True)):
            record = {'action': 'target-ready', 'identifier': identifier, 'frame': frame,
                      'contentBounds': bounds, 'enabled': element.get('enabled', True)}
            with (ui.output / 'viewport-actions.jsonl').open('a') as log:
                log.write(json.dumps(record) + '\n')
            return element
        direction = scroll_direction(element, bounds, 'down' if down else 'up')
        start, end = scroll_points(direction, bounds)
        with (ui.output / 'viewport-actions.jsonl').open('a') as log:
            log.write(json.dumps({'action': 'scroll', 'identifier': identifier, 'observedFrame': frame,
                                  'contentBounds': bounds, 'direction': direction,
                                  'startY': start, 'endY': end}) + '\n')
        ui.axe('swipe', '--start-x', '200', '--start-y', str(start), '--end-x', '200', '--end-y', str(end),
               '--duration', '.35', '--post-delay', '.25')
    raise AssertionError(f'Missing fully visible, enabled 44 pt {identifier}')


def copied():
    return subprocess.check_output(['xcrun', 'simctl', 'pbpaste', ui.udid], text=True)


def edit(field, value, save=True):
    reveal('feedback-' + field, down=False)
    tap('feedback-' + field)
    ui.element('feedback-editor')
    ui.type_into('feedback-editor', value)
    ui.axe('tap', '--label', catalog.text('common.save') if save else catalog.text('common.cancel'), '--post-delay', '.5')


def close_feedback():
    ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('feedback.title')), '--post-delay', '.5')
    ui.element('feedback-open')


def close_screenshot_at_edge(host, identifier, dx, dy):
    close = ui.element('feedback-screenshot-close')
    frame = close['frame']
    assert close.get('enabled', True) and frame['width'] > 0 and frame['height'] > 0, close
    record = {
        'host': host, 'visibleAXFrame': frame, 'control': close['AXUniqueId'],
        'centerOffset': {'x': dx, 'y': dy},
        'physicalTap': {'x': frame['x'] + frame['width'] / 2 + dx, 'y': frame['y'] + frame['height'] / 2 + dy},
        'closedActualPreview': False,
    }
    close_hits.append(record)
    (ui.output / 'close-hit-area.json').write_text(json.dumps(close_hits, indent=2))
    point = record['physicalTap']
    ui.axe('tap', '-x', str(point['x']), '-y', str(point['y']), '--post-delay', '.5')
    ui.wait(lambda items: not any(item.get('AXUniqueId') == 'QLPreviewControllerView' for item in items),
            'The 44 pt Close target did not close the actual screenshot preview')
    record['closedActualPreview'] = True
    row = ui.wait(lambda items: next((item for item in items if item.get('AXUniqueId') == identifier and item.get('enabled', True)), None),
                  'Closing screenshot preview did not settle the host action')
    record['hostActionEnabledAfterClose'] = row.get('enabled', True)
    record['previewReopened'] = any(item.get('AXUniqueId') == 'QLPreviewControllerView' for item in ui.state())
    assert not record['previewReopened'], 'Closing a screenshot replayed the preview action'
    (ui.output / 'close-hit-area.json').write_text(json.dumps(close_hits, indent=2))
    print(json.dumps(record), flush=True)


def screenshot_row_unselected(name):
    reveal('feedback-add-image')
    ui.capture(name)
    items = ui.state()
    width = round(items[0]['frame']['width'])
    pixels = subprocess.check_output([
        'ffmpeg', '-v', 'error', '-i', str(ui.output / f'{name}.png'),
        '-vf', f'scale={width}:-1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-',
    ], timeout=20)

    def background(identifier):
        frame = ui.element(identifier)['frame']
        x, y = round(frame['x'] + 8), round(frame['y'] + frame['height'] / 2)
        height = len(pixels) // (width * 3)
        assert 2 <= y < height - 2, f'{identifier} is outside the captured viewport'
        return tuple(statistics.median(
            pixels[((y + dy) * width + x + dx) * 3 + channel]
            for dy in range(-2, 3) for dx in range(-2, 3)
        ) for channel in range(3))

    # Compare two blank leading insets in the same native grouped card. A
    # selected screenshot row remains visibly gray even though AX omits that
    # selected trait. This checks the rendered return state in either theme.
    image, add = background('feedback-image-0'), background('feedback-add-image')
    difference = max(abs(a - b) for a, b in zip(image, add))
    record = {'screenshotRowRGB': image, 'ordinaryActionRowRGB': add, 'difference': difference}
    (ui.output / f'{name}-selection.json').write_text(json.dumps(record, indent=2))
    print(name + ': ' + json.dumps(record), flush=True)
    assert difference <= 4, f'Screenshot row stayed selected after preview close: {record}'


ui.element('feedback-fixture-ready')
tap('feedback-reset')

# The product entry is in Settings/About and requires neither login nor Debug navigation.
tap('feedback-settings')
row = reveal('bug-feedback')
assert catalog.text('feedback.title') in row.get('AXLabel', ''), row
assert row['frame']['height'] >= 44, row
ui.capture('settings-entry')
tap('bug-feedback')
ui.element('feedback-description')
ui.capture('product-form')
# The Debug stack behind Settings and the sheet's pushed form both expose
# UIKit's BackButton identifier. Touch the foreground native control, then
# verify that the real push returned to Settings before closing its sheet.
back = [item for item in ui.state() if item.get('AXUniqueId') == 'BackButton'][-1]['frame']
assert back['width'] >= 44 and back['height'] >= 44, back
ui.axe('tap', '-x', str(back['x'] + back['width'] / 2), '-y', str(back['y'] + back['height'] / 2), '--post-delay', '.4')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'feedback-description' for item in items), 'Native back did not return from feedback to Settings')
ui.element('bug-feedback')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('tabs.settings')), '--post-delay', '.5')
ui.element('feedback-open')

tap('feedback-open')
ui.element('feedback-description')
edit('description', 'Composer keeps spinning')
edit('steps', 'This edit is cancelled', save=False)
assert catalog.text('feedback.empty') in ui.element('feedback-steps').get('AXLabel', '')
edit('steps', 'Open a session and send hello')
edit('expected', 'A reply appears')
edit('actual', 'The spinner does not stop')
ui.capture('entered-report')

reveal('feedback-add-image')
tap('feedback-add-image')
image = ui.element('feedback-image-0')
assert image['frame']['height'] >= 44, image
tap('feedback-image-0')
ui.element('QLPreviewControllerView')
ui.element('QLOverlayMarkupButtonAccessibilityIdentifier')
ui.capture('native-screenshot-preview')
# UIKit's system Close is visually 36 pt in AX, but its real target extends to
# 44 pt. Exercise that area with physical touches, not a frame-size snapshot.
for index, (dx, dy) in enumerate(((-21, 0), (21, 0), (0, -21), (0, 21))):
    if index:
        tap('feedback-image-0')
        ui.element('QLPreviewControllerView')
        ui.element('QLOverlayMarkupButtonAccessibilityIdentifier')
    close_screenshot_at_edge('form', 'feedback-image-0', dx, dy)
screenshot_row_unselected('native-screenshot-preview-closed')

reveal('feedback-diagnostics')
tap('feedback-diagnostics')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'feedback-diagnostics' and 'Runtime: failed' in item.get('AXLabel', '') for item in items), 'Optional diagnostics were not added')
ui.capture('optional-diagnostics')
reveal('feedback-preview')
tap('feedback-preview')
ui.element('feedback-public-warning')
assert 'Innei/lody-ios' in ui.element('feedback-public-warning').get('AXLabel', '')
tap('feedback-copy')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'feedback-status' and catalog.text('feedback.copied') in item.get('AXLabel', '') for item in items), 'Copy feedback missing')
report = copied()
for text in ('Composer keeps spinning', 'Open a session and send hello', 'A reply appears', 'The spinner does not stop',
             'App version: 0.2.0', 'Build: 48', 'iOS: 27.0', 'Device: iPhone18,1', 'Runtime: failed', '1 screenshot(s)'):
    assert text in report, (text, report)
for private in ('synthetic-secret', 'private@example.com', '/Users/private/project', 'file://'):
    assert private not in report, report
(ui.output / 'copied-report.md').write_text(report)
ui.capture('public-report-preview')

ui.axe('tap', '--label', catalog.text('feedback.github'), '--post-delay', '.4')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'feedback-status' and catalog.text('feedback.githubFailed') in item.get('AXLabel', '') for item in items), 'Offline GitHub failure did not preserve fallback actions')
assert copied() == report
ui.capture('offline-github-failure')
ui.axe('tap', '--label', catalog.text('feedback.github'), '--post-delay', '.4')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'feedback-status' and catalog.text('feedback.githubOpened') in item.get('AXLabel', '') for item in items), 'GitHub retry did not reach the client issue destination')
ui.capture('github-retry')

container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
previous_exports = set((container / 'tmp').glob('BugFeedback-*'))
tap('feedback-share')
ui.element('ActivityListView')
exports = list(set((container / 'tmp').glob('BugFeedback-*')) - previous_exports)
assert len(exports) == 1, exports
assert (exports[0] / 'Lody-iOS-Bug-Report.md').read_text() == report
assert (exports[0] / 'Screenshot-1.png').is_file(), 'System sharing must include the selected image, not just its count'
ui.capture('share-complete-report-and-image')
frame = ui.element('ActivityListView')['frame']
ui.axe('tap', '-x', '20', '-y', str(max(50, frame['y'] - 40)), '--post-delay', '.6')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'ActivityListView' for item in items), 'System sharing did not dismiss')
assert not exports[0].exists(), 'Temporary share exports must be removed after cancellation'
ui.wait(lambda items: any(item.get('AXUniqueId') == 'feedback-status' and catalog.text('feedback.shareCancelled') in item.get('AXLabel', '') for item in items), 'Cancelled sharing must retain the report')

reveal('feedback-preview-image-0')
tap('feedback-preview-image-0')
ui.element('QLPreviewControllerView')
ui.element('QLOverlayMarkupButtonAccessibilityIdentifier')
close_screenshot_at_edge('report', 'feedback-preview-image-0', -21, 0)

reveal('feedback-remove-image-0')
tap('feedback-remove-image-0')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'feedback-remove-image-0' for item in items), 'Removed screenshot remained in the report')
reveal('feedback-copy', down=False)
tap('feedback-copy')
assert 'Screenshots' not in copied()
ui.capture('screenshot-removed')
reveal('feedback-edit-report', down=False)
tap('feedback-edit-report')
reveal('feedback-description', down=False)
assert 'Composer keeps spinning' in ui.element('feedback-description').get('AXLabel', '')
close_feedback()
outcome = ui.element('feedback-fixture-outcome').get('AXLabel', '')
assert 'GitHub attempts: 2' in outcome and 'https://github.com/Innei/lody-ios/issues/new?' in outcome, outcome
tap('feedback-open')
assert 'Composer keeps spinning' in ui.element('feedback-description').get('AXLabel', '')
reveal('feedback-diagnostics')
assert 'Runtime: failed' in ui.element('feedback-diagnostics').get('AXLabel', '')
assert not any(item.get('AXUniqueId') == 'feedback-image-0' for item in ui.state()), 'Cancelled form restored a removed screenshot'
ui.capture('cancelled-draft-restored')
row = ui.element('feedback-diagnostics')['frame']
ui.axe('touch', '-x', str(row['x'] + row['width'] / 2), '-y', str(row['y'] + row['height'] / 2),
       '--down', '--up', '--delay', '.8')
ui.axe('tap', '--label', catalog.text('feedback.removeDiagnostics'), '--post-delay', '.4')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'feedback-diagnostics' and catalog.text('feedback.diagnosticsOff') in item.get('AXLabel', '') for item in items), 'Removed diagnostics remained in the draft')
reveal('feedback-preview')
tap('feedback-preview')
tap('feedback-copy')
assert 'Diagnostics' not in copied()
ui.capture('diagnostics-removed')
tap('feedback-edit-report')
close_feedback()
print('PASS: Settings entry, all report fields, editor cancellation, native screenshot preview/markup affordance, 44 pt Close touch area in form/report hosts without replay, unselected screenshot row after return, removal, optional scrubbed diagnostics, full copy/share, offline GitHub retry and retained draft')
