"""Keep project fixture gestures inside the visible native content."""


def viewport(items, toolbar_labels):
    app = next(item for item in items if item.get('type') == 'Application')
    frame = app['frame']
    top = frame['y'] + 120
    bottom = frame['y'] + frame['height'] - 44
    for item in items:
        item_frame = item.get('frame') or {}
        y = item_frame.get('y', bottom)
        if str(item.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar'):
            bottom = min(bottom, y - 12)
        if (item.get('type') == 'Button' and y < frame['y'] + 160
                and (item.get('AXUniqueId') == 'BackButton' or item.get('AXLabel') in toolbar_labels)):
            top = max(top, y + item_frame.get('height', 0) + 12)
    return top, bottom


def visible_target(item, bounds):
    if not item:
        return False
    frame = item['frame']
    center = frame['y'] + frame['height'] / 2
    half_height = max(44, frame['height']) / 2
    return bounds[0] <= center - half_height and center + half_height <= bounds[1]


def scroll_direction(item, bounds, missing_direction):
    if not item:
        return missing_direction
    frame = item['frame']
    if frame['y'] < bounds[0]:
        return 'up'
    return 'down'


def scroll_points(direction, bounds):
    upper, lower = bounds[0] + 60, bounds[1] - 40
    if direction == 'up':
        return upper, lower
    return lower, upper
