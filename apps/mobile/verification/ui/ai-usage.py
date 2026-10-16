"""Usage source semantics, unavailable cost, retained cache and late-range fencing."""
import json,sys,re
from driver import UI
import catalog
ui=UI(sys.argv[1],sys.argv[2])
def spoken(item):return str(item.get('AXLabel',''))+' '+str(item.get('AXValue',''))
def tap(identifier):ui.element(identifier);ui.axe('tap','--id',identifier,'--post-delay','.4')
def period(key):ui.axe('tap','--label',catalog.text('settings.aiUsage.'+key),'--post-delay','.2')
def metric(identifier,text):
    pattern=re.compile(r'(?<![0-9.,])'+re.escape(text)+r'(?![0-9.,])')
    ui.wait(lambda items:any(item.get('AXUniqueId')==identifier and pattern.search(spoken(item)) for item in items),'Usage metric missing: '+text)
ui.element('retry');ui.capture('usage-unavailable');tap('retry')
metric('usage-tokens','12,500');metric('usage-cost',catalog.text('settings.aiUsage.unavailable'))
ui.capture('usage-unknown-cost')
ui.axe('tap','--label',catalog.text('settings.remote.refresh'),'--post-delay','.3')
ui.element('retry');metric('usage-tokens','12,500');ui.capture('usage-cached-offline');tap('retry')
period('week');ui.element('usage-week-pending');period('month')
ui.element('usage-late-settled');metric('usage-tokens','400,000');metric('usage-cost','$1.25')
ui.capture('usage-current-range')
period('total');metric('usage-tokens','0');metric('usage-cost','$0.00');ui.capture('usage-real-zero')
print(json.dumps({'unknownNotZero':True,'timelineTotals':True,'cachedOffline':True,'lateRangeIgnored':True,'trueZero':True}))
