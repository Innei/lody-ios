"""Permission sheet opens ahead of its target and never costs the composer draft."""
import sys
import json
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
close = catalog.text('accessibility.closeSheet', title=catalog.text('permission.title'))
DRAFT = '12345'


def control(action):
    ui.axe('tap', '--label', 'Request controls')
    ui.wait(lambda items: any(i.get('AXLabel') == action for i in items), action)
    ui.axe('tap', '--label', action)


def target(available):
    control('Resolve target' if available else 'Remote answer')


def open_sheet():
    ui.axe('tap', '--label', 'Fixtures')
    ui.axe('tap', '--label', 'Requests')
    ui.wait(lambda items: any(i.get('AXLabel') == 'Permission Fixture' for i in items), 'Requests submenu never opened')
    ui.axe('tap', '--label', 'Permission Fixture', '--post-delay', '1')
    ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('permission.waiting') for i in items),
            'Sheet must open before its target resolves')
    ui.capture('waiting')
    target(True)
    ui.wait(lambda items: any(i.get('AXLabel') == 'Allow once' for i in items),
            'Permission options never arrived')


def type_draft():
    ui.axe('tap', '--id', 'session-input', '--post-delay', '1')
    ui.axe('type', DRAFT)
    ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
            'Draft was not typed', timeout=10)


type_draft()
open_sheet()
assert any(i.get('AXLabel') == close for i in ui.state()), 'Non-dismissible sheet needs a close button'
assert any(i.get('AXLabel') == 'Custom choice' for i in ui.state()), 'Option without kind must remain actionable'
ui.capture('pending')
ui.axe('tap', '--label', close, '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Closing the sheet lost the composer draft')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'permission-result' and 'cancelled' in (i.get('AXValue') or '') for i in items), 'Close did not cancel the RN presentation')
ui.capture('closed')

open_sheet()
ui.axe('tap', '--label', 'Allow once', '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Answering the request lost the composer draft')
assert not any(i.get('AXLabel') == 'Allow once' for i in ui.state()), 'Sheet stayed up after answering'
ui.wait(lambda items: any(i.get('AXUniqueId') == 'permission-result' and 'request-1' in (i.get('AXValue') or '') for i in items), 'Native answer did not settle the RN presentation')
ui.capture('answered')

open_sheet()
target(False)
ui.wait(lambda items: not any(i.get('AXLabel') == 'Allow once' for i in items),
        'Sheet stayed up after the request was answered elsewhere', timeout=15)
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Remote answer lost the composer draft')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'permission-result' and 'completed' in (i.get('AXValue') or '') for i in items), 'Remote answer did not settle the RN presentation')
ui.capture('answered-elsewhere')
print('PASS: sheet opens before its target, keeps the draft through close, answer and remote answer')


def question_probe():
    return ui.element('permission-sheet-probe').get('AXValue') or ''


def open_questions():
    ui.axe('tap', '--label', 'Fixtures')
    ui.axe('tap', '--label', 'Requests')
    ui.wait(lambda items: any(i.get('AXLabel') == 'Question Fixture' for i in items), 'Requests submenu never opened')
    ui.axe('tap', '--label', 'Question Fixture', '--post-delay', '1')
    ui.wait(lambda items: any(i.get('AXUniqueId') == 'question-option-0' for i in items), 'Question card missing')


open_questions()
ui.capture('question-single')
ui.axe('drag', '--start-x', '200', '--start-y', '400', '--end-x', '200', '--end-y', '60', '--duration', '.5', '--post-delay', '1')
screen = next(i['frame']['height'] for i in ui.state() if i.get('type') == 'Application')
button = ui.element('question-next')['frame']
assert button['y'] + button['height'] <= screen - 30, f'Full-height sheet must keep the action above the home indicator: {button}'
ui.capture('question-full')
ui.axe('tap', '--id', 'question-option-0')
ui.axe('tap', '--id', 'question-next')
ui.wait(lambda items: any(i.get('AXLabel') == 'Which checks should run?' for i in items), 'Next must reach the multi-select question')
ui.axe('tap', '--id', 'question-option-0')
ui.axe('tap', '--id', 'question-option-1')
ui.capture('question-multiple')
assert 'submit:' not in question_probe(), 'Choosing options must never submit automatically'
assert ui.element('list-step-0').get('AXValue') == catalog.text('native.list.answered'), 'Answered step must say so'
assert not ui.element('list-step-2').get('AXValue'), 'Unanswered step must not claim an answer'
ui.axe('tap', '--id', 'list-step-0')
ui.wait(lambda items: any(i.get('AXLabel') == 'Which language should we use?' for i in items), 'Previous answer page missing')
ui.axe('tap', '--id', 'question-next')
ui.axe('tap', '--id', 'question-next')
ui.wait(lambda items: any(i.get('AXLabel') == 'Anything else we should know?' for i in items), 'Next must reach the free-text question')
assert not any(i.get('AXUniqueId') == 'question-next' for i in ui.state()), 'Last question must offer Submit, not Next'
ui.axe('tap', '--id', 'question-custom', '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('common.done') for i in items), 'Custom answer prompt missing')
ui.axe('type', 'Keep it native')
note = ui.wait(lambda items: next((i.get('AXValue') for i in items if i.get('type') == 'TextField' and i.get('AXValue')), None), 'Missing typed answer')
ui.capture('question-prompt')
ui.axe('tap', '--label', catalog.text('common.done'), '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'question-custom' and note in (i.get('AXLabel') or '') for i in items),
        'Custom answer must show on its row')
ui.capture('question-text')
control('Suspend')
assert not ui.element('question-submit').get('enabled', True), 'Suspended request remained actionable'
ui.capture('question-suspended')
control('Resume')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'question-custom' and note in (i.get('AXLabel') or '') for i in items), 'Resume lost question answers')
ui.axe('tap', '--id', 'question-submit', '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('permission.error.send') for i in items), 'Upload failure must retain the card')
probe = question_probe()
observed_answers, _ = json.JSONDecoder().raw_decode(probe[probe.index('{'):])
assert observed_answers == {
    'language': 'Swift', 'checks': ['Unit tests', 'UI tests'], 'notes': note,
}, 'The production card did not submit the full answer set'
print('Observed answer payload: ' + json.dumps(observed_answers), flush=True)
assert 'submit:request-1:1' in question_probe()
ui.capture('question-retry')
ui.axe('tap', '--id', 'question-submit', '--post-delay', '1')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'question-submit' for i in items), 'Successful retry did not close the card')
ui.capture('question-answered')
open_questions()
control('Remote answer')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'permission-sheet-probe' for i in items), 'Desktop answer did not close the question card')
ui.capture('question-answered-elsewhere')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items), 'Question resolution lost the composer draft')
print('PASS: multi-question answers, navigation, failed upload, retry and desktop resolution')
