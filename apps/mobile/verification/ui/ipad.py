"""UIKit owns the iPad sidebar, column layout, navigation and reveal transitions."""
import json
import plistlib
import shutil
import subprocess
import sys
import time

from driver import UI
import catalog


ui = UI(sys.argv[1], sys.argv[2])


def screen_frame():
    frames = [item['frame'] for item in ui.state() if item.get('frame')]
    return max(frames, key=lambda frame: frame['width'] * frame['height'])


def labeled(label):
    return ui.wait(
        lambda items: next(
            (item for item in items if item.get('AXLabel') == label), None
        ),
        f'Missing {label}',
    )


def search_field():
    return ui.wait(lambda items: next((item for item in items if item.get('subrole') == 'AXSearchField'), None), 'Missing sidebar search')


def assert_split_column(name):
    screen = screen_frame()
    panel = ui.element('ipad-panel')['frame']
    assert screen['width'] >= 700, f'iPad check ran on a narrow device: {screen}'
    assert abs(panel['x'] - screen['x']) < 1, (panel, screen)
    assert panel['width'] < screen['width'] * .75, (panel, screen)
    assert panel['height'] >= screen['height'] - 30, (panel, screen)
    ui.capture(name)


def assert_panel_layout():
    panel = ui.element('ipad-panel')['frame']
    composer = ui.element('session-input')['frame']
    panel_right = panel['x'] + panel['width']
    assert composer['x'] > panel_right, (composer, panel)


def assert_panel_chrome():
    panel = ui.element('ipad-panel')['frame']
    items = ui.state()
    search = search_field()
    view = next(
        item for item in items
        if item.get('AXLabel') == catalog.text('inbox.settings.section.view')
    )
    settings = next(
        item for item in items
        if item.get('AXLabel') == catalog.text('tabs.settings')
    )
    new_session = next(
        item for item in items
        if item.get('AXLabel') == catalog.text('tabs.newSession')
    )
    collapse = labeled(catalog.system('hideSidebar'))
    panel_bottom = panel['y'] + panel['height']
    assert view['frame']['y'] < panel['y'] + 80, (view, panel)
    assert settings['frame']['y'] < panel['y'] + 80, (settings, panel)
    assert search['frame']['y'] < panel['y'] + 150, (search, panel)
    assert new_session['frame']['y'] > panel_bottom - 110, (new_session, panel)
    assert new_session['frame']['x'] > panel['x'] + panel['width'] - 100, (new_session, panel)
    assert collapse['frame']['y'] < panel['y'] + 80, (collapse, panel)
    assert collapse['frame']['x'] + collapse['frame']['width'] <= panel['x'] + panel['width']


def assert_detail_content_fits():
    screen = screen_frame()
    panel = ui.element('ipad-panel')['frame']
    panel_right = panel['x'] + panel['width']
    screen_right = screen['x'] + screen['width']
    for identifier in ('u1:user', 'a1:process', 'a1:answer'):
        frame = ui.element(identifier)['frame']
        assert frame['x'] > panel_right, (identifier, frame, panel)
        assert frame['x'] + frame['width'] <= screen_right + .5, (identifier, frame, screen)


