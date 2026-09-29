"""Markdown shortcuts format in place, send as Markdown, and survive a rejected send."""
import json
import sys
from driver import UI

ui = UI(*sys.argv[1:])


def sent():
    return json.loads(ui.element('composer-sent')['AXLabel'])


def value():
    return ui.element('session-input').get('AXValue') or ''


ui.type_into('session-input', '**bold** and `code` ')
ui.wait(lambda items: value().rstrip() == 'bold and code', 'Shortcuts left their Markdown tags in the input')
ui.capture('formatted')
ui.axe('tap', '--id', 'session-send', '--post-delay', '.8')
assert sent().rstrip() == '**bold** and `code`', f'Sent body was not Markdown: {sent()!r}'
assert not value(), 'Pending draft must clear'
ui.axe('tap', '--id', 'complete-request', '--post-delay', '1')
ui.wait(lambda items: value().rstrip() == 'bold and code', 'Rejected send did not restore the draft')
ui.capture('restored')
ui.axe('tap', '--id', 'session-send', '--post-delay', '.8')
assert sent().rstrip() == '**bold** and `code`', f'Restored draft lost its formatting: {sent()!r}'
print('PASS: in-place shortcuts, Markdown send body and formatted restore after rejection')
