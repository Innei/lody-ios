"""Quick replies use the real composer/outbox, and local settings survive restart."""
import os
import subprocess
import sys
import time
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def chips():
    return [i for i in ui.state() if (i.get('AXUniqueId') or '').startswith('quick-reply:')]


def hidden():
    ui.wait(lambda items: not any((i.get('AXUniqueId') or '').startswith('quick-reply:') and i['frame']['height'] > 0 for i in items), 'Quick replies should be hidden')


def status(value):
    ui.wait(lambda items: any(i.get('AXLabel') == value for i in items), f'Missing {value}')


def type_field(identifier, text):
    # Let controlled RN inputs acknowledge each HID character before the next.
    for index, char in enumerate(text):
        ui.axe('type', char)
        ui.wait(lambda items: any(i.get('AXUniqueId') == identifier and (i.get('AXValue') or '').casefold() == text[:index + 1].casefold() for i in items), 'Input did not commit')


def settings():
    ui.axe('tap', '--id', 'quick-settings', '--post-delay', '.5')
    ui.axe('tap', '--id', 'quick-replies', '--post-delay', '.5')


def close_settings():
    back = [i for i in ui.state() if i.get('AXUniqueId') == 'BackButton'][-1]['frame']
    ui.axe('tap', '-x', str(back['x'] + back['width'] / 2), '-y', str(back['y'] + back['height'] / 2), '--post-delay', '.5')
    ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('tabs.settings')), '--post-delay', '.7')


ui.axe('tap', '--id', 'quick-reset', '--post-delay', '.8')
ui.element('quick-reply:continue')
assert len(chips()) == 3
by_id = {i['AXUniqueId']: i for i in chips()}
continue_chip = by_id['quick-reply:continue']['frame']
review_chip = by_id['quick-reply:review']['frame']
commit_chip = by_id['quick-reply:commit-push']['frame']
assert all(32 <= i['frame']['height'] <= 40 for i in chips()), [i['frame']['height'] for i in chips()]
assert all(i['frame']['width'] >= 44 for i in chips())
assert continue_chip['width'] < review_chip['width']
assert continue_chip['width'] < commit_chip['width']
assert continue_chip['width'] < 100, 'Continue must size to its title instead of filling an equal column'
ui.capture('idle')
ui.axe('tap', '--id', 'session-input')
ui.type_into('session-input', 'draft')
hidden()
ui.capture('draft-hidden')
for _ in range(5):
    ui.axe('key', '42')
ui.element('quick-reply:continue')
ui.axe('tap', '--id', 'quick-running', '--post-delay', '.5')
hidden()
ui.capture('running-hidden')
ui.axe('tap', '--id', 'quick-finish', '--post-delay', '.5')
ui.element('quick-reply:continue')
ui.axe('tap', '--id', 'quick-empty', '--post-delay', '.5')
hidden()
ui.axe('tap', '--id', 'quick-reset', '--post-delay', '.7')

# Click the short label, but send the full configured message.
# AXe typing connects a hardware keyboard; detach it again before this press check.
subprocess.run([str(ui.output.parents[1] / 'software-keyboard'), subprocess.check_output(['xcode-select', '-p'], text=True).strip(), ui.udid], check=True, timeout=30)
ui.axe('tap', '--id', 'session-input', '--tap-style', 'physical', '--post-delay', '1')
ui.wait(lambda items: any((i.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar') and i['frame']['y'] < 800 for i in items), 'Software keyboard did not appear')
chip = ui.element('quick-reply:commit-push')
if chip['frame']['x'] + chip['frame']['width'] > 390:
    y = chip['frame']['y'] + chip['frame']['height'] / 2
    ui.axe('swipe', '--start-x', '350', '--start-y', str(y), '--end-x', '80', '--end-y', str(y), '--duration', '.5', '--post-delay', '.5')
chip = ui.element('quick-reply:commit-push')['frame']
x, y = chip['x'] + chip['width'] / 2, chip['y'] + chip['height'] / 2
ui.capture('glass-resting')
ui.axe('touch', '-x', str(x), '-y', str(y), '--down')
try:
    ui.capture('glass-pressed')
    status('Calls: 0 · idle')
finally:
    ui.axe('touch', '-x', str(x), '-y', str(y), '--up')
status('Calls: 1 · sending')
hidden()
message = catalog.text('settings.quickReplies.defaults.commit-push.message')
user = ui.wait(lambda items: next((i for i in items if (i.get('AXUniqueId') or '').endswith(':user') and i.get('AXLabel') == message), None), 'Full quick-reply text missing from transcript')
turn = user['AXUniqueId'].removesuffix(':user')
ui.capture('sent')
ui.axe('tap', '--id', 'quick-fail')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('send.alert.title') for i in items), 'Missing failure alert')
ui.axe('tap', '--label', catalog.system('ok'))
assert ui.element(turn + ':user')['AXLabel'] == message
hidden()
ui.capture('failed-retained')
ui.axe('tap', '--id', turn + ':pending')
status('Calls: 2 · sending')
ui.axe('tap', '--id', 'quick-ack')
status('Calls: 2 · accepted')
hidden()
ui.axe('tap', '--id', 'quick-finish')
status('Calls: 2 · idle')
ui.element('quick-reply:continue')

settings()
ui.axe('tap', '--label', catalog.text('settings.quickReplies.add'), '--post-delay', '.5')
save = ui.wait(lambda items: next((i for i in items if i.get('AXLabel') == 'Save' and i.get('type') == 'Button'), None), 'Missing Save')
assert not save['enabled']
ui.capture('editor-empty')
ui.axe('tap', '--id', 'quick-reply-label')
type_field('quick-reply-label', 'Build')
ui.axe('tap', '--id', 'quick-reply-message')
type_field('quick-reply-message', 'Run the build.')
ui.capture('editor-filled')
ui.axe('tap', '--label', 'Save', '--post-delay', '.7')
row = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').startswith('Build') and i.get('AXUniqueId') and not i['AXUniqueId'].startswith('quick-reply:')), None), 'Saved quick reply missing')
custom_id = row['AXUniqueId']
ui.axe('tap', '--id', custom_id, '--post-delay', '.5')
ui.axe('tap', '--id', 'quick-reply-label')
for _ in range(5):
    ui.axe('key', '42')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'quick-reply-label' and not i.get('AXValue') for i in items), 'Name was not cleared')
