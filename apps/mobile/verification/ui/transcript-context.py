"""Read-only usage, warnings, artifacts, identity, goal lifecycle and agent schedules."""
import sys
from driver import UI

ui = UI(*sys.argv[1:])

def fixture(name):
    ui.axe('tap', '--label', 'Transcript fixtures')
    ui.axe('tap', '--label', name, '--post-delay', '.4')

def descendants(node):
    yield node
    for child in node.get('children', []):
        yield from descendants(child)

def absent(identifier, items=None):
    if items is None:
        items = ui.state()
    assert not any(item.get('AXUniqueId') == identifier for item in items), identifier

def reveal_context(identifier):
    header = ui.element('Transcript context')['frame']
    transcript = ui.element('chat-transcript')['frame']
    x = transcript['x'] + transcript['width'] / 2
    start = header['y'] + header['height'] + 100
    end = min(start + 350, transcript['y'] + transcript['height'] - 200)
    # Context is a scrollable transcript prefix. Inserting it preserves the
    # message being read, so reveal it with the same native gesture as a user.
    ui.axe('swipe', '--start-x', str(x), '--start-y', str(start),
           '--end-x', str(x), '--end-y', str(end), '--duration', '.6', '--post-delay', '.4')
    def visible(items):
        row = next((item for item in items if item.get('AXUniqueId') == identifier), None)
        navigation = next((item for item in items if item.get('AXUniqueId') == 'Transcript context'), None)
        if row is None or navigation is None:
            return None
        frame, bar = row['frame'], navigation['frame']
        if frame['y'] < bar['y'] + bar['height'] - 1:
            return None
        if frame['y'] + frame['height'] > transcript['y'] + transcript['height'] - 140:
            return None
        return row
    return ui.wait(visible, identifier + ' cannot be revealed below the native navigation bar', timeout=10)

assert '32%' in ui.element('session-context-usage')['AXLabel']
assert '64,000' in ui.element('session-context-usage')['AXLabel']
assert '25%' in ui.element('session-quota:codex')['AXLabel']
assert '5,960 tokens' in ui.element('usage-report:meta:details')['AXLabel']
assert 'tokens' not in ui.element('absent-report:meta:details')['AXLabel']
ui.capture('reported-and-absent-usage')
fixture('no-usage')
absent('session-context-usage')
absent('session-quota:codex')
assert 'tokens' not in ui.element('usage-report:meta:details')['AXLabel']
ui.capture('no-usage-placeholder')

fixture('warning')
assert 'temporary interruption' in ui.element('warning-reply:warning')['AXLabel']
ui.capture('warning-visible')
ui.axe('tap', '--id', 'warning-reply:process', '--post-delay', '.4')
process = ui.wait(
    lambda items: next((item for item in items
        if item.get('AXUniqueId') == 'chat-transcript'
        and any(child.get('AXUniqueId') == 'warning-reply:tool' for child in descendants(item))), None),
    'Agent process did not open',
)
process_items = list(descendants(process))
assert any(item.get('AXUniqueId') == 'warning-reply:thought' for item in process_items), 'Process thought is missing'
# Activity is a partial-height sheet; AXe also returns the visible background
# conversation, where the warning must remain. Check the process list itself.
absent('warning-reply:warning', process_items)
ui.capture('warning-outside-process')
ui.axe('tap', '--label', 'Close Activity', '--post-delay', '.4')
ui.wait(lambda items: not any(item.get('AXUniqueId') == 'warning-reply:tool' for item in items), 'Agent process did not dismiss')
assert 'temporary interruption' in ui.element('warning-reply:warning')['AXLabel']

fixture('files')
for name in ['pending', 'expired']:
    assert ui.element('artifact-reply:' + name)['type'] != 'Button', 'Unavailable artifact offered an active download'
assert 'Uploading' in ui.element('artifact-reply:pending')['AXLabel']
assert 'Expired' in ui.element('artifact-reply:expired')['AXLabel']
ui.capture('artifact-lifecycle')
ui.axe('tap', '--id', 'artifact-reply:pdf', '--post-delay', '.3')
ui.element('QLPreviewControllerView')
ui.wait(lambda items: not any(item.get('AXLabel') == 'Loading file…' for item in items), 'Artifact download did not finish')
ui.capture('artifact-quick-look')
button = ui.wait(lambda items: next((item for item in items if item.get('type') == 'Button' and (item.get('AXLabel') or '').lower() in ['done', 'close']), None), 'Quick Look must offer Close')
ui.axe('tap', '--label', button['AXLabel'], '--post-delay', '.4')

fixture('team')
assert ui.element('maya-message:sender')['AXLabel'] == 'Maya Chen'
assert ui.element('ethan-message:sender')['AXLabel'] == 'Ethan'
assert 'Reviewer' in ui.element('reviewer-message:sender')['AXLabel']
ui.capture('team-senders')
fixture('solo')
absent('maya-message:sender')
absent('ethan-message:sender')
ui.element('reviewer-message:sender')
ui.capture('solo-keeps-agent-author')

for status, title in [('active', 'Active'), ('paused', 'Paused'), ('cleared', 'Cleared')]:
    fixture('goal-' + status)
    row = reveal_context('session-goal')
    assert title in row['AXLabel']
    assert 'Stale catalog fallback' not in row['AXLabel']
    ui.capture('goal-' + status)

fixture('schedules')
ui.element('session-scheduled:wakeup')
assert 'Asia/Tokyo' in ui.element('session-scheduled:cron')['AXLabel']
ui.capture('pending-agent-schedules')
fixture('expired-schedule')
absent('session-scheduled:wakeup')
ui.element('session-scheduled:cron')
ui.capture('fired-wakeup-cleared')
print('PASS: reported usage, missing telemetry, secondary warnings, artifact lifecycle/Quick Look, team isolation, authoritative goal and read-only schedules')
