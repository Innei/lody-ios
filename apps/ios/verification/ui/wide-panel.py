"""Activity stays a sheet; file navigation adapts between a sheet and split view."""
import sys
from driver import UI
import catalog
import pad
from rotation import rotate, restore_portrait

ui = UI(sys.argv[1], sys.argv[2])
close_panel = catalog.text('accessibility.closePanel')
close_file_sheet = catalog.text('accessibility.closeSheet', title=catalog.text('diff.title'))
close_activity = catalog.text('accessibility.closeSheet', title=catalog.text('process.title'))
file_row = 'diff-preview:changes:docs/superpowers/.diff-check.md'


def labeled(label):
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == label), None), f'Missing {label}')


def tap(frame):
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.8')


def sheet_close(label):
    frame = labeled(label)['frame']
    assert frame['y'] > ui.state()[0]['frame']['y'] + 40, ('Detail is a full-height drawer instead of a sheet', frame)
    return frame


def close(label):
    tap(labeled(label)['frame'])
    ui.wait(lambda items: not any(item.get('AXLabel') == label for item in items) or None, 'Detail did not close')
    ui.element('session-input')


try:
    for orientation in ('portrait', 'landscape'):
        rotate(ui, orientation)
        wide = orientation == 'landscape'
        pad.show_list(ui)
        if not any(item.get('AXUniqueId') == 'ui-design' for item in ui.state()):
            tap(max((item['frame'] for item in ui.state() if item.get('AXUniqueId') == 'toggle:ui:local:lody'),
                    key=lambda value: value['width'] * value['height']))
        ui.axe('tap', '--id', 'ui-design', '--post-delay', '.8')
        ui.element('session-input')

        tap(ui.element('a1:meta:details')['frame'])
        close_message = catalog.text('common.done')
        sheet_close(close_message)
        ui.capture(orientation + '-message-sheet')
        close(close_message)

        tap(ui.element('a1:process')['frame'])
        sheet_close(close_activity)
        ui.capture(orientation + '-activity-sheet')
        close(close_activity)

        ui.open_case('home-file-preview')
        ui.element(file_row)
        root_close = close_panel if wide else close_file_sheet
        frame = labeled(root_close)['frame']
        if wide:
            chat = ui.element('session-input')['frame']
            assert frame['x'] >= chat['x'] + chat['width'] - 1, ('File panel is not beside chat', frame, chat)
            ui.wait(lambda items: not pad.list_visible(items) or None, 'The list stayed beside the detail')
        else:
            sheet_close(root_close)
        ui.capture(orientation + '-file-root')
        ui.axe('tap', '--id', file_row)
        ui.element('diff-toolbar-stats')
        labeled('Unified')
        ui.capture(orientation + '-file-detail')
        if wide:
            rotate(ui, 'portrait')
            ui.element('diff-toolbar-stats')
            # The child remains on the same stack in a centered sheet.
            heading = labeled('.diff-check.md')['frame']
            assert heading['y'] > 40, ('File stack did not become a sheet', heading)
            ui.capture('file-stack-in-portrait-sheet')
            ui.open_case('appearance-preview')
            ui.element('account')
            rotate(ui, 'landscape')
            ui.element('account')
            ui.capture('transient-sheet-over-file-in-landscape')
            rotate(ui, 'portrait')
            ui.element('account')
            ui.capture('transient-sheet-over-file-in-portrait')
            close_settings = catalog.text('accessibility.closeSheet', title=catalog.text('tabs.settings'))
            tap(labeled(close_settings)['frame'])
            ui.wait(lambda items: not any(item.get('AXUniqueId') == 'account' for item in items) or None, 'Settings did not close')
            ui.element('diff-toolbar-stats')
            ui.open_case('home-native-alert')
            labeled('Layout verification')
            rotate(ui, 'landscape')
            labeled('Layout verification')
            ui.capture('native-alert-after-rotation')
            tap(labeled('OK')['frame'])
            ui.element('diff-toolbar-stats')
            ui.capture('file-stack-restored-landscape')
        ui.axe('tap', '--id', 'BackButton')
        ui.element(file_row)
        close(root_close)
        if wide:
            ui.wait(lambda items: pad.list_visible(items) or None, 'The list did not return after closing the detail')
        ui.capture(orientation + '-file-closed')
finally:
    restore_portrait(ui)

print('PASS: Activity is always a sheet; file detail stacks survive split/sheet rotation and closing restores the sidebar.')