type_field('quick-reply-label', 'Build Again')
ui.axe('tap', '--label', 'Save', '--post-delay', '.6')
assert 'Build Again' in ui.element(custom_id)['AXLabel']
ui.capture('settings-edited')

ui.axe('tap', '--label', 'Edit', '--post-delay', '.5')
source, target = ui.element(custom_id)['frame'], ui.element('continue')['frame']
x = source['x'] + source['width'] - 22
ui.axe('swipe', '--start-x', str(x), '--start-y', str(source['y'] + source['height'] / 2), '--end-x', str(x), '--end-y', str(target['y'] + target['height'] / 2 - 10), '--duration', '1', '--post-delay', '.8')
assert ui.element(custom_id)['frame']['y'] < ui.element('continue')['frame']['y'], 'Reorder did not update the list'
ui.capture('settings-reordered')
ui.axe('tap', '--label', 'Done', '--post-delay', '.4')
close_settings()
ui.element('quick-reply:' + custom_id)
assert chips()[0]['AXUniqueId'] == 'quick-reply:' + custom_id
ui.capture('custom-chip')

# Relaunch the real app to verify UserDefaults hydration, not only React state.
subprocess.run(['xcrun', 'simctl', 'terminate', ui.udid, 'app.innei.lody'], check=True, timeout=30)
ui.invalidate_axe()
launch = ['xcrun', 'simctl', 'launch', ui.udid, 'app.innei.lody', '--ui-verify', '-AppleLanguages', '(en)', '-AppleLocale', 'en_US']
port = os.environ.get('LODY_UI_METRO_PORT')
if port:
    launch += ['--initialUrl', f'http://127.0.0.1:{port}?disableOnboarding=1']
subprocess.run(launch, check=True, timeout=30)
ui.element('ui-verify-ready', timeout=90)
for _ in range(8):
    if any(i.get('AXUniqueId') == 'quick-replies-preview' and 140 <= i['frame']['y'] <= 700 for i in ui.state()):
        break
    ui.axe('swipe', '--start-x', '200', '--start-y', '700', '--end-x', '200', '--end-y', '500', '--duration', '.5', '--post-delay', '1.5')
time.sleep(1)
ui.capture('restart-menu')
preview = ui.element('quick-replies-preview')['frame']
ui.axe('tap', '-x', str(preview['x'] + preview['width'] / 2), '-y', str(preview['y'] + preview['height'] / 2), '--post-delay', '.8')
ui.element('quick-reset')
ui.element('quick-reply:' + custom_id)
assert chips()[0]['AXUniqueId'] == 'quick-reply:' + custom_id
assert chips()[0]['AXLabel'] == 'Build Again'
ui.capture('restored-after-restart')
settings()
row = ui.element(custom_id)['frame']
y = row['y'] + row['height'] / 2
ui.axe('swipe', '--start-x', str(row['x'] + row['width'] - 20), '--start-y', str(y), '--end-x', str(row['x'] + row['width'] / 2), '--end-y', str(y), '--duration', '.5', '--post-delay', '.5')
ui.axe('tap', '--label', 'Delete', '--post-delay', '.5')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('settings.quickReplies.deleteTitle') for i in items), 'Missing delete confirmation')
ui.axe('tap', '--label', 'Delete', '--post-delay', '.5')
assert not any(i.get('AXUniqueId') == custom_id for i in ui.state())
close_settings()
assert not any(i.get('AXUniqueId') == 'quick-reply:' + custom_id for i in chips())
ui.capture('deleted')
print('PASS: idle/draft/running/empty states, ordinary send and retry, add/edit/reorder/delete, and cold-start persistence.')
