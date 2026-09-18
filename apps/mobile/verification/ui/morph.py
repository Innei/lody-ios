"""Production creation sheet: close, backdrop and composer relay share the morph."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
folder = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip()) / 'tmp'
before = set(folder.glob('lody-morph-*.json'))
close = catalog.text('accessibility.closeSheet', title=catalog.text('create.title'))

def open_sheet():
    buttons = [i for i in ui.state() if i.get('type') == 'Button' and i.get('frame')]
    frame = max(buttons, key=lambda i: i['frame']['y'])['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1')
    ui.element('create-session-input')

for action in ('close', 'backdrop', 'send'):
    open_sheet()
    ui.capture(action + '-open')
    if action == 'close':
        header = next(i['frame'] for i in ui.state() if i.get('AXLabel') == close)
        x, y = header['x'] + header['width'] / 2, header['y'] + header['height'] / 2
        ui.axe('swipe', '--start-x', str(x), '--start-y', str(y),
               '--end-x', str(x), '--end-y', str(y + 45), '--duration', '1', '--post-delay', '1')
        ui.element('create-session-input')
        ui.capture('cancelled-drag')
        ui.axe('tap', '--label', close, '--post-delay', '1')
    elif action == 'backdrop':
        ui.axe('tap', '-x', '30', '-y', '180', '--tap-style', 'physical', '--post-delay', '1')
    else:
        (folder / 'lody-production-composer-relay.json').unlink(missing_ok=True)
        frame = ui.element('create-type')['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] * .75), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '1')
        ui.axe('tap', '--id', 'create-session-input')
        ui.type_into('create-session-input', 'Morph handoff')
        subprocess.run([str(ui.output.parent.parent / 'software-keyboard'), subprocess.check_output(['xcode-select', '-p'], text=True).strip(), ui.udid], check=True, timeout=30)
        ui.capture('send-draft')
        draft = ui.element('create-session-input')['AXValue']
        ui.axe('tap', '--id', 'session-send', '--post-delay', '1')
        ui.element('session-input')
        ui.wait(lambda items: any(i.get('AXLabel') == draft and (i.get('AXUniqueId') or '').endswith(':user') for i in items), 'Sent draft did not reach the conversation')
        relay = json.loads((folder / 'lody-production-composer-relay.json').read_text())
        assert relay['sameComposer'] and relay['inputBefore'] == relay['inputAfter'], 'Morph interrupted the composer handoff'
        assert relay['inputBefore']['focused'], 'Morph lost keyboard focus'
        assert all(abs(a - b) < 1.5 for a, b in zip(relay['source'], relay['adopted'])), 'Composer jumped after the morph'
        shutil.copy2(folder / 'lody-production-composer-relay.json', ui.output)
    ui.wait(lambda items: not any(i.get('AXUniqueId') == 'create-session-input' for i in items), action + ' left the sheet visible')
    ui.capture(action + '-closed')
    paths = set(folder.glob('lody-morph-*.json')) - before
    reports = [json.loads(path.read_text()) for path in paths]
    dismissals = [report for report in reports if report['reverse']]
    assert len(dismissals) == 1, f'{action}: expected one reverse morph, got {len(dismissals)}'
    samples = dismissals[0]['samples']
    assert len(samples) >= 4, f'{action}: missing animation frames'
    assert any(.1 < sample['scale'] < .9 for sample in samples), f'{action}: sheet did not shrink'
    assert all(sample['dismissing'] for sample in samples), f'{action}: morph ran before UIKit dismissal, leaving background glass dimmed until teardown'
    assert samples[0]['dimming'], f'{action}: missing the backdrop'
    assert all(view['selected'] or view['alpha'] == 0 for view in dismissals[0]['hierarchy'] if 'dimming' in view['class'].lower()), f'{action}: a visible window backdrop was left outside the animation'
    for layer in range(len(samples[0]['dimming'])):
        assert any(.1 < sample['dimming'][layer] < .9 for sample in samples), f'{action}: overlay {layer} did not fade with the sheet'
        assert samples[-1]['dimming'][layer] < .05, f'{action}: overlay {layer} remained after the morph'
    for path in paths:
        shutil.copy2(path, ui.output / (action + '-' + path.name))
    before.update(paths)
print('PASS: close, backdrop and send share a shrinking sheet and fading overlay')
