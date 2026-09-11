"""Typing autocompletes in place; explicit categories open a full-screen searchable picker."""
import sys
import subprocess
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
field = 'create-session-input' if 'mention-sheet' in str(ui.output) else 'session-input'
keyboard_ready = False

def search_field():
    return ui.wait(lambda items: next((i for i in items if i.get('subrole') == 'AXSearchField'), None), 'Navigation search missing')

def tap(identifier):
    if identifier.startswith('mention-item:'):
        for _ in range(4):
            items = ui.state()
            panel = next(i['frame'] for i in items if i.get('AXUniqueId') == 'mention-panel')
            target = next((i['frame'] for i in items if i.get('AXUniqueId') == identifier), None)
            if target and target['y'] >= panel['y'] and target['y'] + target['height'] <= panel['y'] + panel['height']:
                break
            rows = [i['frame'] for i in items if (i.get('AXUniqueId') or '').startswith('mention-item:') and i.get('frame')]
            assert rows, 'Reference category panel missing'
            top = panel['y']
            bottom = panel['y'] + panel['height']
            x = rows[0]['x'] + rows[0]['width'] / 2
            ui.axe('swipe', '--start-x', str(x), '--start-y', str(bottom - 12), '--end-x', str(x), '--end-y', str(top + 12), '--duration', '.4', '--post-delay', '.3')
    if identifier == 'mention-search':
        frame = search_field()['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.4')
        return
    ui.element(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.8')

def value():
    return ui.element(field).get('AXValue') or ''

def keyboard_clear():
    def visible_keyboard(items):
        screen_height = items[0]['frame']['height']
        return next((i['frame']['y'] for i in items if (i.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar') and i['frame']['y'] < screen_height - 150), None)
    top = ui.wait(visible_keyboard, 'Software keyboard disappeared while choosing references')
    send = ui.element('session-send')['frame']
    assert send['y'] + send['height'] <= top + 1, 'Composer overlaps the keyboard'

def type_keys(text):
    global keyboard_ready
    # Pick English explicitly: the globe value names the NEXT keyboard, not the current one.
    globe = next((i for i in ui.state() if i.get('AXLabel') == catalog.system('nextKeyboard')), None)
    if globe and not keyboard_ready:
        frame = globe['frame']
        ui.axe('touch', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--down', '--up', '--delay', '1')
        key = ui.wait(lambda items: next((i for i in items if i.get('AXLabel') in ['English (US)', '英语（美国）', '英语(美国)']), None), 'English keyboard menu missing')
        frame = key['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.3')
        # A newly leased Simulator may show the QuickPath introduction after switching keyboards.
        intro = next((i for i in ui.state() if i.get('AXLabel') in ['Continue', '继续'] and i.get('type') == 'Button'), None)
        if intro:
            ui.axe('tap', '--label', intro['AXLabel'], '--post-delay', '.4')
        keyboard_ready = True
    # Physical software-keyboard taps keep this a touch interaction, not hardware typing.
    for char in text:
        key = ui.wait(lambda items: next((i for i in items if (i.get('AXLabel') or '').lower() == char and i.get('type') == 'Button'), None), 'Missing keyboard key ' + char)
        frame = key['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical')

def open_category(kind):
    tap('session-mention')
    tap('mention-item:' + kind)
    search = search_field()['frame']
    screen = ui.state()[0]['frame']
    assert search['y'] > screen['height'] * .7, 'Navigation search must appear at the bottom of the iPhone sheet'
    row_id = 'src' if kind == 'file' else 'skills/swiftui-pro/SKILL.md'
    row = ui.element('mention-picker-item:' + row_id)['frame']
    assert row['x'] >= 16 and row['x'] + row['width'] <= ui.state()[0]['frame']['width'] - 16, 'Picker rows must use inset grouped margins'

ui.capture('resting')
tap(field)
resting_send = ui.element('session-send')['frame']
tap('session-mention')
category = ui.element('mention-item:file')
ui.element('mention-item:skill')
assert not any('native.chat.mention.' in str(i.get('AXLabel') or '') for i in ui.state()), 'Reference categories expose untranslated keys'
assert 44 <= category['frame']['height'] <= 52, 'Category entry must remain one compact tappable row'
assert abs(ui.element('session-send')['frame']['y'] - resting_send['y']) <= 1, 'Opening references moved the composer'
assert value() == '@', 'At button did not insert trigger'
keyboard_clear()
ui.capture('categories')
type_keys('auth')
ui.element('mention-item:src/auth')
ui.element('mention-item:skills/auth-review/SKILL.md')
keyboard_clear()
assert not any(i.get('subrole') == 'AXSearchField' for i in ui.state()), 'Typing opened a sheet instead of autocomplete'
ui.capture('autocomplete')
tap('mention-item:skills/auth-review/SKILL.md')
assert value() == '$auth-review ', 'Autocomplete did not replace current query'
keyboard_clear()
ui.capture('autocomplete-inserted')

open_category('file')
ui.element('mention-picker-item:src')
ui.capture('files-sheet')
tap('mention-picker-item:src')
ui.element('mention-picker-item:src/auth')
ui.capture('directory')
tap('mention-picker-item:src/auth')
ui.element('mention-picker-item:src/auth/session.ts')
ui.capture('nested-directory')
tap('mention-picker-use-directory')
ui.wait(lambda _: value() == '$auth-review @src/auth ', 'Directory was not inserted at the saved caret')
keyboard_clear()
ui.capture('directory-inserted')

open_category('skill')
ui.element('mention-picker-item:skills/swiftui-pro/SKILL.md')
ui.capture('skills-sheet')
tap('mention-search')
type_keys('swift')
ui.element('mention-picker-item:skills/swiftui-pro/SKILL.md')
ui.capture('skill-search')
tap('mention-picker-item:skills/swiftui-pro/SKILL.md')
ui.wait(lambda _: value() == '$auth-review @src/auth $swiftui-pro ', 'Selected skill did not return to the original draft')
keyboard_clear()

open_category('file')
tap('mention-search')
type_keys('session')
ui.element('mention-picker-item:src/auth/session.ts')
ui.capture('file-search')
tap('mention-picker-item:src/auth/session.ts')
ui.wait(lambda _: value() == '$auth-review @src/auth $swiftui-pro @src/auth/session.ts ', 'File selection lost an earlier reference')
keyboard_clear()
ui.capture('references-inserted')

open_category('skill')
tap('mention-search')
type_keys('zzzz')
ui.element('mention-picker-empty')
ui.capture('empty-search')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('native.chat.mention.open')), '--post-delay', '.6')
ui.wait(lambda _: value() == '$auth-review @src/auth $swiftui-pro @src/auth/session.ts @', 'Cancelling the sheet changed the original draft')
keyboard_clear()
ui.capture('cancelled')
print('PASS: compact touch autocomplete, full-screen category browsing/search, directory reference, file/skill insertion and cancellation restore the draft and keyboard')

for kind, path, token in [
    ('session', 'session-review', '@session:session-review'),
    ('role', 'role-reviewer', '@role:role-reviewer'),
    ('issue', 'issue:11', '#11'),
    ('pr', 'pr:12', '#12'),
    ('cmd', 'compact', '/compact'),
]:
    tap('session-mention')
    tap('mention-item:' + kind)
    ui.element('mention-picker-item:' + path)
    ui.capture(kind + '-sheet')
    tap('mention-picker-item:' + path)
    assert token in value(), 'Selected reference missing: ' + token
ui.capture('all-references')
tap('session-send')
ui.wait(lambda items: any('use lody mcp to query session[id: session-review] history' in str(i.get('AXLabel', '')) for i in items), 'Session reference did not expand in the sent transcript')
ui.wait(lambda items: any('$auth-review' in (i.get('custom_actions') or []) for i in items), 'Sent skill did not render as an actionable reference')
ui.wait(lambda items: any('agent role[id: role-reviewer, name: Reviewer]' in str(i.get('AXLabel', '')) for i in items), 'Role reference did not expand in the sent transcript')
ui.capture('expanded-transcript')
print('PASS: all seven references, actionable skill display and send-time session/Role expansion in the native transcript')

field = 'session-input'
tap(field)
ui.axe('type', '/')
ui.element('mention-item:compact')
assert not any(i.get('AXUniqueId') == 'mention-item:file' for i in ui.state()), 'Slash opened the category index'
ui.capture('slash-direct')
ui.axe('key', '42')
assert value() == '', 'Cancelling slash left inserted command text'
ui.axe('type', '$')
ui.element('mention-item:skills/auth-review/SKILL.md')
assert not any(i.get('AXUniqueId') == 'mention-item:file' for i in ui.state()), 'Dollar opened the category index'
ui.capture('skill-direct')
ui.axe('key', '42')
assert value() == '', 'Cancelling skill completion changed the draft'

# AXe hardware typing changes the per-device keyboard mode; restore the runner's
# software keyboard before the next appearance reuses this process.
subprocess.run([str(ui.output.parents[1] / 'software-keyboard'), subprocess.check_output(['xcode-select', '-p'], text=True).strip(), ui.udid], check=True, timeout=30)
tap(field)
keyboard_clear()
