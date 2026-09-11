"""Dark background choice applies immediately and remains accessible."""
import json
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])


def selected(identifier):
    return catalog.text('settings.history.selected') in (ui.element(identifier).get('AXLabel') or '')


def choose(identifier):
    ui.axe('tap', '--id', identifier, '--post-delay', '.7')
    ui.wait(lambda _: selected(identifier), f'{identifier} did not become selected')


choose('dark-background-soft')
assert not selected('dark-background-black')
ui.capture('soft')

choose('dark-background-black')
assert not selected('dark-background-soft')
ui.capture('black')

choose('dark-background-soft')
assert not selected('dark-background-black')
ui.capture('soft-restored')
print(json.dumps({'soft': '#111113', 'black': '#000000', 'restored': 'soft'}))
