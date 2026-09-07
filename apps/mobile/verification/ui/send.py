"""Immediate offline user/shiny rows, exact failed draft restore, receipt reconciliation."""
import sys
from driver import UI
ui = UI(*sys.argv[1:])
ui.axe('tap', '--id', 'session-input')
ui.axe('type', 'Offline send\nKeep my attachment')
draft = ui.element('session-input')['AXValue']
attachments = [i['AXLabel'] for i in ui.state() if (i.get('AXLabel') or '').startswith('预览附件 ')]
assert attachments
ui.capture('draft')
ui.axe('tap', '--id', 'session-send')
shiny = ui.wait(lambda items: next((i for i in items if (i.get('AXUniqueId') or '').endswith(':pending')), None), 'Offline shiny row missing')
turn = shiny['AXUniqueId'].removesuffix(':pending')
assert ui.element('send-status')['AXLabel'] == 'Calls: 0 · waiting', 'Network ran before connection'
assert '等待连接' in shiny['AXLabel']
assert draft in ui.element(turn + ':user')['AXLabel']
assert not ui.element('session-input').get('AXValue')
ui.capture('offline')
ui.axe('tap', '--id', turn + ':pending')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 1 · sending' for i in items), 'Connected send did not start')
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXLabel') == '消息尚未发送' for i in items), 'Definite failure not surfaced')
ui.capture('failure-alert')
ui.axe('tap', '--label', 'OK')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == draft for i in items), 'Text was not restored')
assert [i['AXLabel'] for i in ui.state() if (i.get('AXLabel') or '').startswith('预览附件 ')] == attachments
assert not any(i.get('AXUniqueId') in [turn + ':user', turn + ':pending'] for i in ui.state()), 'Failed rows remain'
ui.capture('restored')
ui.axe('tap', '--id', 'session-send')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · sending' for i in items), 'Explicit retry did not start')
ui.axe('tap', '--id', 'send-complete')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · accepted' for i in items), 'Receipt missing')
ui.capture('waiting-reply')
ui.axe('tap', '--id', 'send-reply')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 2 · idle' for i in items), 'Reply did not reconcile local pending')
assert not any((i.get('AXUniqueId') or '').endswith(':pending') for i in ui.state())
ui.axe('tap', '--id', 'session-input')
ui.axe('type', 'next draft')
assert ui.element('session-input')['AXValue'] == 'next draft', 'Acknowledged draft re-locked input'
ui.capture('reconciled')
ui.axe('tap', '--id', 'session-send')
ui.wait(lambda items: any(i.get('AXLabel') == 'Calls: 3 · sending' for i in items), 'Third send missing')
ui.axe('type', 'followup')
assert ui.element('session-input')['AXValue'] == 'followup', 'Pending send dismissed or locked input'
ui.axe('tap', '--id', 'send-fail')
ui.wait(lambda items: any(i.get('AXLabel') == '消息尚未发送' for i in items), 'Failure alert missing')
ui.axe('tap', '--label', 'OK')
assert ui.element('session-input')['AXValue'] == 'followup', 'Failure overwrote next draft'
assert not ui.element('session-send')['enabled'], 'Unmerged failed draft must be retained'
ui.axe('tap', '--label', '有一条未发出的消息 · 点此合并到草稿')
assert ui.element('session-input')['AXValue'] == 'followup\n\nnext draft'
assert ui.element('session-send')['enabled']
ui.capture('merged-drafts')
print('PASS: offline immediate message/shiny, explicit rejection restore with attachment, retry and same-ID reply reconciliation')
