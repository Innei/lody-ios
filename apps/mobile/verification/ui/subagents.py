"""A turn's sub agents read as one group, show their latest step, and open their run history."""
import json
import sys
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])


def value(identifier):
    return ui.element(identifier).get('AXValue') or ''


def labelled(prefix):
    return ui.wait(
        lambda items: next((i for i in items if (i.get('AXLabel') or '').startswith(prefix) and i.get('frame')), None),
        f'Missing element labelled {prefix!r}',
    )


def tap(identifier, delay='1.2'):
    frame = ui.element(identifier)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + min(30, frame['height'] / 2)), '--post-delay', delay)


def dismiss():
    ui.axe('swipe', '--start-x', '200', '--start-y', '140', '--end-x', '200', '--end-y', '820', '--duration', '0.3', '--post-delay', '1.2')


first = 'agents-reply:explore'
assert '5 agents' in value(first), value(first)
assert 'Housekeeping' not in json.dumps(ui.state())
ui.capture('group')

ui.wait(lambda items: any('Read src/auth/guard.ts' in (i.get('AXValue') or '') for i in items if i.get('AXUniqueId') == first), 'The running agent must show its latest step', timeout=20)
assert 'Lost track' in value('agents-reply:migrator')
assert 'Cancelled' in value('agents-reply:docs')
ui.capture('latest-step')

tap(first)
ui.element('subagent-run-status')
ui.element('subagent-run-incomplete')
ui.capture('run-detail')
ui.axe('tap', '--id', 'subagent-run-stop', '--post-delay', '1.2')
ui.wait(lambda items: any('Cancelled' in (i.get('AXLabel') or '') for i in items if i.get('AXUniqueId') == 'subagent-run-status'), 'Stop must cancel the run')
assert 'subagent-run-stop' not in [i.get('AXUniqueId') for i in ui.state()]
ui.capture('run-stopped')
dismiss()

tap('agents-reply:reviewer')
ui.element('subagent-run-status')
ui.capture('run-completed')
dismiss()

tap('agents-reply:tests')
ui.element('subagent-detail-result')
ui.capture('legacy-detail')
print('Sub agents group per turn, surface live steps and lost/cancelled states, and open a live run history with Stop; legacy tasks keep their summary view.')
