"""Existing running text never replays; only a subsequent live append animates."""
import json
import os
import sys
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])


def probe(items):
    node = next((item for item in items if item.get('AXUniqueId') == 'session-preview-probe'), None)
    return json.loads(node.get('AXValue') or '{}') if node else {}


def phase(name):
    def ready(items):
        value = probe(items)
        return value if name in value.get('seen', []) else None
    return ui.wait(ready, f'Missing {name} snapshot')


phase('restore')
ui.capture('restored-running-reply')
ui.axe('tap', '--label', 'Append')
ui.wait(lambda items: probe(items).get('paced') and probe(items).get('faded'), 'Live suffix did not animate')
ui.capture('live-append')
ui.axe('tap', '--label', 'Catch up')
result = phase('catchup')
ui.capture('reconnected-running-reply')
(ui.output / 'stream-restoration.json').write_text(json.dumps(result, indent=2))
if os.environ.get('LODY_STREAM_RECORD_BEFORE') == '1':
    assert result['failures'], 'The before build did not reproduce the text replay'
else:
    assert result['failures'] == [], ('Restored or completed text replayed', result)
    ui.open_case('session-preview-stream-restore')
    reopened = phase('restore')
    assert reopened['failures'] == [], ('Reopening replayed existing text', reopened)
    ui.capture('reopened-running-reply')
print(json.dumps(result), flush=True)
