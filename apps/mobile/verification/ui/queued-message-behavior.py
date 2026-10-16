"""Preferences stay local, survive restart, and push native notification settings."""
import os
import plistlib
import subprocess
import sys
from pathlib import Path
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])

def choose(value):
    row = ui.element('queued-message-behavior')
    assert row['frame']['height'] >= 44
    ui.axe('tap', '--id', 'queued-message-behavior', '--post-delay', '.5')
    ui.capture(f'{value}-menu')
    ui.axe('tap', '--label', catalog.text(f'settings.queuedMessageBehavior.{value}'), '--post-delay', '.7')
    ui.wait(lambda _: ui.element('queued-message-behavior').get('AXValue') == catalog.text(f'settings.queuedMessageBehavior.{value}'), 'Selected value did not update')
    ui.element('notifications')
    ui.element('queued-message-behavior')
    ui.capture(f'{value}-selected')


ui.capture('preferences')
assert ui.element('notifications')['frame']['height'] >= 44
assert ui.element('quick-replies')['frame']['height'] >= 44
choose('queue')
choose('guide')
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
prefs = container / 'Library/Preferences/app.innei.lody.plist'


def saved():
    return plistlib.loads(prefs.read_bytes()).get('queuedMessageBehavior')


ui.wait(lambda _: saved() == 'guide', 'Steer preference was not persisted')
ui.axe('tap', '--id', 'notifications', '--post-delay', '.5')
permission = ui.element('notification-permission')
assert catalog.text('notifications.hint.signedOut') in permission['AXLabel']
ui.capture('notifications-signed-out')
ui.axe('drag', '--start-x', '2', '--start-y', '450', '--end-x', '65',
       '--end-y', '450', '--duration', '1', '--post-delay', '.6')
ui.element('notification-permission')
ui.capture('notification-pop-cancelled')
ui.axe('drag', '--start-x', '2', '--start-y', '450', '--end-x', '365',
       '--end-y', '450', '--duration', '.5', '--post-delay', '.6')
assert ui.element('queued-message-behavior')['AXValue'] == catalog.text('settings.queuedMessageBehavior.guide')
ui.capture('notification-returned')

subprocess.run(['xcrun', 'simctl', 'terminate', ui.udid, 'app.innei.lody'], check=True, timeout=30)
ui.invalidate_axe()
launch = ['xcrun', 'simctl', 'launch', ui.udid, 'app.innei.lody', '--ui-verify', '-AppleLanguages', '(en)', '-AppleLocale', 'en_US']
port = os.environ.get('LODY_UI_METRO_PORT')
if port:
    launch += ['--initialUrl', f'http://127.0.0.1:{port}?disableOnboarding=1']
subprocess.run(launch, check=True, timeout=30)
ui.element('ui-verify-ready', timeout=90)
ui.open_case('preferences-preview')
assert ui.element('queued-message-behavior')['AXValue'] == catalog.text('settings.queuedMessageBehavior.guide')
assert saved() == 'guide'
ui.capture('steer-restored-after-restart')
choose('queue')
ui.wait(lambda _: saved() == 'queue', 'Queue preference was not persisted')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('settings.preferences.title')), '--post-delay', '.5')
print('PASS: local preference persists through cold launch; native notification push, cancelled pop and return preserve it.')
