"""Record native Search fading across pushes, cancelled pops and returns.

Visual gate: compare run.mp4 with Settings. Search must blur/fade, not disappear
abruptly; its retiring glass must not reappear or remain after the transition.
The accessibility assertions below only establish settled ownership/usability.
"""
import json
import sys
import time

import catalog
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])
search_label = catalog.text('search.field.placeholder')


def home():
    ui.element('ui-design')
    ui.wait(lambda items: any(i.get('AXValue') == search_label for i in items),
            'Home search did not return')


def session():
    ui.element('session-input')
    ui.wait(lambda items: not any(i.get('AXValue') == search_label for i in items),
            'Home search leaked over the session')


events = []
started = time.monotonic()


def action(name, *arguments):
    events.append({'action': name, 'secondsFromFirstAction': time.monotonic() - started})
    ui.axe(*arguments)


home()
ui.capture('home')
for index in range(2):
    action(f'push-{index}', 'tap', '--id', 'ui-design', '--post-delay', '.8')
    session()
    ui.capture(f'pushed-{index}')
    action(f'cancel-pop-{index}', 'swipe', '--start-x', '1', '--start-y', '650',
           '--end-x', '65', '--end-y', '650', '--duration', '1', '--post-delay', '.8')
    session()
    ui.capture(f'cancelled-{index}')
    action(f'complete-pop-{index}', 'swipe', '--start-x', '1', '--start-y', '650',
           '--end-x', '350', '--end-y', '650', '--duration', '.5', '--post-delay', '.8')
    home()
    ui.capture(f'returned-{index}')

# Restored controls must remain usable after repeated transition cancellation.
action('activate-search', 'tap', '--value', search_label, '--post-delay', '.5')
ui.axe('type', 'Search')
if catalog.LANGUAGE != 'en':
    ui.axe('key', '40')
ui.element('ui-search')
ui.capture('search-active')
labels = {catalog.system('cancel').lower(), catalog.system('close').lower()}
button = ui.wait(lambda items: next((i for i in items if i.get('type') == 'Button'
                 and (i.get('AXLabel') or '').lower() in labels), None),
                 'Missing search dismiss button')
ui.axe('tap', '--label', button['AXLabel'], '--post-delay', '.5')
home()
ui.capture('search-cancelled')
(ui.output / 'transition-events.json').write_text(json.dumps(events, indent=2))
print('PASS: repeated Home pushes, cancelled edge pops and completed returns preserve settled toolbar ownership and usable search. VISUAL REVIEW REQUIRED: continuous native Search fade, no abrupt removal, late reappearance or post-transition residue.')
