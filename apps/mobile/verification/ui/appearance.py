"""Settings choices update in place through native pop-up menus."""
import sys
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
    ui.element('queued-message-behavior')
    ui.capture(f'{value}-selected')
print('PASS: native menu updates in place and restores the initial preference.')
