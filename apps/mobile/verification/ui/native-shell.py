"""Real React events and state inside UIKit-owned navigation controllers."""
import json
import subprocess
import sys
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])


def label(text):
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == text), None), f'Missing {text}')


def tap_label(text):
    frame = label(text)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.5')


def counter(role):
    frame = ui.element(f'poc-{role}-counter')['frame']
    assert frame['height'] >= 44, frame
    ui.axe('swipe', '--start-x', str(frame['x'] + 20), '--start-y', str(frame['y'] + 22),
           '--end-x', str(frame['x'] + 23), '--end-y', str(frame['y'] + 22), '--duration', '.2', '--delta', '1')
    label(f'{role} count: 1')


ui.element('poc-root-counter')
ui.element('poc-detail-counter')
counter('root')
counter('detail')
root = ui.element('poc-root-counter')['frame']
detail = ui.element('poc-detail-counter')['frame']
assert detail['x'] > root['x'] + root['width'], (root, detail)
ui.capture('native-shell-columns')
ui.axe('tap', '--id', 'poc-search')
ui.axe('type', '30')
label('Session 30 — React content wraps inside the native column.')
ui.capture('native-shell-search')
tap_label('Project')
ui.element('poc-project-draft')
counter('project')
subprocess.run([str(ui.output.parents[1] / 'software-keyboard'),
                subprocess.check_output(['xcode-select', '-p'], text=True).strip(), ui.udid], check=True)
ui.axe('tap', '--id', 'poc-project-draft')
keyboard = ui.wait(lambda items: next((i['frame'] for i in items if (i.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar')), None), 'Software keyboard did not appear')
field = ui.element('poc-project-draft')['frame']
assert field['y'] + field['height'] < keyboard['y'], (field, keyboard)
ui.capture('native-shell-keyboard')
ui.type_into('poc-project-draft', 'retained react draft')
assert ui.element('poc-project-draft').get('AXValue') == 'retained react draft'
tap_label('Done')
frame = ui.element('poc-project-counter')['frame']
ui.axe('swipe', '--start-x', str(frame['x'] - 15), '--start-y', str(frame['y'] + 100),
       '--end-x', str(frame['x'] + 50), '--end-y', str(frame['y'] + 100), '--duration', '1.5')
label('React project · cancelled pops: 1')
assert ui.element('poc-project-draft').get('AXValue') == 'retained react draft'
ui.capture('native-shell-project')
tap_label('Native Sidebar')
ui.element('poc-root-counter')
label('root count: 1')
tap_label('Project')
label('project count: 0')
assert ui.element('poc-project-draft').get('AXValue') != 'retained react draft'
ui.capture('native-shell-project-reset')
inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '--json'], text=True))
name = next(d['name'] for group in inventory['devices'].values() for d in group if d['udid'] == ui.udid)
subprocess.run(['open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', ui.udid], check=True)


def rotate(turns):
    return subprocess.check_output(['osascript', '-e', f'''
tell application "Simulator" to activate
tell application "System Events" to tell process "Simulator"
  set targetWindow to first window whose name starts with "{name}"
  perform action "AXRaise" of targetWindow
  click menu bar item "Device" of menu bar 1
  set rotationItem to menu item "Rotate Device Automatically" of menu 1 of menu bar item "Device" of menu bar 1
  set wasAutomatic to value of attribute "AXMenuItemMarkChar" of rotationItem is not missing value
  if wasAutomatic then
    click rotationItem
  else
    key code 53
  end if
  repeat {turns} times
    perform action "AXPress" of (first button of toolbar 1 of targetWindow whose description is "Rotate")
    delay 0.6
  end repeat
  return wasAutomatic
end tell'''], text=True, timeout=25).strip() == 'true'


automatic = rotate(1)
try:
    ui.wait(lambda items: any(i.get('frame', {}).get('width', 0) > 1000 for i in items), 'Landscape did not arrive')
    ui.axe('tap', '--id', 'poc-detail-counter')
    label('detail count: 2')
    label('project count: 0')
    ui.capture('native-shell-landscape')
finally:
    rotate(3)
    if automatic:
        subprocess.run(['osascript', '-e', '''tell application "System Events" to tell process "Simulator"
click menu bar item "Device" of menu bar 1
click menu item "Rotate Device Automatically" of menu 1 of menu bar item "Device" of menu bar 1
end tell'''], check=True, timeout=10)
tap_label('Native Sidebar')
tap_label('close')
ui.element('native-shell-poc')
ui.capture('native-shell-closed')
print('PASS: native search, UIKit push/pop/cancel, React moved presses and state, keyboard, rotation and close')
