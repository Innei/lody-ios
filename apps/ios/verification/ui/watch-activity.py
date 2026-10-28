"""Capture the production small-family view in a native watchOS verification host.

This does not claim ActivityKit/Smart Stack forwarding. That needs the paired
phone flow described in activity-host/README.md. Every capture retains its AX
hierarchy and the fixture label on screen, so provenance is unambiguous.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--udid', default=os.environ.get('LODY_VERIFY_UDID'))
args = parser.parse_args()
if not args.udid:
    parser.error('Run inside pnpm verify:simulator --device watch (or watch-small)')
args.output.mkdir(parents=True, exist_ok=True)


def sim(*command):
    return subprocess.run(['xcrun', 'simctl', *command], check=True, capture_output=True, text=True, timeout=90)


def nodes(value):
    if isinstance(value, list):
        for item in value:
            yield from nodes(item)
    elif isinstance(value, dict):
        yield value
        yield from nodes(value.get('children', []))


sim('install', args.udid, str(args.app))
results = []
for name, title in [
    ('single', 'Refactor session list paging'), ('running', 'Refactor session list paging'),
    ('permission', 'Poll GitHub PR status'), ('question', 'Migrate the Keychain access group'),
    ('done', 'Fix the CI cache key'), ('failed', 'Fix the CI cache key'),
    ('doneMany', 'Refactor session list paging'), ('stale', 'Refactor session list paging'),
    ('permission-aod', 'Poll GitHub PR status'),
]:
    fixture = name.removesuffix('-aod')
    start = time.monotonic()
    sim('launch', '--terminate-running-process', args.udid, 'app.innei.lody.small-activity-verify',
        '-fixture', fixture, '-reduced', 'YES' if name.endswith('-aod') else 'NO',
        '-AppleLanguages', '(en)', '-AppleLocale', 'en_US')
    deadline = time.monotonic() + 45
    while True:
        raw = subprocess.check_output(['axe', 'describe-ui', '--udid', args.udid], text=True, timeout=30)
        tree = json.loads(raw)
        labels = [n.get('AXLabel', '') or '' for n in nodes(tree)]
        if any(title in label for label in labels) and any(f'· {fixture}' in label for label in labels):
            break
        if time.monotonic() > deadline:
            raise RuntimeError(f'{name}: production title never became visible: {labels}')
        time.sleep(0.3)
    if fixture in ['permission', 'question']:
        assert any('Waiting' in label for label in labels), labels
    if fixture == 'failed':
        assert any('Failed' in label for label in labels), labels
    if fixture == 'doneMany':
        assert any('2 tasks finished' in label for label in labels), labels
    if fixture == 'stale':
        assert any('Outdated' in label for label in labels), labels
    (args.output / f'{name}.json').write_text(raw)
    # AX can become ready before the watch launch transition finishes. Reject a
    # black centre frame; this readiness check is not a visual-correctness claim.
    capture_deadline = time.monotonic() + 10
    while True:
        image = args.output / f'{name}.png'
        sim('io', args.udid, 'screenshot', str(image))
        brightness = subprocess.check_output([
            'ffmpeg', '-v', 'error', '-i', str(image), '-vf',
            'crop=iw:ih/2:0:ih/4', '-pix_fmt', 'gray', '-f', 'rawvideo', '-'
        ], timeout=10)
        if sum(value > 80 for value in brightness) > 100:
            break
        if time.monotonic() > capture_deadline:
            raise RuntimeError(f'{name}: the framebuffer remained black after AX readiness')
        time.sleep(0.2)
    results.append({'fixture': name, 'entrySeconds': round(time.monotonic() - start, 2),
                    'titlePresent': True, 'visualReview': 'pending'})
    print(f'Captured {name}', flush=True)
(args.output / 'observations.json').write_text(json.dumps({
    'surface': 'watchOS native host of production small view; not Smart Stack forwarding',
    'udid': args.udid, 'app': str(args.app), 'checks': results,
}, indent=2) + '\n')
