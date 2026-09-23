"""Free turn reminder appears at 25, updates with the remaining count, and hides for Plus."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])


def notice():
    return next((item for item in ui.state()
                 if item.get('AXUniqueId') == 'session-free-turn-notice' and item.get('AXLabel')), None)


assert notice() is None, 'The reminder appeared before 25 turns'
ui.axe('tap', '--id', 'free-turn-25')
ui.wait(lambda _: notice() is not None, 'The 25-turn reminder did not appear')
assert notice()['AXLabel'] == catalog.plural('chat.composer.freeTurnsRemaining', 5, remaining=5)
ui.capture('five-turns-left')
ui.axe('tap', '--id', 'free-turn-29')
ui.wait(lambda _: notice() and notice()['AXLabel'] == catalog.plural('chat.composer.freeTurnsRemaining', 1, remaining=1), 'The remaining count did not update')
ui.capture('one-turn-left')
ui.axe('tap', '--id', 'free-turn-30')
ui.wait(lambda _: notice() and notice()['AXLabel'] == catalog.text('chat.composer.freeTurnLimit'), 'The limit message did not appear')
ui.capture('limit-reached')
ui.axe('tap', '--id', 'free-turn-plus')
ui.wait(lambda _: notice() is None, 'Paid workspace still shows the Free reminder')
ui.capture('plus-no-reminder')
