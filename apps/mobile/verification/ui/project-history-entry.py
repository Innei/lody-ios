"""The signed-in Settings sheet exposes project history and a recoverable disconnected state."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
ui.axe('tap', '--label', catalog.text('tabs.settings'), '--post-delay', '1')
row = ui.element('project-history')
assert catalog.text('settings.history.title') in row.get('AXLabel', '')
assert row['frame']['height'] >= 44
ui.capture('settings-entry')
ui.axe('tap', '--id', 'project-history', '--post-delay', '.5')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('settings.history.sync') for item in items), 'Missing navigation refresh')
ui.wait(lambda items: any(catalog.text('settings.history.loadFailed') in (item.get('AXLabel') or '') for item in items), 'Missing recoverable disconnected state')
ui.capture('disconnected')
ui.axe('tap', '--label', catalog.text('settings.history.sync'), '--tap-style', 'physical', '--post-delay', '.8')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('settings.history.sync') for item in items), 'Missing navigation refresh')
ui.capture('retry-available')
print('PASS: Settings exposes Agent Conversation Sync with native navigation and recoverable connection failure.')
