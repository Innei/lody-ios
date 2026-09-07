"""Real form-sheet dismissal/root push with the same local native message."""
import sys
from driver import UI
ui = UI(*sys.argv[1:])
ui.axe('tap', '--id', 'create-session-input')
ui.axe('type', 'Carry this message\nInto the new conversation')
draft = ui.element('create-session-input')['AXValue']
ui.capture('source')
ui.axe('tap', '--id', 'session-send')
ui.element('send-status')
shiny = ui.wait(lambda items: next((i for i in items if (i.get('AXUniqueId') or '').endswith(':pending')), None), 'Target pending row missing')
turn = shiny['AXUniqueId'].removesuffix(':pending')
assert draft == ui.element(turn + ':user')['AXLabel']
assert ui.element('send-status')['AXLabel'] == 'Calls: 0 · waiting', 'Creation waited for network or dispatched offline'
ui.capture('target-offline')
ui.axe('tap', '--id', 'send-connect')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 1 · creating' for i in items), 'Creation did not start')
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXLabel') == '消息尚未发送' for i in items), 'Creation failure missing')
ui.axe('tap', '--label', 'OK')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == draft for i in items), 'Cross-page failed draft not restored')
assert not any(i.get('AXUniqueId') in [turn + ':user', turn + ':pending'] for i in ui.state())
ui.capture('target-restored')
print('PASS: new-session handoff before network, waiting shiny row, creation rejection restores in target composer')
