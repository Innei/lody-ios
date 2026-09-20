"""Settings choices update in place through native pop-up menus."""
import sys
import subprocess
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
for value in ["soft","black","soft"]:
    row = ui.element('appearance')
    assert row['frame']['height'] >= 44
    ui.axe('tap', '--id', 'appearance', '--post-delay', '.5')
    ui.capture(f'{value}-menu')
    ui.axe('tap', '--label', catalog.text(f'settings.appearance.{value}'), '--post-delay', '.7')
    ui.wait(lambda _: ui.element('appearance').get('AXValue') == catalog.text(f'settings.appearance.{value}'), 'Selected value did not update')
    ui.element('appearance')
    ui.element('notifications')
    ui.capture(f'{value}-selected')
for value in ['purple', 'pink', 'indigo', 'blue']:
    assert ui.element('accent-color')['frame']['height'] >= 44
    ui.axe('tap', '--id', 'accent-color', '--post-delay', '.3')
    ui.axe('tap', '--label', catalog.text(f'settings.appearance.{value}'), '--post-delay', '.5')
    ui.wait(lambda _: ui.element('accent-color').get('AXValue') == catalog.text(f'settings.appearance.{value}'), 'Accent selection did not update')
    ui.capture(f'accent-{value}')

# Exercise the real UIApplication API and its completion state, including reset.
for value, label in [('default', catalog.text('settings.appearance.defaultIcon')), ('Aqua', 'Aqua'), ('default', catalog.text('settings.appearance.defaultIcon'))]:
    row = ui.element('app-icon')
    assert row['frame']['height'] >= 44
    if row.get('AXValue') == label:
        continue
    ui.axe('tap', '--id', 'app-icon', '--post-delay', '.3')
    ui.axe('tap', '--label', label, '--post-delay', '1')
    # SpringBoard's changed-icon alert can expose an empty AX tree. Try its
    # label first; the fallback is the observed centered OK button on our
    # default iPhone Verify device. The selected value below must still match.
    ui.screenshot(f'icon-{value}-system-confirmation')
    try:
        ui.axe('tap', '--label', 'OK', '--post-delay', '.5', timeout=3, recover=False)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError):
        ui.axe('tap', '-x', '201', '-y', '505', '--post-delay', '.5')
    ui.invalidate_axe()
    ui.wait(lambda items: any(item.get('AXUniqueId') == 'app-icon' and item.get('AXValue') == label for item in items), 'System icon change did not complete')
    ui.capture(f'icon-{value}')
print('PASS: appearance menus, all accents, and real alternate icon switching/reset.')
