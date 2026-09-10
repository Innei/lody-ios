"""Typing autocompletes in place; explicit categories open a full-screen searchable picker."""
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
field = 'create-session-input' if 'mention-sheet' in str(ui.output) else 'session-input'
keyboard_ready = False

def search_field():
    return ui.wait(lambda items: next((i for i in items if i.get('subrole') == 'AXSearchField'), None), 'Navigation search missing')

def tap(identifier):
    if identifier == 'mention-search':
        frame = search_field()['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.4')
        return
    ui.element(identifier)
    ui.axe('tap', '--id', identifier, '--post-delay', '.4')

def value():
    return ui.element(field).get('AXValue', '')

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
assert value() == '@auth-review ', 'Autocomplete did not replace current query'
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
ui.wait(lambda _: value() == '@auth-review @src/auth ', 'Directory was not inserted at the saved caret')
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
ui.wait(lambda _: value() == '@auth-review @src/auth @swiftui-pro ', 'Selected skill did not return to the original draft')
keyboard_clear()

open_category('file')
tap('mention-search')
type_keys('session')
ui.element('mention-picker-item:src/auth/session.ts')
ui.capture('file-search')
tap('mention-picker-item:src/auth/session.ts')
ui.wait(lambda _: value() == '@auth-review @src/auth @swiftui-pro @src/auth/session.ts ', 'File selection lost an earlier reference')
keyboard_clear()
ui.capture('references-inserted')

open_category('skill')
tap('mention-search')
type_keys('zzzz')
ui.element('mention-picker-empty')
ui.capture('empty-search')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('native.chat.mention.open')), '--post-delay', '.6')
ui.wait(lambda _: value() == '@auth-review @src/auth @swiftui-pro @src/auth/session.ts @', 'Cancelling the sheet changed the original draft')
keyboard_clear()
ui.capture('cancelled')
print('PASS: compact touch autocomplete, full-screen category browsing/search, directory reference, file/skill insertion and cancellation restore the draft and keyboard')
