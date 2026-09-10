"""Leaving either composer host with an open popover returns to a usable Debug root."""
import json
import os
import subprocess
import sys
from driver import UI
from inspector import inspector

ui = UI(sys.argv[1], sys.argv[2])


def pid():
    lines = subprocess.check_output(['xcrun', 'simctl', 'spawn', ui.udid, 'launchctl', 'list'], text=True, timeout=20).splitlines()
    return next(line.split()[0] for line in lines if 'UIKitApplication:app.innei.lody[' in line)


original = pid()
for host in ['chat', 'sheet']:
    if host == 'sheet':
        for _ in range(8):
            if any(i.get('AXUniqueId') == 'model-memory' for i in ui.state()):
                break
            ui.axe('swipe', '--start-x', '200', '--start-y', '700', '--end-x', '200', '--end-y', '500', '--duration', '.4', '--post-delay', '.4')
        ui.axe('tap', '--id', 'model-memory', '--tap-style', 'physical', '--post-delay', '.6')
        ui.element('create-session-input')
    ui.axe('tap', '--id', 'session-input' if host == 'chat' else 'create-session-input', '--post-delay', '.6')
    ui.axe('tap', '--id', 'session-model', '--post-delay', '.5')
    ui.element('composer-model-menu')
    ui.capture(host + '-popover')
    inspector(ui.udid, os.environ['LODY_UI_METRO_PORT'], 'Runtime.evaluate', {'expression': 'globalThis.__lodyUiVerifyReset()'})
    ui.element('ui-verify-ready')
    ui.wait(lambda items: not any(i.get('AXUniqueId') in ['composer-model-menu', 'session-input', 'create-session-input'] for i in items), 'Previous composer/popover survived the root reset')
    assert pid() == original, 'Root reset replaced the App process'
    # A real tap proves the returned list is not blocked by a native presentation.
    ui.axe('tap', '--id', 'notification-preview', '--tap-style', 'physical', '--post-delay', '.5')
    ui.element('notification-preview-ready')
    inspector(ui.udid, os.environ['LODY_UI_METRO_PORT'], 'Runtime.evaluate', {'expression': 'globalThis.__lodyUiVerifyReset()'})
    ui.element('ui-verify-ready')
    ui.capture(host + '-returned')
print(json.dumps({'status': 'passed', 'hosts': ['chat', 'sheet'], 'appPid': original}))
