"""The right panel in the iPad's current layout, without cloud.

Portrait is the tall layout: the list slides over the chat and the panel is a
sheet. Landscape is the wide layout: the panel replaces the list beside the chat.
"""
import sys
from driver import UI
import catalog
from rotation import rotate, restore_portrait

ui = UI(sys.argv[1], sys.argv[2])
close_panel = catalog.text('accessibility.closePanel')


def labeled(label):
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == label), None), f'Missing {label}')


def tap(frame):
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.8')


def list_visible(items):
    return any(item.get('AXUniqueId') == 'ipad-inbox-list' and item['frame']['x'] + item['frame']['width'] > 1 for item in items)


try:
    for orientation in ('portrait', 'landscape'):
        rotate(ui, orientation)
        close_panel = catalog.text('accessibility.closePanel')
        screen = ui.state()[0]['frame']
        wide = screen['width'] > screen['height']
        if not wide:
            close_panel = catalog.text('accessibility.closeSheet', title=catalog.text('process.title'))
        if not wide:
            ui.wait(lambda items: not list_visible(items) or None, 'The tall layout starts with the list beside the chat')
            tap(labeled(catalog.system('showSidebar'))['frame'])
        ui.element('ipad-inbox-list')
        if not any(item.get('AXUniqueId') == 'ui-design' for item in ui.state()):
            tap(max((item['frame'] for item in ui.state() if item.get('AXUniqueId') == 'toggle:ui:local:lody'),
                    key=lambda value: value['width'] * value['height']))
        ui.axe('tap', '--id', 'ui-design', '--tap-style', 'physical', '--post-delay', '.8')
        ui.element('session-input')
        if not wide:
            ui.wait(lambda items: not list_visible(items) or None, 'The list overlay stayed over the opened chat')
        ui.capture(orientation + '-chat')

        tap(ui.element('a1:process')['frame'])
        close = labeled(close_panel)['frame']
        ui.element('session-input')
        if wide:
            chat = ui.element('session-input')['frame']
            assert close['x'] >= chat['x'] + chat['width'] - 1, ('Panel is not beside the chat', close, chat)
            ui.wait(lambda items: not list_visible(items) or None, 'The list stayed beside the open panel')
        else:
            assert close['y'] > screen['y'] + 40, ('The tall panel is not a sheet over the chat', close)
        ui.capture(orientation + '-panel-open')
        if wide:
            rotate(ui, 'portrait')
            labeled(close_panel)
            ui.element('a1:read')
            ui.capture('inspector-after-portrait')
            rotate(ui, 'landscape')
            labeled(close_panel)
            ui.element('a1:read')
            ui.element('session-input')
            ui.capture('inspector-restored-landscape')

        tap(close)
        ui.wait(lambda items: not any(item.get('AXLabel') == close_panel for item in items) or None, 'Panel did not close')
        ui.element('session-input')
        if wide:
            ui.wait(lambda items: list_visible(items) or None, 'The list did not return after closing the panel')
        ui.capture(orientation + '-panel-closed')
finally:
    restore_portrait(ui)

print('PASS: tall sheets and wide inspectors preserve the session; the inspector survives rotation and closing restores the sidebar.')
