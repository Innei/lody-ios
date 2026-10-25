"""The tall iPad layout keeps the session list hidden until it is shown."""
import catalog


def list_visible(items):
    return any(
        item.get('AXUniqueId') == 'ipad-inbox-list' and item['frame']['x'] + item['frame']['width'] > 1
        for item in items
    )


def show_list(ui):
    show = catalog.system('showSidebar')
    items = ui.wait(
        lambda items: items if list_visible(items) or any(item.get('AXLabel') == show for item in items) else None,
        'Neither the session list nor its Show Sidebar button appeared',
    )
    if list_visible(items):
        return
    frame = next(item for item in items if item.get('AXLabel') == show)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2),
           '--tap-style', 'physical', '--post-delay', '.8')
    ui.wait(lambda items: list_visible(items) or None, 'The session list did not appear')