def rotate_device(turns=1, restore_automatic=False):
    inventory = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', '--json'], text=True, timeout=20,
    ))
    window_name = next(
        device['name']
        for devices in inventory['devices'].values()
        for device in devices
        if device['udid'] == ui.udid
    )
    subprocess.run(
        ['open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', ui.udid],
        check=True,
        timeout=20,
    )
    result = subprocess.run(
        [
            'osascript',
            '-e',
            f'''tell application "Simulator" to activate
tell application "System Events" to tell process "Simulator"
  if exists (first menu item of menu 1 of menu bar item "Window" of menu bar 1 whose name starts with "{window_name}") then
    click (first menu item of menu 1 of menu bar item "Window" of menu bar 1 whose name starts with "{window_name}")
    delay 0.5
  end if
  if not (exists (first window whose name starts with "{window_name}")) then
    click menu bar item "File" of menu bar 1
    delay 0.2
    click menu item "{window_name}" of menu 1 of menu item "iOS 26.5" of menu 1 of menu item "Open Simulator" of menu 1 of menu bar item "File" of menu bar 1
  end if
  set targetWindow to missing value
  repeat 80 times
    try
      set targetWindow to first window whose name starts with "{window_name}"
      perform action "AXRaise" of targetWindow
      exit repeat
    on error
      delay 0.25
    end try
  end repeat
  if targetWindow is missing value then error "Simulator window did not open"
  click menu bar item "Device" of menu bar 1
  delay 0.2
  set automaticRotation to menu item "Rotate Device Automatically" of menu 1 of menu bar item "Device" of menu bar 1
  set wasAutomatic to value of attribute "AXMenuItemMarkChar" of automaticRotation is not missing value
  if wasAutomatic then
    click automaticRotation
    delay 0.5
  else
    key code 53
  end if
  repeat {turns} times
    set rotated to false
    repeat 20 times
      try
        set targetWindow to first window whose name starts with "{window_name}"
        perform action "AXRaise" of targetWindow
        set rotateButton to first button of toolbar 1 of targetWindow whose description is "Rotate"
        perform action "AXPress" of rotateButton
        set rotated to true
        exit repeat
      on error
        delay 0.25
      end try
    end repeat
    if not rotated then error "Simulator rotate button was unavailable"
    delay 0.5
  end repeat
  if {str(restore_automatic).lower()} and not wasAutomatic then
    click menu bar item "Device" of menu bar 1
    delay 0.2
    click menu item "Rotate Device Automatically" of menu 1 of menu bar item "Device" of menu bar 1
  end if
  return wasAutomatic
end tell''',
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.strip() == 'true'


ui.element('ipad-detail-placeholder')
labeled(catalog.system('hideSidebar'))
# AX frames stay upright even when the simulated hardware is upside down.
# Restore this leased device's orientation before delivering physical touches.
for _ in range(4):
    preferences = plistlib.loads(subprocess.check_output(['defaults', 'export', 'com.apple.iphonesimulator', '-']))
    orientation = preferences.get('DevicePreferences', {}).get(ui.udid, {}).get('SimulatorWindowOrientation', 'Portrait')
    if orientation == 'Portrait':
        break
    rotate_device()
    time.sleep(.6)
else:
    raise AssertionError('Could not restore upright portrait orientation')
assert screen_frame()['height'] > screen_frame()['width']
assert_panel_chrome()
assert_split_column('portrait-home')

# Keep the same two-line rows and touch targets, with less empty space between projects.
project_row = ui.element('toggle:ui:local:lody')['frame']
session_row = ui.element('ui-design')['frame']
empty_row = ui.element('project:ui:empty')['frame']
assert project_row['height'] >= 44 and session_row['height'] >= 44
assert session_row['width'] >= ui.element('ipad-panel')['frame']['width'] - 24
assert empty_row['y'] - project_row['y'] < 130, (project_row, empty_row)
ui.axe('tap', '-x', str(project_row['x'] + 60),
       '-y', str(project_row['y'] + project_row['height'] / 2), '--post-delay', '.6')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'ui-design' for item in items),
        'Sidebar project did not collapse')
ui.capture('sidebar-project-collapsed')
project_row = ui.element('toggle:ui:local:lody')['frame']
ui.axe('tap', '-x', str(project_row['x'] + 60),
       '-y', str(project_row['y'] + project_row['height'] / 2), '--post-delay', '.6')
ui.element('ui-design')
ui.capture('sidebar-project-expanded')

# The stacked native search drives the production filter and clears it again.
field = search_field()['frame']
ui.axe('tap', '-x', str(field['x'] + field['width'] / 2), '-y', str(field['y'] + field['height'] / 2), '--post-delay', '.5')
ui.axe('type', 'lody')
ui.element('ui-design')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'project:ui:empty' for item in items),
        'Sidebar search did not filter the empty project')
ui.capture('sidebar-search-keyboard')
ui.axe('tap', '--label', catalog.system('clear'), '--post-delay', '.4')
ui.axe('key', '40')
ui.element('project:ui:empty')

# Contextual creation keeps its native detents and stays inside the panel.
panel = ui.element('ipad-panel')['frame']
ui.axe(
    'tap', '--label', catalog.text('tabs.newSession'),
    '--tap-style', 'physical', '--post-delay', '1',
)
if not any(item.get('AXUniqueId') == 'create-session-input' for item in ui.state()):
    ui.axe(
        'tap', '--label', catalog.text('tabs.newSession'),
        '--tap-style', 'physical', '--post-delay', '1',
    )
