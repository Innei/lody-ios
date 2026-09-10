"""Actual product screens expose @ and preserve the selected machine reference."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])

def tap(identifier):
    ui.element(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.5')

def choose(field, host):
    tap(field)
    tap('session-mention')
    tap('mention-item:file')
    tap('mention-picker-item:src')
    ui.capture(host + '-files')
    tap('mention-picker-item:src/session.ts')
    assert '@src/session.ts' in ui.element(field).get('AXValue', ''), 'Selected file did not reach the real composer'
    tap('session-mention')
    tap('mention-item:skill')
    ui.capture(host + '-skills')
    tap('mention-picker-item:/fixture/skills/auth/SKILL.md')
    text = ui.element(field).get('AXValue', '')
    assert text.strip() == '@src/session.ts use /auth-review [Skill Path](</fixture/skills/auth/SKILL.md>)', 'The real composer lost the machine skill path or prior draft'
    ui.capture(host + '-draft')

# Start from the real inbox, not a manually wired composer preview.
tap('ui-design')
choose('session-input', 'chat')
ui.axe('tap', '--label', 'Back' if catalog.LANGUAGE == 'en' else '返回', '--post-delay', '1')
ui.element('ui-design')
buttons = [i for i in ui.state() if i.get('type') == 'Button' and i.get('frame')]
frame = max(buttons, key=lambda i: i['frame']['y'])['frame']
ui.axe('tap', '-x', str(frame['x'] + frame['width']/2), '-y', str(frame['y'] + frame['height']/2), '--post-delay', '1')
choose('create-session-input', 'sheet')
print('PASS: production chat and new-session screens browse real-provider-shaped files/skills and retain complete references')
