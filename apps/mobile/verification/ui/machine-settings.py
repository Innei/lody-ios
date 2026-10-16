"""Machine identity, liveness, cache recovery and owner-only rename on production UI."""
import json
import sys
from driver import UI
from sheet_background import capture_card
import catalog

ui = UI(sys.argv[1], sys.argv[2])
owner = 'setting:machine::7a341b7c-6be8-4a33-9a1a-220ce48c5098'
teammate = 'setting:machine::8b452c8d-7cf9-4b44-8b2b-331df59d6109'


def spoken(item):
    return ' '.join(str(item.get(key) or '') for key in ('AXLabel', 'AXValue'))


def tap(identifier):
    ui.element(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.5')


def toolbar(key):
    ui.axe('tap', '--label', catalog.text(key), '--post-delay', '.5')


def has_text(key):
    return any(catalog.text(key) in spoken(item) for item in ui.state())


for identifier in (owner, teammate):
    row = ui.element(identifier)
    assert row['frame']['height'] >= 44
    assert identifier.split('::')[1] in spoken(row), 'Same-name machine identity missing'
    assert catalog.text('devices.unknown') in spoken(row), 'Failed refresh claimed live presence'
assert has_text('settings.remote.machineCached')
synced = catalog.text('settings.remote.syncedAt', time='').strip()
assert any(synced in spoken(item) for item in ui.state()), 'Missing cache refresh time'
ui.capture('machines-cached-failure')

tap('retry')
ui.wait(lambda items: any(item.get('AXUniqueId') == owner and catalog.text('devices.online') in spoken(item) for item in items), 'Owner presence did not recover')
assert catalog.text('devices.offline') in spoken(ui.element(teammate))
assert catalog.text('settings.remote.readOnly') in spoken(ui.element(teammate))
assert not has_text('settings.remote.machineCached')
ui.capture('machines-live')

tap(teammate)
assert not any(item.get('AXUniqueId') == 'setting-name' for item in ui.state()), 'Read-only machine opened an editor'
tap(owner)
assert ui.element('setting-name')['AXValue'] == 'Studio Mac'
capture_card(ui, 'machine-editor', 'setting-name')
tap('setting-name')
ui.axe('tap', '--label', catalog.system('clear'), '--post-delay', '.2')
ui.type_into('setting-name', 'Studio Renamed')
capture_card(ui, 'machine-editor-focused', 'setting-name')
toolbar('settings.remote.save')
ui.wait(lambda items: any(catalog.text('settings.remote.conflict') in spoken(item) for item in items), 'Missing rename conflict')
assert ui.element('setting-name')['AXValue'] == 'Studio Renamed', 'Conflict lost the draft'
ui.capture('machine-conflict-draft')
toolbar('common.cancel')
tap(owner)
assert ui.element('setting-name')['AXValue'] == 'Studio Mac', 'Conflict changed remote data'
tap('setting-name')
ui.axe('tap', '--label', catalog.system('clear'), '--post-delay', '.2')
ui.type_into('setting-name', 'Studio Renamed')
toolbar('settings.remote.save')
ui.wait(lambda items: any(item.get('AXUniqueId') == owner and 'Studio Renamed' in spoken(item) for item in items), 'Rename did not refresh the list')
assert 'Studio Mac' in spoken(ui.element(teammate)), 'Rename affected the other same-name machine'
ui.capture('machine-renamed')
tap(owner)
assert ui.element('setting-name')['AXValue'] == 'Studio Renamed'
toolbar('common.cancel')
ui.element(owner)
ui.capture('machine-returned')
print(json.dumps({'sameNameIdentity': True, 'presenceRecovered': True, 'readOnlyBlocked': True, 'conflictRetainedDraft': True, 'renamePersisted': True}))
