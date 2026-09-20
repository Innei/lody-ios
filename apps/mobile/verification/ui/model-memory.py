"""Production shared native form: per-model/agent memory and composer parity."""
import sys
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])

def tap(value):
    print('tap ' + value, flush=True)
    if value in ['model', 'agent']:
        reveal_options()
    ui.element(value)
    ui.axe('tap', '--id', value, '--post-delay', '.5')

def back():
    item = ui.wait(lambda items: max((i for i in items if i.get('type') == 'Button' and i.get('AXLabel') in ['Back', 'New conversation', 'Model and options']), key=lambda i: i['frame']['y'], default=None), 'Back button missing')
    f = item['frame']
    ui.axe('tap', '-x', str(f['x'] + f['width']/2), '-y', str(f['y'] + f['height']/2), '--post-delay', '.5')
    reveal_options()

def option(key, value):
    tap('option-' + key)
    tap(value or 'default-choice')

def summary(value):
    ui.wait(lambda items: any(value.casefold() in (i.get('AXLabel') or '').casefold() for i in items), 'Missing remembered summary: ' + value)

def model(value):
    tap('model'); option('modelId', value); back()

def agent(value):
    tap('agent'); tap('ui:' + value)

def reveal_options():
    f = ui.element('create-form')['frame']
    model = next((i for i in ui.state() if i.get('AXUniqueId') == 'model'), None)
    if model and model['frame']['y'] + model['frame']['height'] <= f['y'] + f['height']:
        return
    ui.axe('swipe', '--start-x', str(f['x'] + f['width']/2), '--start-y', str(f['y'] + f['height'] - 20),
           '--end-x', str(f['x'] + f['width']/2), '--end-y', str(f['y'] + 20), '--duration', '.4', '--post-delay', '.5')

def composer_model(value):
    tap('create-session-input'); tap('session-model'); tap('composer-model-menu')
    ui.axe('tap', '--label', value, '--element-type', 'Button', '--post-delay', '.8')
    summary('high')
    ui.capture('native-restored-' + value.replace(' ', '-'))
    ui.axe('tap', '-x', '20', '-y', '160', '--post-delay', '.5')
    reveal_options()

tap('model')
option('modelId', 'a'); option('effort', 'high'); option('modeId', 'read-only')
option('modelId', 'b'); back()
summary('Model B · Full Access')
ui.capture('new-model-full-access')
tap('model'); option('effort', 'low'); back()
summary('Model B · low · Full Access')
composer_model('Model A')
summary('Model A · high · Read Only')
model('b'); summary('Model B · low · Full Access')
ui.capture('restored-b')

tap('model'); option('fast-mode', 'true'); option('collaboration_mode', 'plan'); back()
summary('On'); ui.capture('codex-extra-options')
tap('model'); option('fast-mode', 'false'); back()
summary('Off')
model('a'); summary('Model A · high · Read Only')
model('b'); summary('Off')
tap('model'); option('fast-mode', ''); option('collaboration_mode', ''); back()
summary('Model B · low · Full Access')

agent('grok')
tap('model'); option('modelId', 'grok-a'); option('effort', 'high')
option('modeId', 'plan'); option('permission_mode', 'always-approve')
ui.capture('grok-permission')
option('modelId', 'grok-b'); option('permission_mode', 'auto'); back()
summary('Grok B'); summary('auto')
composer_model('Grok A')
summary('Grok A · high · Plan'); summary('always-approve')
ui.capture('grok-native-restored')

agent('claude')
tap('model'); option('effort', 'high'); option('fast', 'true'); back()
ui.capture('claude-extra-options')
tap('create-session-input'); tap('session-model'); summary('high')
ui.capture('claude-native-effort')
ui.axe('tap', '-x', '20', '-y', '160', '--post-delay', '.5')
reveal_options()
agent('deepseek'); tap('model'); option('agent_preset', 'coder'); back()
summary('coder'); ui.capture('agent-preset')
agent('grok'); model('grok-a'); summary('Grok A · high · Plan'); summary('always-approve')
ui.axe('tap', '--label', 'Cancel', '--post-delay', '.5')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'create-session-input' for i in items), 'Native Cancel did not settle the presentation')
ui.capture('cancelled')
print('PASS: native form, per-model/agent memory, false/default options, config-only effort, composer parity')
