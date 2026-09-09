"""Permission sheet opens ahead of its target and never costs the composer draft."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
close = catalog.text('accessibility.closeSheet', title=catalog.text('permission.title'))
DRAFT = '12345'


def open_sheet():
    ui.axe('tap', '--label', 'Fixtures')
    ui.axe('tap', '--label', 'Permission Fixture', '--post-delay', '0.5')
    ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('permission.waiting') for i in items),
            'Sheet must open before its target resolves', timeout=1)
    ui.wait(lambda items: any(i.get('AXLabel') == 'Allow once' for i in items),
            'Permission options never arrived')


def type_draft():
    ui.axe('tap', '--id', 'session-input', '--post-delay', '1')
    ui.axe('type', DRAFT)
    ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
            'Draft was not typed', timeout=10)


type_draft()
open_sheet()
assert any(i.get('AXLabel') == close for i in ui.state()), 'Non-dismissible sheet needs a close button'
assert any(i.get('AXLabel') == 'Custom choice' for i in ui.state()), 'Option without kind must remain actionable'
ui.capture('pending')
ui.axe('tap', '--label', close, '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Closing the sheet lost the composer draft')
ui.capture('closed')

open_sheet()
ui.axe('tap', '--label', 'Allow once', '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Answering the request lost the composer draft')
assert not any(i.get('AXLabel') == 'Allow once' for i in ui.state()), 'Sheet stayed up after answering'
ui.capture('answered')

open_sheet()
ui.wait(lambda items: not any(i.get('AXLabel') == 'Allow once' for i in items),
        'Sheet stayed up after the request was answered elsewhere', timeout=15)
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Remote answer lost the composer draft')
ui.capture('answered-elsewhere')
print('PASS: sheet opens before its target, keeps the draft through close, answer and remote answer')
