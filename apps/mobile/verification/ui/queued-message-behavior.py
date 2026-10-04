"""Settings choices update in place through native pop-up menus."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
for value in ["queue","guide","queue"]:
    row = ui.element('queued-message-behavior')
    assert row['frame']['height'] >= 44
    ui.axe('tap', '--id', 'queued-message-behavior', '--post-delay', '.5')
    ui.capture(f'{value}-menu')
    ui.axe('tap', '--label', catalog.text(f'settings.queuedMessageBehavior.{value}'), '--post-delay', '.7')
    ui.wait(lambda _: ui.element('queued-message-behavior').get('AXValue') == catalog.text(f'settings.queuedMessageBehavior.{value}'), 'Selected value did not update')
    ui.element('appearance')
    ui.element('notifications')
    ui.element('queued-message-behavior')
    ui.capture(f'{value}-selected')
print('PASS: native menu updates in place and restores the initial preference.')
