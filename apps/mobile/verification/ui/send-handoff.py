"""Real form-sheet dismissal/root push with the same local native message."""
import sys
from driver import UI
import catalog
from send_motion import ThrowTrace
ui = UI(*sys.argv[1:])
throw_trace = ThrowTrace(ui)
ui.axe('tap', '--id', 'create-session-input')
ui.axe('type', 'Carry this message\nInto the new conversation')
draft = ui.element('create-session-input')['AXValue']
ui.capture('source')
ui.axe('tap', '--id', 'session-send')
ui.element('send-status')
shiny = ui.wait(lambda items: next((i for i in items if (i.get('AXUniqueId') or '').endswith(':duration')), None), 'Target pending row missing')
turn = shiny['AXUniqueId'].removesuffix(':duration')
assert draft == ui.element(turn + ':user')['AXLabel']
assert ui.element('send-status')['AXLabel'] == 'Calls: 0 · waiting', 'Creation waited for network or dispatched offline'
ui.capture('target-offline')
ui.axe('tap', '--id', 'send-connect')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 1 · creating' for i in items), 'Creation did not start')
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('send.alert.title') for i in items), 'Creation failure missing')
ui.axe('tap', '--label', catalog.system('ok'))
assert not ui.element('session-input').get('AXValue'), 'Failure jumped into the destination input'
assert ui.element(turn + ':user')['AXLabel'] == draft
assert ui.element(turn + ':pending')['AXLabel'] == catalog.text('native.chat.message.retry')
ui.capture('target-failure-retained')
ui.axe('tap', '--id', turn + ':pending')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · creating' for i in items), 'Explicit creation retry did not start')
ui.capture('target-retrying')
print('PASS: first-turn handoff before network, retained creation failure and explicit retry')

throw_trace.verify(1)
