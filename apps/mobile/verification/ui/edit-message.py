"""Last-turn context menu, full-screen composer, attachment edits and failed-send retention."""
import json
import sys
from driver import UI
import catalog

ui = UI(*sys.argv[1:])

def hold(identifier):
    frame = ui.element(identifier)['frame']
    ui.axe('touch', '-x', str(frame['x'] + frame['width'] - 35), '-y', str(frame['y'] + frame['height'] / 2), '--down', '--up', '--delay', '.8')
    ui.wait(lambda items: any((item.get('AXLabel') or '').casefold() == catalog.system('copy').casefold() for item in items), 'Message menu did not open')

def open_editor():
    hold('editable:user')
    ui.axe('tap', '--label', catalog.text('native.chat.editAction'), '--post-delay', '.8')
    ui.element('edit-message-input')
    screen_height = ui.state()[0]['frame']['height']
    keyboard = ui.wait(lambda items: next((item['frame'] for item in items if (item.get('AXUniqueId') or '').startswith('UIKeyboardLayoutStar') and item['frame']['y'] < screen_height - 150), None), 'Editor did not focus the keyboard')
    button = ui.element('session-send')
    assert button['enabled'], 'Editor send button is disabled for a valid original message'
    send = button['frame']
    assert send['y'] + send['height'] <= keyboard['y'] + 1, 'Keyboard covers the editor send button'

ui.axe('swipe', '--start-x', '190', '--start-y', '250', '--end-x', '190', '--end-y', '570', '--duration', '.5', '--post-delay', '.7')
hold('earlier:user')
assert not any(item.get('AXLabel') == catalog.text('native.chat.editAction') for item in ui.state())
ui.capture('earlier-menu')
ui.axe('tap', '-x', '20', '-y', '600', '--post-delay', '.8')
ui.wait(lambda items: not any((item.get('AXLabel') or '').casefold() == catalog.system('copy').casefold() for item in items), 'Message menu did not dismiss')
open_editor()
original = 'Original prompt'
assert ui.element('edit-message-input')['AXValue'] == original
assert not any(item.get('AXUniqueId') == 'old-reply:text' for item in ui.state())
ui.capture('editor')
ui.axe('tap', '--label', catalog.text('common.cancel'), '--post-delay', '.6')
assert ui.element('session-input')['AXValue'] == 'Keep this chat draft'
ui.element('old-reply:text')
ui.capture('cancelled')
open_editor()
ui.axe('tap', '--label', catalog.text('native.chat.attachment.remove', name='original.txt'))
assert not any(item.get('AXLabel') == catalog.text('native.chat.attachment.remove', name='original.txt') for item in ui.state())
ui.paste_file('edit-message-input')
ui.axe('tap', '--id', 'edit-message-input')
input_log = ui.output / 'text-input.jsonl'
input_offset = input_log.stat().st_size if input_log.exists() else 0
ui.axe('type', ' revised')
with input_log.open(encoding='utf-8') as log:
    log.seek(input_offset)
    records = [json.loads(line) for line in log if line.strip()]
assert len(records) == 1, 'Editing must record exactly one suffix Paste'
record = records[0]
assert record.get('event') == 'system-paste' and record.get('status') == 'performed'
assert record.get('text') == ' revised'
before = record['before']
assert before.get('id') == 'edit-message-input' and before.get('firstResponder') is True
assert before.get('text') == original, 'Attachment editing changed the original text before Paste'
start, end = before['selection']['start'], before['selection']['end']
assert type(start) is int and type(end) is int and 0 <= start <= end <= len(original), 'Invalid pre-Paste UTF-16 selection'
# The independently known ASCII fixture uses the same character and UTF-16 offsets.
expected = original[:start] + ' revised' + original[end:]
assert ui.element('edit-message-input')['AXValue'] == expected, 'Paste did not commit the complete edit at the observed selection'
ui.capture('attachments-edited')
ui.axe('tap', '--id', 'session-send', '--post-delay', '.2')
ui.element('edit-message-busy')
ui.capture('sending')
ui.element('edit-message-error')
assert ui.element('edit-message-input')['AXValue'] == expected
ui.capture('failed-kept')
ui.axe('tap', '--id', 'session-send', '--post-delay', '2')
ui.element('session-input')
assert ui.element('session-input')['AXValue'] == 'Keep this chat draft'
payload = json.loads(ui.element('edit-fixture-payload')['AXLabel'])
assert payload['expectedUserTurnId'] == 'editable'
assert payload['retainedIds'] == ['original:1']
assert len(payload['attachments']) == 1
assert payload['text'] == expected
assert ui.element('edit-fixture-count')['AXLabel'] == '2'
assert not any(item.get('AXUniqueId') == 'old-reply:text' for item in ui.state())
ui.capture('replaced')
print('PASS: last-message menu, full-screen editing, cancellation, attachment add/remove, failure retention and replacement')
