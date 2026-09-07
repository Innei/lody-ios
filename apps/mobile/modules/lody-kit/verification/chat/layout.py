"""Run with the native chat preview open at the bottom: python3 layout.py SIMULATOR_UDID."""
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / 'verification/ui'))
from driver import UI
import catalog

udid = sys.argv[1]
ui = UI(udid, tempfile.mkdtemp(prefix='layout-ui-'))

def axe(*args):
    return subprocess.check_output(['axe', *args, '--udid', udid], text=True)

def rows(node):
    if isinstance(node, dict):
        if (node.get('AXUniqueId') or '').startswith('preview:'):
            yield node
        for value in node.values():
            yield from rows(value)
    elif isinstance(node, list):
        for value in node:
            yield from rows(value)

axe('tap', '--id', 'chat-navigation-title', '--post-delay', '0.3')
assert '原生 titleView 点击正常' in axe('describe-ui'), 'Native title must keep its tap action'
axe('tap', '--label', catalog.system('ok'), '--post-delay', '0.3')
axe('tap', '--label', 'Retry')
observations = []
saw_running = False
saw_segments = False
deadline = time.monotonic() + 45
while time.monotonic() < deadline:
    items = {item['AXUniqueId']: item for item in rows(json.loads(axe('describe-ui')))}
    saw_running |= any(catalog.text('native.chat.transcript.status.running') in item.get('AXLabel', '') for item in items.values())
    saw_segments |= 'preview:middle' in items and 'preview:process:thought-two' in items
    answer = items.get('preview:answer')
    summary = items.get('preview:process')
    for item in items.values():
        if item['AXUniqueId'].startswith('preview:process'):
            observations.append({'summary': item.get('AXLabel', ''), 'summaryFrame': item['frame']})
    if answer and '分割线之后的收尾段落' in answer.get('AXLabel', ''):
        break
    time.sleep(0.15)
assert saw_running and saw_segments, 'Did not observe the live text/process segments'
assert answer and '分割线之后的收尾段落' in answer['AXLabel'], 'Conclusion did not finish'
# Rich Markdown can be taller than the viewport. Bring the completed process
# entry into view before asserting its state; offscreen cells are not in AX.
for _ in range(8):
    items = {item['AXUniqueId']: item for item in rows(json.loads(axe('describe-ui')))}
    summary = items.get('preview:process')
    if summary and catalog.text('native.chat.transcript.status.done') in summary.get('AXLabel', ''):
        break
    axe('swipe', '--start-x', '200', '--start-y', '300', '--end-x', '200', '--end-y', '650', '--duration', '0.5', '--post-delay', '0.4')
else:
    raise AssertionError('Completed process entry not found')
assert 'preview:intro' not in items and 'preview:middle' not in items, 'Completion must fold intermediate prose'
observations.append({'summary': summary['AXLabel'], 'summaryFrame': summary['frame']})
for item in observations:
    assert abs(item['summaryFrame']['height'] - 44) <= 1, item['summaryFrame']
print(json.dumps({'samples': len(observations), 'nativeTitleAction': True,
                  'summaryHeight': 44, 'streamAndCompletionObserved': True}, indent=2))

if '--send' in sys.argv:
    # This path sends only to the local development preview, never a real session.
    assert '原生聊天预览' in axe('describe-ui')
    axe('tap', '--id', 'session-input', '--post-delay', '0.5')
    ui.type_into('session-input', 'keep this message at the top.')
    time.sleep(1)
    axe('tap', '--id', 'session-send')
    time.sleep(0.7)
    def find_user(node):
        if isinstance(node, dict):
            if (node.get('AXUniqueId') or '').endswith(':user') and 'keep this message at the top.' in (node.get('AXLabel') or '').lower():
                return node
            for value in node.values():
                found = find_user(value)
                if found:
                    return found
        elif isinstance(node, list):
            for value in node:
                found = find_user(value)
                if found:
                    return found
    first = find_user(json.loads(axe('describe-ui')))
    assert first and 100 <= first['frame']['y'] <= 150, first
    time.sleep(6)
    last = find_user(json.loads(axe('describe-ui')))
    # A long answer may naturally fill the viewport and push the message up;
    # completion must never pull a short answer back down to the bottom.
    if last:
        assert last['frame']['y'] <= first['frame']['y'] + 1, last
    print('Send: new user message anchored below the native header')
