"""Remote settings use production forms, with resettable failure outcomes at the service boundary."""
import json
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])

def spoken(item):
    return ' '.join([str(item.get(key) or '') for key in ('AXLabel', 'AXValue')] + [spoken(child) for child in item.get('children') or []])

def label(identifier):
    return spoken(ui.element(identifier))

def tap(identifier):
    ui.element(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.5')

def toolbar(key):
    return ui.wait(lambda items: next((item for item in items if item.get('AXLabel') == catalog.text(key) and item.get('type') == 'Button'), None), f'Missing toolbar action {key}')

def save():
    # Saving is a native toolbar action, reachable while the keyboard is open.
    frame = toolbar('settings.remote.save')['frame']
    assert abs(frame['y'] - toolbar('common.cancel')['frame']['y']) < 10, 'Save must stay beside Cancel in the navigation bar'
    ui.axe('tap', '--label', catalog.text('settings.remote.save'), '--post-delay', '.5')

ui.capture('categories')
ui.axe('tap', '--id', 'settings-machine', '--pre-delay', '.8', '--post-delay', '.8', '--tap-style', 'physical')
ui.wait(lambda items: any(catalog.text('settings.remote.loadFailed') in (item.get('AXLabel') or '') for item in items), 'Missing load failure')
ui.capture('load-failure')
tap('retry')
assert 'Studio Mac' in label('setting:machine::m1')
ui.capture('machines')
tap('setting:machine::m1')
assert toolbar('common.cancel')['frame']['x'] < toolbar('settings.remote.save')['frame']['x']
ui.capture('machine-editor')
tap('setting-name')
ui.axe('type', ' mobile')
machine_name = ui.element('setting-name')['AXValue']
assert 'mobile' in machine_name
save()
ui.wait(lambda items: any(item.get('AXUniqueId') == 'setting:machine::m1' and machine_name in (item.get('AXLabel') or '') for item in items), 'Machine rename did not reach list')
ui.capture('machine-saved')

ui.axe('swipe', '--start-x', '2', '--start-y', '400', '--end-x', '370', '--end-y', '400', '--duration', '.5', '--post-delay', '.6')
tap('settings-agent')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'setting:agent:m1:a1' and 'Codex' in (item.get('AXLabel') or '') for item in items), 'Agent section did not open')
assert catalog.text('settings.usage.used', percent=32) in label('usage:m1:a1:codex:0')
assert catalog.text('settings.usage.used', percent=61) in label('usage:m1:a1:codex:1')
assert 'Spark' in label('usage:m1:a1:codex_bengalfox:0')
assert catalog.text('settings.usage.resetUnknown') in label('usage:m1:a1:codex_bengalfox:0')
ui.capture('agent-usage')
# A failed fetch on reconnect uses the persisted catalog-shaped projection.
ui.axe('swipe', '--start-x', '180', '--start-y', '250', '--end-x', '180', '--end-y', '640', '--duration', '.6', '--post-delay', '1')
ui.wait(lambda items: any(catalog.text('settings.usage.offline') in (item.get('AXLabel') or '') for item in items), 'Missing offline usage state')
assert catalog.text('settings.usage.used', percent=32) in label('usage:m1:a1:codex:0')
ui.capture('agent-usage-offline')
ui.axe('swipe', '--start-x', '180', '--start-y', '250', '--end-x', '180', '--end-y', '640', '--duration', '.6', '--post-delay', '1')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'usage:m1:a1:codex:0' and catalog.text('settings.usage.used', percent=72) in spoken(item) for item in items), 'Usage did not update after reconnect')
ui.capture('agent-usage-updated')
ui.axe('swipe', '--start-x', '180', '--start-y', '720', '--end-x', '180', '--end-y', '250', '--duration', '.6', '--post-delay', '.5')
assert catalog.text('settings.usage.used', percent=100) in label('usage:m1:a2:claude:0')
assert catalog.text('settings.remote.readOnly') in label('setting:agent:m1:a2')
assert catalog.text('settings.usage.empty') in label('usage:m1:a3:empty')
ui.element('setting:agent:m1:a4')
assert not any((item.get('AXUniqueId') or '').startswith('usage:m1:a4:') for item in ui.state()), 'Custom API incorrectly displays subscription quota'
ui.capture('agent-usage-readonly-empty-api')
ui.axe('swipe', '--start-x', '180', '--start-y', '300', '--end-x', '180', '--end-y', '730', '--duration', '.6', '--post-delay', '.5')
tap('setting:agent:m1:a1')
ui.capture('agent-editor')
tap('setting-prompt')
ui.axe('type', ' mobile instructions.')
prompt = ui.element('setting-prompt')['AXValue']
assert 'mobile instructions.' in prompt
save()
assert catalog.text('settings.remote.saveFailed') in label('lody.toast')
ui.capture('save-failure-toast')
assert ui.element('setting-prompt')['AXValue'] == prompt
save()
ui.element('setting:agent:m1:a1')
tap('setting:agent:m1:a1')
assert ui.element('setting-prompt')['AXValue'] == prompt
ui.capture('agent-reopened')
ui.axe('tap', '--label', catalog.text('common.cancel'), '--post-delay', '.5')

ui.axe('swipe', '--start-x', '2', '--start-y', '400', '--end-x', '370', '--end-y', '400', '--duration', '.5', '--post-delay', '.6')
tap('settings-mcp')
ui.wait(lambda items: any(item.get('AXUniqueId') == 'setting:mcp::c1' and 'Documentation' in (item.get('AXLabel') or '') for item in items), 'MCP section did not open')
assert catalog.text('settings.remote.disabled') in label('setting:mcp::c1')
tap('setting:mcp::c1')
ui.capture('mcp-editor')
tap('setting-enabled')
save()
ui.wait(lambda items: any(item.get('AXUniqueId') == 'setting:mcp::c1' and catalog.text('settings.remote.enabled') in spoken(item) for item in items), 'MCP default did not persist')
ui.capture('mcp-saved')
tap('setting:mcp::c1')
assert ui.element('setting-enabled').get('AXValue') == '1'
ui.capture('mcp-reopened')
print(json.dumps({'machineName': machine_name, 'agentPrompt': prompt, 'mcpEnabledByDefault': True, 'failuresRetainedDraft': True}))
