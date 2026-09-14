"""Queued message behavior is a local exclusive choice and can be restored."""
import json
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])


def selected(identifier):
    return catalog.text('settings.history.selected') in (
        ui.element(identifier).get('AXLabel') or ''
    )


def choose(identifier):
    ui.axe('tap', '--id', identifier, '--post-delay', '.7')
    ui.wait(lambda _: selected(identifier), f'{identifier} did not become selected')


choose('queued-message-behavior-queue')
assert not selected('queued-message-behavior-guide')
ui.capture('queue')

choose('queued-message-behavior-guide')
assert not selected('queued-message-behavior-queue')
ui.capture('guide')

choose('queued-message-behavior-queue')
assert not selected('queued-message-behavior-guide')
ui.capture('queue-restored')
print(json.dumps({'default': 'queue', 'guide': 'guide', 'restored': 'queue'}))
