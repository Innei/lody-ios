"""Replay identical 300 synthetic TPS fixtures through the production RN/native path."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])
container = Path(subprocess.check_output(
    ['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
reports = container / 'tmp'
summary = []


def percentile(values, fraction):
    values = sorted(values)
    return values[min(len(values) - 1, int((len(values) - 1) * fraction))]


for scenario in ['paragraphs', 'text', 'code']:
    before = set(reports.glob('lody-stream-performance-*.json'))
    ui.axe('tap', '--label', f'Stream {scenario}', '--post-delay', '.3')
    time.sleep(7)
    ui.capture(f'{scenario}-streaming')
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        fresh = set(reports.glob('lody-stream-performance-*.json')) - before
        if fresh:
            break
        time.sleep(.5)
    else:
        raise AssertionError(f'{scenario}: native stream probe did not finish')
    assert len(fresh) == 1, 'More than one fixture probe reported'
    source = fresh.pop()
    data = json.loads(source.read_text())
    shutil.copy2(source, ui.output / f'{scenario}-samples.json')
    for check in data.get('layoutChecks', []):
        if 'difference' in check:
            assert check['difference'] <= 2, ('Block layout differs from the full Markdown renderer', check)
        if check['name'] == 'reuse':
            assert check['sameSizingAndDisplayView'] and check['stablePrefixUntouched'], check
        if check['name'] == 'reference':
            assert check['lateReferenceResolved'], check
        if check['name'] == 'selection':
            assert check['completedMessageSelectsAcrossBlocks'], check
        if check['name'] == 'syntax':
            assert check['partialBoldRendered'] and check['completionRestoresSource'] and check['partialLinkIsText'], check
    samples = data['samples']
    assert data['received'] >= 14_400, ('Truncated input fixture', data['received'])
    assert 10 < data['inputSeconds'] < 20, ('Input was not a sustained stream', data['inputSeconds'])
    assert data['shown'] == data['received'], 'Stream did not deliver all text'
    assert samples[-1]['fading'] == 0 and samples[-1]['finished'] == 1, 'Final text never visually settled'
    assert not any(s['finished'] == 1 and s['fading'] == 1 for s in samples), 'Completion interrupted the final fade'
    if scenario != 'code':
        assert any(s['shown'] > 4096 and s['fading'] == 1 for s in samples), 'Long replies lost their animated tail'
    caught_up = next((s['t'] - data['inputSeconds'] for s in samples
                     if s['t'] >= data['inputSeconds'] and s['lag'] == 0 and s['fading'] == 0 and s['finished'] == 1 and
                     abs(s['bottom'] - s['offset']) <= 1), None)
    assert caught_up is not None, 'Stream never caught up'
    assert max(s['offset'] for s in samples) - min(s['offset'] for s in samples) > 1000, 'Fixture did not exercise scrolling'
    assert samples[-1]['bottom'] - samples[-1]['offset'] <= 1, 'Following never reached the tail'
    ui.element('stream-perf-answer:text')
    ui.capture(f'{scenario}-complete')
    if scenario == 'text':
        # Fade invalidation is restricted to the tail. Earlier lines must still
        # have their pixels when scrolling back within the same long text view.
        ui.axe('swipe', '--start-x', '200', '--start-y', '300', '--end-x', '200', '--end-y', '650',
               '--duration', '.6', '--post-delay', '.6')
        ui.element('chat-scroll-to-bottom')
        ui.capture('text-earlier-lines')
        ui.axe('tap', '--id', 'chat-scroll-to-bottom', '--post-delay', '.8')
    active = [s for s in samples if s['t'] <= data['inputSeconds']]
    intervals = [s['dt'] * 1000 for s in active]
    commits = data['commitsMs']
    result = {
        'scenario': scenario,
        'inputSeconds': data['inputSeconds'],
        'fps': len(active) / active[-1]['t'],
        'p95FrameMs': percentile(intervals, .95),
        'maxFrameMs': max(intervals),
        'framesOver50Ms': sum(t > 50 for t in intervals),
        'p95CommitMs': percentile(commits, .95),
        'commitCount': len(commits),
        'p95LagUnits': percentile([s['lag'] for s in active], .95),
        'p95BottomGapPt': percentile([max(0, s['bottom'] - s['offset']) for s in active], .95),
        'catchUpSeconds': caught_up,
    }
    summary.append(result)
    (ui.output / 'stream-summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(result), flush=True)

# Hold each incoming prefix so its actual native rendered state is reviewable.
for step, name in enumerate(['bold', 'code', 'partial-link', 'complete-link', 'partial-stop', 'stopped']):
    ui.axe('tap', '--label', 'Next syntax', '--post-delay', '1')
    ui.element('stream-perf-answer:text')
    ui.capture(f'syntax-{name}')