composer = ui.element('create-session-input')['frame']
surface = ui.element('ipad-sheet-surface')['frame']
assert abs(surface['x'] - panel['x'] - 10) < 1, (surface, panel)
assert abs(surface['width'] - panel['width'] + 20) < 1, (surface, panel)
assert abs(surface['y'] + surface['height'] - panel['y'] - panel['height'] + 10) < 1
assert not any(item.get('AXUniqueId') == 'ipad-search' for item in ui.state()), 'Search leaked through the modal scope'
assert composer['x'] >= panel['x'], (composer, panel)
assert composer['x'] + composer['width'] <= panel['x'] + panel['width'], (
    composer, panel,
)
assert composer['y'] >= panel['y'], (composer, panel)
assert composer['y'] + composer['height'] <= panel['y'] + panel['height'], (
    composer, panel,
)
ui.capture('panel-create-sheet')
sheet = ui.element('ipad-panel-sheet')['frame']
sheet_x = int(sheet['x'] + sheet['width'] / 2)
# Drag through the creation screen's scroll view. At its top edge the native
# sheet must take ownership and expand before the content scrolls.
ui.axe(
    'swipe', '--start-x', str(sheet_x), '--start-y', str(int(sheet['y'] + 240)),
    '--end-x', str(sheet_x), '--end-y', str(int(panel['y'] + 80)),
    '--duration', '.5', '--post-delay', '.5',
)
expanded = ui.element('ipad-panel-sheet')['frame']
assert expanded['y'] < sheet['y'] - 100, (expanded, sheet)
expanded_surface = ui.element('ipad-sheet-surface')['frame']
for key in ('x', 'y', 'width', 'height'):
    assert abs(expanded_surface[key] - panel[key]) < 1, (expanded_surface, panel)
ui.capture('panel-create-sheet-expanded')

# Inner navigation stays in the same sheet and restores the production form.
ui.axe('tap', '--id', 'project', '--post-delay', '.6')
ui.element('ui:local:lody')
ui.capture('panel-create-project-picker')
ui.axe('tap', '--id', 'BackButton', '--tap-style', 'physical', '--post-delay', '.6')
ui.element('create-session-input')
ui.axe(
    'swipe', '--start-x', str(sheet_x),
    '--start-y', str(int(expanded['y'] + 240)),
    '--end-x', str(sheet_x), '--end-y', str(int(expanded['y'] + 480)),
    '--duration', '.5', '--post-delay', '.5',
)
collapsed = ui.element('ipad-panel-sheet')['frame']
assert collapsed['y'] > expanded['y'] + 100, (collapsed, expanded)
collapsed_surface = ui.element('ipad-sheet-surface')['frame']
for key in ('x', 'y', 'width', 'height'):
    assert abs(collapsed_surface[key] - surface[key]) < 1, (collapsed_surface, surface)
ui.capture('panel-create-sheet-collapsed')
ui.axe(
    'swipe', '--start-x', str(sheet_x),
    '--start-y', str(int(collapsed['y'] + 10)),
    '--end-x', str(sheet_x), '--end-y', str(int(collapsed['y'] + 200)),
    '--duration', '.5', '--post-delay', '.8',
)
ui.wait(
    lambda items: not any(
        item.get('AXUniqueId') == 'ipad-panel-sheet' for item in items
    ),
    'Panel sheet did not dismiss from its medium detent',
)
labeled(catalog.text('tabs.newSession'))

# The project is a second ScreenStackItem owned by the panel, with its own title
# and native Back button while the root detail remains unchanged.
ui.axe('tap', '--id', 'project:ui:empty', '--post-delay', '1')
ui.wait(
    lambda items: any(
        (item.get('AXLabel') or '') == catalog.text('project.newSession.accessibility')
        for item in items
    ),
    'Panel project action did not appear',
)
ui.element('BackButton')
ui.wait(
    lambda items: any((item.get('AXLabel') or '') == '空盒子' for item in items),
    'Panel project header did not appear',
)
ui.capture('project-pushed')

ui.axe('tap', '--id', 'BackButton', '--tap-style', 'physical', '--post-delay', '.8')
ui.axe('tap', '--id', 'ui-design', '--post-delay', '1')
ui.element('session-input')
ui.element('ipad-panel')
ui.element('chat-navigation-title')
assert_panel_layout()
assert_detail_content_fits()
ui.capture('session-and-panel-headers')
ui.axe('tap', '--id', 'session-input', '--tap-style', 'physical', '--post-delay', '.6')
ui.capture('session-glass-focused')
ui.axe('key', '41')

