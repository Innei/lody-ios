"""In a Home-style navigation host, the composer task chip opens the task sheet and one tap on a file surface, including a streamed-then-settled .md link, presents exactly one page."""
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])


def probe(items=None):
    match = next((i for i in items or ui.state() if i.get('AXUniqueId') == 'session-preview-probe'), None)
    return ((match or {}).get('AXValue') or '').split(',')


def tap_point(x, y, delay='.6'):
    ui.axe('tap', '-x', str(x), '-y', str(y), '--post-delay', delay)


def tap_center(frame):
    tap_point(frame['x'] + frame['width'] / 2, frame['y'] + frame['height'] / 2)


def close_pages():
    closed = 0
    for _ in range(4):
        items = ui.state()
        close = next((i for i in items if i.get('AXUniqueId') in ('file-back', 'file-quicklook-close')), None)
        close = close or next((i for i in items if i.get('type') == 'Button' and i.get('AXLabel') == catalog.text('native.close')), None)
        if not close:
            return closed
        tap_center(close['frame'])
        closed += 1
    return closed


def opens_once(name, x, y):
    before = probe().count('present')
    tap_point(x, y, '1.5')
    ui.capture(name)
    closed = close_pages()
    presented = probe().count('present') - before
    assert presented == 1 and closed == 1, f'{name}: one tap presented {presented} pages and needed {closed} closes'
    ui.element('session-subtasks')


ui.wait(lambda items: 'settled' in probe(items), 'The streamed reply did not settle')
tasks = ui.element('session-subtasks')
assert tasks.get('AXLabel') == catalog.plural('native.chat.overlay.tasks', 1), tasks.get('AXLabel')
ui.capture('loaded')
report = ui.element('preview-working:report')['frame']
assert report['y'] + report['height'] <= tasks['frame']['y'], 'The assistant file row is under the composer'
opens_once('assistant-file', report['x'] + report['width'] / 2, report['y'] + report['height'] / 2)

tap_center(ui.element('session-subtasks')['frame'])
ui.wait(lambda items: any(i.get('AXLabel') == catalog.text('process.tasks') for i in items), 'The task chip did not open the task sheet')
ui.element('preview-working:running-task')
ui.capture('tasks-sheet')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('process.tasks')), '--post-delay', '.8')
ui.wait(lambda items: not any(i.get('AXLabel') == catalog.text('process.tasks') for i in items), 'The task sheet did not close')

reply = ui.element('preview-answer:reply')['frame']
# Production Markdown: a 24pt line and 8pt paragraph gap put "Updated App.tsx" at +48; the link starts near +71.
for x in (reply['x'] + 72, reply['x'] + 100):
    opens_once(f'reply-link-{round(x)}', x, reply['y'] + 48)
mention = ui.element('preview-follow-up:user-text')['frame']
opens_once('user-mention', mention['x'] + mention['width'] - 40, mention['y'] + 26)
attachment = ui.element('preview-follow-up:attachment:fixture-attachment')['frame']
opens_once('user-attachment', attachment['x'] + attachment['width'] / 2, attachment['y'] + attachment['height'] / 2)
plan = ui.element('preview-working:plan')['frame']
assert plan['y'] + plan['height'] <= ui.element('session-subtasks')['frame']['y'], 'The settled .md link is under the composer'
opens_once('settled-md-link', plan['x'] + 150, plan['y'] + plan['height'] / 2)
print('PASS: the task chip opens the task sheet; reply links, mentions and file attachments each present one page per tap')
