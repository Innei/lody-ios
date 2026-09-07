"""Offline image fixture in Debug chat preview; run through pnpm verify:ui."""
import json
from pathlib import Path
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / 'verification/ui'))
import catalog

udid, output = sys.argv[1], Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)


def axe(*args):
    return subprocess.check_output(['axe', *args, '--udid', udid], text=True)


def elements():
    def walk(node):
        yield node
        for child in node.get('children', []):
            yield from walk(child)
    return [item for root in json.loads(axe('describe-ui')) for item in walk(root)]


def capture(name):
    subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(output / f'{name}.png')], check=True)


items = elements()
height = items[0]['frame']['height']
IMAGE = catalog.text('native.chat.image.label', name='')
CLOSE = catalog.text('native.chat.image.closePreview')
source = next(item for item in items if (item.get('AXLabel') or '').startswith(IMAGE)
              and item['frame']['y'] > 100 and item['frame']['y'] + item['frame']['height'] < height - 110)
source_id = source['AXUniqueId']
assert source_id == 'preview-image:user', 'Use the offline image fixture'
name = source['AXLabel'].removeprefix(IMAGE)
axe('tap', '--id', source_id, '--post-delay', '1')
assert any(item.get('AXLabel') == CLOSE for item in elements()), 'Image must open the lightbox'
capture('opened')


def double_tap():
    image = next(item for item in elements() if item.get('AXLabel') == name)
    frame = image['frame']
    x = max(20, min(items[0]['frame']['width'] - 20, frame['x'] + frame['width'] / 2))
    y = max(120, min(height - 100, frame['y'] + frame['height'] / 2))
    axe('batch', '--step', f'tap -x {x} -y {y}', '--step', 'sleep 0.08',
        '--step', f'tap -x {x} -y {y}')
    time.sleep(0.6)
    return next(item for item in elements() if item.get('AXLabel') == name)


zoomed = double_tap()
assert int(zoomed['AXValue'].rstrip('%')) > 100, 'Double tap must enlarge the image'
capture('zoomed')
assert double_tap()['AXValue'] == '100%', 'Second double tap must restore fit'
axe('tap', '--label', CLOSE, '--post-delay', '0.7')
assert not any(item.get('AXLabel') == CLOSE for item in elements())
assert any(item.get('AXUniqueId') == source_id for item in elements()), 'Closing must return to the message'
capture('closed')
axe('tap', '--id', source_id, '--post-delay', '1')
assert any(item.get('AXLabel') == CLOSE for item in elements())
# Explicit HID drag reliably delivers move events to UIKit's interactive transition.
axe('drag', '--start-x', str(items[0]['frame']['width'] / 2), '--start-y', str(height * 0.45),
    '--end-x', str(items[0]['frame']['width'] / 2), '--end-y', str(height * 0.85),
    '--duration', '0.6', '--post-delay', '2')
assert not any(item.get('AXLabel') == CLOSE for item in elements()), 'Drag must dismiss the preview'
assert any(item.get('AXUniqueId') == source_id for item in elements())
capture('drag-closed')
print(json.dumps({'open': True, 'doubleTapZoom': zoomed['AXValue'], 'restoreFit': True,
                  'returnToMessage': True, 'dragDismiss': True}))
