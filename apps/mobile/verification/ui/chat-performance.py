"""Three repeated native scroll runs; report performance without a fake FPS gate."""
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time
from driver import UI

ui = UI(sys.argv[1], sys.argv[2])
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
loading_path = container / 'tmp/lody-chat-loading.json'
ui.capture('loading-state')
ui.element('perf-9998:user')
ui.axe('swipe', '--start-x', '200', '--start-y', '400', '--end-x', '200', '--end-y', '550', '--duration', '.4', '--post-delay', '.5')
anchor_y = ui.element('perf-9998:user')['frame']['y']
stable = 0
deadline = time.monotonic() + 10
while stable < 3:
    assert time.monotonic() < deadline, 'Scroll did not settle during loading'
    time.sleep(.2)
    current_y = ui.element('perf-9998:user')['frame']['y']
    stable = stable + 1 if abs(current_y - anchor_y) < .5 else 0
    anchor_y = current_y
assert not loading_path.exists(), 'Reading-position check missed history preparation'
ui.capture('loading-scrolled')
deadline = time.monotonic() + 90
while not loading_path.exists():
    assert time.monotonic() < deadline, 'History preparation did not finish'
    time.sleep(.2)
loading = json.loads(loading_path.read_text())
shutil.copy2(loading_path, ui.output / 'loading.json')
loading_path.unlink()
assert loading['rows'] == 15_000, 'History is incomplete (including completed reply metadata)'
assert 0 < loading['firstRows'] < loading['rows'], 'First paint waited for all history'
assert 0 < loading['firstContentMs'] < loading['completeMs'], 'Missing staged first paint'
assert len(loading['sliceMs']) > 1, 'History did not yield between measurement batches'
ui.element('perf-9999:text')
assert abs(ui.element('perf-9998:user')['frame']['y'] - anchor_y) < 3, 'History insertion moved the reading position'
ui.capture('history-ready')
ui.axe('tap', '--id', 'chat-scroll-to-bottom', '--post-delay', '1')
reports = []
for run in range(3):
    existing = set((container / 'tmp').glob('lody-chat-performance-*.json'))
    ui.axe('tap', '--label', 'Run Chat Benchmark', '--post-delay', '.2')
    deadline = time.monotonic() + 110
    while not (paths := set((container / 'tmp').glob('lody-chat-performance-*.json')) - existing):
        assert time.monotonic() < deadline, 'Native benchmark did not complete'
        time.sleep(1)
    path = next(iter(paths))
    report = json.loads(path.read_text())
    shutil.copy2(path, ui.output / f'run-{run + 1}.json')
    assert report['entries'] == 10_000 and report['rows'] == 15_000, 'Incomplete dataset'
    assert 20 <= report['seconds'] < 30, 'Incomplete measurement interval'
    samples = report['samples']
    offsets = [s['offset'] for s in samples]
    assert max(offsets) - min(offsets) > 70_000, 'Scroll did not cover the requested distance'
    deltas = [b - a for a, b in zip(offsets, offsets[1:])]
    assert sum(d < -1 for d in deltas) > 20 and sum(d > 1 for d in deltas) > 20, 'Missing bidirectional motion'
    assert all(s['mib'] > 0 for s in report['memory']), 'Memory sampling failed'
    assert abs(report['fps'] - len(samples) / report['seconds']) < .001
    intervals = sorted(s['dt'] * 1000 for s in samples)
    report['p95FrameMs'] = intervals[int((len(intervals) - 1) * .95)]
    report['maxFrameMs'] = max(intervals)
    report['overBudgetPercent'] = 100 * sum(s['dt'] > s['budget'] * 1.5 for s in samples) / len(samples)
    report['visitedSectionRange'] = [min(s['firstSection'] for s in samples), max(s['lastSection'] for s in samples)]
    reports.append({k: v for k, v in report.items() if k not in ['samples', 'memory']})
    ui.capture(f'run-{run + 1}-complete')
summary = {'runs': reports, 'medianFPS': statistics.median(r['fps'] for r in reports)}
(ui.output / 'performance-summary.json').write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
