"""Offline production NativeChat draft contract; opened/reset by verify:ui."""
import argparse
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / 'verification/ui'))
from driver import UI
import catalog

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('udid')
parser.add_argument('--expect', choices=['success', 'failure'], required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
ui = UI(args.udid, args.output)
assert ui.element('composer-result')['AXLabel'] == 'Requests: 0', 'Use the offline composer scene'
ui.axe('tap', '--id', 'session-input')
ui.axe('type', 'Offline draft\nKeep the attachment')
draft = ui.element('session-input')['AXValue']
def attachments(items):
    prefix = catalog.text('native.chat.attachment.preview', name='')
    return [i['AXLabel'] for i in items if (i.get('AXLabel') or '').startswith(prefix)]
picked = attachments(ui.state())
assert picked, 'Synthetic attachment missing'
ui.capture('draft')
send = ui.element('session-send')
ui.axe('tap', '--id', 'session-send')
assert not ui.element('session-send')['enabled']
assert not ui.element('session-input').get('AXValue') and not attachments(ui.state()), 'Draft must clear while pending'
f = send['frame']
ui.axe('tap', '-x', str(f['x']+f['width']/2), '-y', str(f['y']+f['height']/2))
ui.capture('pending')
ui.axe('tap', '--label', 'Complete Request')
if args.expect == 'failure':
    ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == draft for i in items), 'Exact draft not restored')
    assert attachments(ui.state()) == picked and ui.element('session-send')['enabled']
else:
    ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-send' and i.get('AXLabel') == catalog.text('native.chat.composer.send') for i in items), 'Send did not settle')
    assert not ui.element('session-input').get('AXValue') and not attachments(ui.state())
assert ui.element('composer-result')['AXLabel'] == 'Requests: 1', 'Double tap must produce one request'
ui.capture('settled')
print(f'PASS: offline composer {args.expect}, text + attachment, duplicate suppression')
