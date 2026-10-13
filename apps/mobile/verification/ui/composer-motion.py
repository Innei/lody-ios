"""Record empty composer/keyboard round trips with the context and suggestion row."""
import json
import subprocess
import sys
import time
from driver import UI

ui = UI(*sys.argv[1:])
events = []
ui.axe('tap', '--id', 'quick-reset')
ui.axe('tap', '--id', 'quick-preview')
ui.element('session-preview')


def assert_rendered_edges(name, field, chip, body):
    width = round(ui.state()[0]['frame']['width'])
    pixels = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(ui.output / f'{name}.png'),
                                     '-vf', f'scale={width}:-1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], timeout=20)

    def edge(frame, expected):
        y = round(frame['y'] + frame['height'] / 2)
        # Find the rendered rim, including the native glass stroke, independently of its AX frame.
        def contrast(x):
            return sum(abs(pixels[((y + dy) * width + x) * 3 + c] -
                           pixels[((y + dy) * width + x - 1) * 3 + c])
                       for dy in range(-1, 2) for c in range(3))
        found = max(range(round(expected) - 10, round(expected) + 11), key=contrast)
        assert abs(found - expected) <= 1, f'{name}: visible glass edge {found} differs from text baseline {expected}'

    edge(field, body['x'])
    edge(field, body['x'] + body['width'])
    edge(chip, body['x'])


for cycle in range(2):
    field = ui.element('session-input')['frame']
    body = ui.element('completed-reply:text')['frame']
    assert abs(field['x'] - body['x']) <= 1, 'Capsule leading edge differs from message text'
    assert abs(field['x'] + field['width'] - body['x'] - body['width']) <= 1, 'Capsule trailing edge differs from message text'
    chip = ui.element('session-preview')['frame']
    assert abs(chip['x'] - body['x']) <= 1, 'Context chip differs from message text'
    ui.capture(f'rest-{cycle}')
    assert_rendered_edges(f'rest-{cycle}', field, chip, body)
    events.append({'action': 'expand', 'start': time.time()})
    ui.axe('tap', '--id', 'session-input', '--post-delay', '.8')
    field = ui.element('session-input')['frame']
    assert field['height'] >= 120, 'Focus did not expand the composer'
    ui.wait(lambda items: any((i.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar')
                             and i['frame']['y'] < 750 for i in items), 'Software keyboard missing')
    attach = ui.element('session-attach')['frame']
    assert attach['width'] >= 44 and attach['height'] >= 44, 'Add lost its touch target'
    ui.capture(f'expanded-{cycle}')
    events.append({'action': 'collapse', 'start': time.time()})
    ui.axe('tap', '-x', '4', '-y', str(field['y'] - 110), '--post-delay', '.8')
    ui.wait(lambda items: abs(ui.element('session-input')['frame']['height'] - 48) <= 1,
            'Dismissal did not restore the capsule')
    ui.element('session-preview')
    ui.element('quick-reply:continue')
    ui.capture(f'collapsed-{cycle}')

(ui.output / 'motion-events.json').write_text(json.dumps(events, indent=2))
print('PASS: repeated keyboard expansion/collapse preserves context, suggestions and Add target')
