from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import sys
import threading
import time

TEST_LINE = re.compile(r"Test Case '-\[\w+\.(\w+) (\w+)\]' (started|passed|failed)")


def parse_tests(text):
    current, passed, failed = None, 0, 0
    for suite, test, event in TEST_LINE.findall(text):
        if event == 'started':
            current = f'{suite}.{test}'
            continue
        current = None
        passed += event == 'passed'
        failed += event == 'failed'
    return {'current': current, 'passed': passed, 'failed': failed}


def parse_in_process(text):
    counts = {'passed': 0, 'failed': 0}
    for line in text.splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if isinstance(entry, dict) and entry.get('status') in counts:
            counts[entry['status']] += 1
    return counts


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def live(record):
    return bool(record.get('pid')) and not record.get('finished') and alive(record['pid'])


def lock_owner(text):
    found = re.search(r'verify:mac:vm pid (\d+)', text)
    return int(found[1]) if found else None


def runner_state(running, keeper, vnc):
    if not running:
        return 'stopped'
    return 'up' if keeper and vnc else 'booting'


def idle_left(now, last, idle):
    return max(0, round(idle - (now - last)))


def history(text, count=10):
    entries = []
    for line in text.splitlines():
        try:
            entries.append(json.loads(line))
        except ValueError:
            continue
    return entries[-count:]


class Progress:
    def __init__(self, path=None, history_path=None):
        self.path, self.history_path = path, history_path
        self.record = {}
        self.depth = {}
        self.lock = threading.Lock()

    def begin(self, kind, cases, output, log=None, in_process_log=None):
        self.record = {
            'pid': os.getpid(), 'kind': kind, 'argv': sys.argv, 'cwd': os.getcwd(), 'started': time.time(),
            'cases': list(cases), 'output': str(output), 'log': log, 'in_process_log': in_process_log,
            'steps': [], 'finished': None, 'result': None,
        }
        self.save()

    def start(self, name):
        with self.lock:
            self.depth[name] = self.depth.get(name, 0) + 1
            if self.depth[name] == 1:
                self.record.setdefault('steps', []).append(
                    {'name': name, 'state': 'running', 'started': time.time(), 'ended': None})
            self.save()

    def finish(self, name, state='done'):
        with self.lock:
            self.depth[name] = max(0, self.depth.get(name, 1) - 1)
            if self.depth[name] == 0 or state == 'failed':
                for step in reversed(self.record.get('steps', [])):
                    if step['name'] == name and step['state'] == 'running':
                        step.update(state=state, ended=time.time())
                        break
            self.save()

    @contextmanager
    def step(self, name):
        self.start(name)
        try:
            yield
        except BaseException:
            self.finish(name, 'failed')
            raise
        self.finish(name)

    def end(self, result):
        with self.lock:
            now = time.time()
            for step in self.record.get('steps', []):
                if step['state'] == 'running':
                    step.update(state='done', ended=now)
            self.record.update(finished=now, result=result)
            self.save()
            if self.history_path and self.record.get('started'):
                entry = {key: self.record[key] for key in ('kind', 'cases', 'result', 'started', 'output')}
                entry['seconds'] = round(now - self.record['started'], 1)
                with Path(self.history_path).open('a') as handle:
                    handle.write(json.dumps(entry) + '\n')

    def save(self):
        if not self.path:
            return
        path = Path(self.path)
        partial = path.with_suffix('.partial')
        partial.write_text(json.dumps(self.record))
        partial.replace(path)


current = Progress()


def failure(error):
    text = str(error).strip()
    return f'failed: {text.splitlines()[0] if text else type(error).__name__}'


def short_command(command):
    program, _, rest = command.partition(' ')
    return f'{Path(program).name} {rest}'.strip()


def duration(seconds):
    minutes, seconds = divmod(max(0, int(seconds)), 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f'{hours}h{minutes:02d}m'
    return f'{minutes}m{seconds:02d}s' if minutes else f'{seconds}s'


def counts(label, tests):
    line = f'{tests["passed"]} passed, {tests["failed"]} failed'
    return f'         {label:<11}{line}' + (f', now {tests["current"]}' if tests.get('current') else '')


def render(snapshot):
    now, runner, lock, run = snapshot['now'], snapshot['runner'], snapshot['lock'], snapshot['run']
    state = f'Runner   {runner["name"]}: {runner["state"]}'
    if runner['paused']:
        state += ', idle timer paused while a run holds the lock'
    elif runner['idle_left'] is not None:
        state += f', idle stop in {duration(runner["idle_left"])}'
    lines = [state]
    if runner['vnc']:
        lines.append(f'VNC      {runner["vnc"]}  (login admin / admin; View → Observe)')
    if lock:
        tty = lock['tty'] if lock['tty'] not in (None, '??') else 'no tty'
        lines += [f'Lock     held by pid {lock["pid"]} since {lock["started"]} on {tty}',
                  f'         {short_command(lock["command"])}', f'         cwd {lock["cwd"] or "unknown"}']
    else:
        lines.append('Lock     free')
    if run:
        cases = ' '.join(run['cases']) or 'all'
        lines.append(f'Run      {run["kind"]} {cases}, {duration(now - run["started"])}, output {run["output"]}')
        steps = []
        for step in run['steps']:
            if step['state'] == 'running':
                steps.append(f'{step["name"]} running {duration(now - step["started"])}')
            else:
                steps.append(f'{step["name"]} {duration(step["ended"] - step["started"])}'
                             + (' FAILED' if step['state'] == 'failed' else ''))
        lines.append(f'         steps      {", ".join(steps) or "starting"}')
        if run['tests']:
            lines.append(counts('XCUITest', run['tests']))
        if run['in_process']:
            lines.append(counts('in-process', run['in_process']))
    else:
        lines.append('Run      not running')
    lines.append(f'History  last {len(snapshot["history"])}' if snapshot['history'] else 'History  none yet')
    for entry in reversed(snapshot['history']):
        started = time.strftime('%m-%d %H:%M', time.localtime(entry.get('started') or 0))
        cases = ' '.join(entry.get('cases') or []) or 'all'
        lines.append(f'  {started}  {entry.get("kind", "?"):<7} {cases:<22} {entry.get("result") or "?":<8} '
                     f'{entry.get("seconds", 0):.0f}s  {entry.get("output", "")}')
    return '\n'.join(lines)
