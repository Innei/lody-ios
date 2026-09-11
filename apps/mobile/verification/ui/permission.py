"""Permission sheet opens ahead of its target and never costs the composer draft."""
import sys
import os
import json
from driver import UI
from inspector import inspector
import catalog

ui = UI(sys.argv[1], sys.argv[2])
close = catalog.text('accessibility.closeSheet', title=catalog.text('permission.title'))
DRAFT = '12345'


def target(available):
    inspector(ui.udid, int(os.environ['LODY_UI_METRO_PORT']), 'Runtime.evaluate', {
        'expression': 'globalThis.__lodyUiVerifyPermissionTarget(' + str(available).lower() + ')',
    })


def open_sheet():
    ui.axe('tap', '--label', 'Fixtures')
    ui.axe('tap', '--label', 'Permission Fixture', '--post-delay', '0.5')
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
ui.capture('closed')

open_sheet()
ui.axe('tap', '--label', 'Allow once', '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Answering the request lost the composer draft')
assert not any(i.get('AXLabel') == 'Allow once' for i in ui.state()), 'Sheet stayed up after answering'
ui.capture('answered')

open_sheet()
target(False)
ui.wait(lambda items: not any(i.get('AXLabel') == 'Allow once' for i in items),
        'Sheet stayed up after the request was answered elsewhere', timeout=15)
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items),
        'Remote answer lost the composer draft')
ui.capture('answered-elsewhere')
print('PASS: sheet opens before its target, keeps the draft through close, answer and remote answer')


def question_probe(expression):
    return inspector(ui.udid, int(os.environ['LODY_UI_METRO_PORT']), 'Runtime.evaluate', {
        'expression': expression, 'returnByValue': True,
    })['result'].get('value')


def open_questions():
    ui.axe('tap', '--label', 'Fixtures')
    ui.axe('tap', '--label', 'Question Fixture', '--post-delay', '1')
    ui.wait(lambda items: any(i.get('AXUniqueId') == 'question-option-0' for i in items), 'Question card missing')


open_questions()
ui.capture('question-single')
ui.axe('tap', '--id', 'question-option-0')
ui.axe('tap', '--id', 'question-next')
ui.wait(lambda items: any(i.get('AXLabel') == 'Which checks should run?' for i in items), 'Next must reach the multi-select question')
ui.axe('tap', '--id', 'question-option-0')
ui.axe('tap', '--id', 'question-option-1')
ui.capture('question-multiple')
assert question_probe('globalThis.__lodyUiVerifyQuestion.attempts') == 0, 'Choosing options must never submit automatically'
ui.axe('tap', '--id', 'question-previous')
ui.wait(lambda items: any(i.get('AXLabel') == 'Which language should we use?' for i in items), 'Previous answer page missing')
ui.axe('tap', '--id', 'question-next')
ui.axe('tap', '--id', 'question-next')
ui.wait(lambda items: any(i.get('AXLabel') == 'Anything else we should know?' for i in items), 'Next must reach the free-text question')
ui.axe('tap', '--id', 'question-custom')
ui.axe('type', 'Keep it native')
ui.capture('question-text')
ui.axe('tap', '--id', 'question-submit', '--post-delay', '1')
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('permission.error.send') for i in items), 'Upload failure must retain the card')
observed_answers = question_probe('globalThis.__lodyUiVerifyQuestion.answers')
assert observed_answers == {
    'language': 'Swift', 'checks': ['Unit tests', 'UI tests'], 'notes': 'Keep it native',
}, 'The production card did not submit the full answer set'
print('Observed answer payload: ' + json.dumps(observed_answers), flush=True)
assert question_probe('globalThis.__lodyUiVerifyQuestion.attempts') == 1
ui.capture('question-retry')
ui.axe('tap', '--id', 'question-submit', '--post-delay', '1')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'question-submit' for i in items), 'Successful retry did not close the card')
ui.capture('question-answered')
open_questions()
question_probe('globalThis.__lodyUiVerifyQuestion.remoteAnswer()')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'question-submit' for i in items), 'Desktop answer did not close the question card')
ui.capture('question-answered-elsewhere')
ui.wait(lambda items: any(i.get('AXUniqueId') == 'session-input' and i.get('AXValue') == DRAFT for i in items), 'Question resolution lost the composer draft')
print('PASS: multi-question answers, navigation, failed upload, retry and desktop resolution')
