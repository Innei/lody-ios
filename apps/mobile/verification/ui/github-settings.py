"""Independent expired identity and repository state, failure, refresh and readback."""
import json,sys
from driver import UI
import catalog
ui=UI(sys.argv[1],sys.argv[2])
def spoken(item):return str(item.get('AXLabel',''))+' '+str(item.get('AXValue',''))
def tap(identifier):ui.element(identifier);ui.axe('tap','--id',identifier,'--post-delay','.4')
ui.element('retry');ui.capture('github-unverified');tap('retry')
assert catalog.text('settings.github.expired') in spoken(ui.element('identity'))
repo='repo:LodyAI/Lody'
assert catalog.text('settings.remote.enabled') in spoken(ui.element(repo))
ui.capture('github-scopes')
tap(repo);ui.axe('tap','--label',catalog.text('settings.remote.disabled'),'--post-delay','.5')
ui.element('retry');assert catalog.text('settings.github.unknown') in spoken(ui.element('identity'))
ui.capture('github-write-unconfirmed');tap('retry')
assert catalog.text('settings.remote.enabled') in spoken(ui.element(repo))
tap(repo);ui.axe('tap','--label',catalog.text('settings.remote.disabled'),'--post-delay','.5')
ui.wait(lambda items:any(item.get('AXUniqueId')==repo and catalog.text('settings.remote.disabled') in spoken(item) for item in items),'Repository enable state not read back')
assert catalog.text('settings.github.expired') in spoken(ui.element('identity'))
ui.capture('github-repository-disabled')
print(json.dumps({'identitySeparateFromRepositories':True,'failureNotConnected':True,'repoReadback':True,'noRealAuthorization':True}))
