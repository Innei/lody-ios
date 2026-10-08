"""Offline device liveness, per-session status and recovery without closing the creation sheet."""
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import time

import catalog
from driver import UI

ui = UI(*sys.argv[1:])
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
database = container / 'Library/Application Support/Lody/catalog.sqlite'
events = []
started = time.monotonic()


def seed(key, value):
    with sqlite3.connect(database, timeout=10) as db:
        db.execute('INSERT INTO cache(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', (key, json.dumps(value)))
    events.append({'key': key, 'value': value, 'seconds': time.monotonic() - started})


def presence(ids=None):
    seed('ui-device-presence', {'state': 'unknown' if ids is None else 'live', 'onlineMachineIds': ids or []})


def label(text):
    return ui.wait(lambda items: next((i for i in items if text in (i.get('AXLabel') or '')), None), 'Missing label: ' + text)


def tap_label(text):
    f = label(text)['frame']
    ui.axe('tap', '-x', str(f['x'] + f['width']/2), '-y', str(f['y'] + f['height']/2), '--post-delay', '.7')


def device_menu(state):
    tap_label(catalog.text('inbox.workspaceSwitch.accessibility', name=''))
    tap_label(catalog.text('devices.title'))
    label('Studio')
    label(state)


def close_menu():
    ui.axe('tap', '-x', '380', '-y', '820', '--post-delay', '.5')


def send_enabled(value):
    ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-send' and bool(i.get('enabled')) == value for i in items), 'Send availability did not update')


def draft_intact(expected):
    assert ui.element('create-session-input').get('AXValue') == expected, 'Device refresh replaced the draft'
    label('notes.txt')


def focus_creation():
    for _ in range(3):
        f = ui.element('create-session-input')['frame']
        ui.axe('tap', '-x', str(f['x'] + 30), '-y', str(f['y'] + f['height']/2), '--post-delay', '1.2')
        if any('UIKeyboard' in (i.get('AXUniqueId') or '') for i in ui.state()):
            return
    raise AssertionError('Creation composer did not focus the keyboard')


def capture_creation(name):
    assert not any(i.get('AXLabel') == 'Reload' for i in ui.state()), 'Developer menu obscures the creation form'
    ui.capture(name)


ui.element('ui-design')
label(catalog.text('devices.summary', count=2, total=3))
ui.capture('home-mixed')
device_menu(catalog.text('devices.offline'))
ui.capture('device-list')
close_menu()
presence([])
label(catalog.text('devices.summary', count=0, total=3))
device_menu(catalog.text('devices.offline'))
ui.capture('device-list-offline')
close_menu()
presence()
label(catalog.text('devices.unknown'))
device_menu(catalog.text('devices.unknown'))
ui.capture('device-list-unknown')
close_menu()
presence(['ui', 'mini'])
label(catalog.text('devices.summary', count=2, total=3))

if 'devices-pad' not in str(ui.output):
    ui.axe('tap', '--id', 'ui-design', '--post-delay', '.8')
    ui.element('session-input')
    label('Fixture Mac')
    ui.capture('session-online')
    ui.axe('tap', '--id', 'session-input')
    ui.type_into('session-input', 'Device status draft')
    draft = ui.element('session-input')['AXValue']
    presence(['mini'])
    label('Fixture Mac, ' + catalog.text('devices.offline'))
    ui.capture('session-offline')
    assert ui.element('session-input')['AXValue'] == draft
    presence(['ui'])
    label('Fixture Mac, ' + catalog.text('devices.online'))
    assert ui.element('session-input')['AXValue'] == draft
    back = ui.wait(lambda items: next((i for i in items if i.get('type') == 'Button' and i.get('AXLabel') == 'Back'), None), 'Missing native Back')
    f = back['frame']
    ui.axe('tap', '-x', str(f['x'] + f['width']/2), '-y', str(f['y'] + f['height']/2), '--post-delay', '.8')
    ui.element('ui-design')

    presence([])
    ui.open_case('create-recovery')
    ui.element('create-session-input')
    label(catalog.text('create.devices.failed'))
    send_enabled(False)
    capture_creation('create-load-failed')
    focus_creation()
    ui.axe('type', ' with edits')
    draft = ui.element('create-session-input')['AXValue']
    assert 'keep this draft' in draft.lower() and 'with edits' in draft.lower(), 'Typing did not edit the creation draft'
    seed('ui-device-options-error', False)
    label(catalog.text('create.devices.projectOffline'))
    draft_intact(draft)
    capture_creation('create-offline-draft')
    presence(['mini'])
    label(catalog.text('create.devices.projectOffline'))
    send_enabled(False)
    presence(['ui', 'mini'])
    label('Fixture Agent')
    send_enabled(True)
    draft_intact(draft)
    capture_creation('create-recovered')
    presence([])
    label(catalog.text('create.devices.projectOffline'))
    send_enabled(False)
    tap_label(catalog.text('create.type.chat'))
    ui.element('machine')
    label(catalog.text('create.devices.selectedOffline'))
    draft_intact(draft)
    capture_creation('chat-create-offline')
    presence(['ui'])
    label('Fixture Agent')
    send_enabled(True)
    draft_intact(draft)
    capture_creation('chat-create-recovered')
    tap_label(catalog.text('accessibility.closeSheet', title=catalog.text('create.title')))

(ui.output / 'device-events.json').write_text(json.dumps(events, indent=2))
print('PASS: device counts, unknown/offline distinction, per-session status and same-sheet recovery preserve drafts and attachments. Offline service fixture; no cloud request or message sent. Visual review required.')