# Exercise the translucent panel header with content moving through its soft
# top scroll edge.
panel = ui.element('ipad-panel')['frame']
x = int(panel['x'] + panel['width'] / 2)
ui.axe(
    'swipe', '--start-x', str(x), '--start-y', '700',
    '--end-x', str(x), '--end-y', '360', '--duration', '.5', '--post-delay', '.7',
)
ui.capture('panel-scrolled-edge')

ui.axe('tap', '--label', catalog.system('hideSidebar'), '--post-delay', '.5')
expand = labeled(catalog.system('showSidebar'))
assert expand['frame']['x'] < 100 and expand['frame']['y'] < 100, expand
ui.element('chat-navigation-title')
time.sleep(.4)
ui.capture('panel-collapsed')
ui.axe('tap', '--label', catalog.system('showSidebar'), '--post-delay', '.7')
labeled(catalog.system('hideSidebar'))
ui.element('chat-navigation-title')
assert_panel_layout()

# Verify the system page sheet is centered and narrower than the iPad window.
# Its visual capture proves the opaque surface.
ui.axe(
    'tap', '--label', catalog.text('tabs.settings'),
    '--tap-style', 'physical', '--post-delay', '1',
)
account = ui.element('account')['frame']
screen = screen_frame()
assert account['width'] < screen['width'] - 80, (account, screen)
assert account['x'] > screen['x'] + 40, (account, screen)
ui.capture('centered-opaque-settings')
close = catalog.text('accessibility.closeSheet', title=catalog.text('tabs.settings'))
ui.axe('tap', '--label', close, '--post-delay', '1')
labeled(catalog.system('hideSidebar'))

def create_and_send(landscape):
    name = 'landscape' if landscape else 'portrait'
    labeled(catalog.text('tabs.newSession'))
    ui.axe('tap', '--label', catalog.text('tabs.newSession'),
           '--tap-style', 'physical', '--post-delay', '1')
    ui.element('create-session-input')
    ui.axe('tap', '--id', 'create-session-input', '--post-delay', '.5')
    message = f'iPad {name} new message'
    ui.type_into('create-session-input', message)
    ui.capture(f'{name}-before-send')
    print(f'SEND {name} at {time.time()}', flush=True)
    panel = ui.element('ipad-panel')['frame']
    send = next(item['frame'] for item in ui.state()
                if item.get('AXUniqueId') == 'session-send'
                and panel['x'] <= item['frame']['x'] < panel['x'] + panel['width'])
    ui.axe('tap', '-x', str(send['x'] + send['width'] / 2),
           '-y', str(send['y'] + send['height'] / 2), '--post-delay', '.8')
    ui.wait(lambda items: not any(item.get('AXUniqueId') == 'create-session-input' for item in items),
            'Creation sheet did not close after sending')
    ui.wait(lambda items: any(message in (item.get('AXLabel') or '') and
                             (item.get('AXUniqueId') or '').endswith(':user') for item in items),
            'New session did not retain the first message')
    ui.element('session-input')
    labeled(catalog.system('hideSidebar'))
    assert_panel_layout()
    ui.capture(f'{name}-after-send')


create_and_send(False)
ui.axe('tap', '--id', 'ui-design', '--post-delay', '.5')
automatic_rotation = rotate_device()
try:
    time.sleep(1)
    screen = screen_frame()
    assert screen['width'] > screen['height'], screen
    ui.element('session-input')
    ui.element('chat-navigation-title')
    assert_panel_layout()
    assert_detail_content_fits()
    assert_split_column('landscape-session')
    landscape = ui.output / 'landscape-session.png'
    shutil.copy2(landscape, ui.output / 'landscape-session-raw.png')
    subprocess.run(['sips', '-r', '90', str(landscape)], check=True, timeout=20)
    create_and_send(True)
finally:
    rotate_device(3, restore_automatic=automatic_rotation)
    time.sleep(1)
    assert screen_frame()['height'] > screen_frame()['width']

print('PASS: System sidebar, safe-area content, creation, selection, cancellation, navigation and rotation work in both orientations.')
