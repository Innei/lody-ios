"""Immediate offline media/text, retained failure, explicit retry and history reconciliation."""
import sys
from driver import UI
import catalog
from send_motion import ThrowTrace
ui = UI(*sys.argv[1:])
trace = ThrowTrace(ui)
ui.axe('tap', '--id', 'session-input')
ui.axe('type', 'Offline send\nKeep my attachment')
draft = ui.element('session-input')['AXValue']
ui.capture('draft')
ui.axe('tap', '--id', 'session-send')
timer = ui.wait(lambda items: next((i for i in items if (i.get('AXUniqueId') or '').endswith(':duration')), None), 'Offline timer missing')
turn = timer['AXUniqueId'].removesuffix(':duration')
assert ui.element('send-status')['AXLabel'] == 'Calls: 0 · waiting'
assert ui.element(turn + ':user-text')['AXLabel'] == draft
ui.element(turn + ':attachment:fixture-file')
assert not ui.element('session-input').get('AXValue')
ui.capture('offline')
ui.axe('tap', '--id', turn + ':pending')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 1 · sending' for i in items), 'Connected send did not start')
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('send.alert.title') for i in items), 'Failure alert missing')
ui.axe('tap', '--label', catalog.system('ok'))
assert not ui.element('session-input').get('AXValue'), 'Failed text jumped back into input'
assert ui.element(turn + ':user-text')['AXLabel'] == draft
ui.element(turn + ':attachment:fixture-file')
assert ui.element(turn + ':pending')['AXLabel'] == catalog.text('native.chat.message.retry')
ui.capture('failure-retained')
ui.axe('tap', '--id', turn + ':pending')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · sending' for i in items), 'Explicit retry did not start')
ui.axe('tap', '--id', 'send-complete')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · accepted' for i in items), 'Receipt missing')
ui.capture('waiting-reply')
ui.axe('tap', '--id', 'send-reply')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · idle' for i in items), 'Reply did not reconcile pending')
assert ui.element(turn + ':user-text')['AXLabel'] == draft
ui.element(turn + ':attachment:fixture-file')
ui.capture('reconciled')
ui.axe('tap', '--id', 'session-input')
ui.type_into('session-input', '2 next draft')
# Let the measured throw settle before driving another input mutation.
ui.axe('tap', '--id', 'session-send', '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 3 · sending' for i in items), 'Next send missing')
ui.type_into('session-input', '3 next draft')
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('send.alert.title') for i in items), 'Failure alert missing')
ui.axe('tap', '--label', catalog.system('ok'))
assert ui.element('session-input')['AXValue'] == '3 next draft', 'Failure overwrote new input'
assert not ui.element('session-send')['enabled'], 'Retained failure must not be overwritten by a new send'
ui.capture('new-draft-preserved')
trace.verify(2)
print('PASS: offline media/text, retained failure and explicit retry without another throw, history takeover, new draft preserved')
