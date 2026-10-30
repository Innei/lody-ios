"""The warm runner: one persistent clone of the base VM that verify:mac:vm runs reuse.

A detached keeper process (``vm_runner.py keep``) owns the runner's ``tart run``, its
VNC forwarder and the idle timer, so the VM and the viewer outlive each run and stop
after IDLE_SECONDS without a run. Each run resets Lody's state in the guest instead
of cloning; the runner is recycled only when the base changes, an infrastructure
failure happened, or ``pnpm verify:mac:vm reset`` is run.
"""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
from types import SimpleNamespace

from vm_guest import (BASE, LOCK, VOLUME, XCODE, Alive, Guest, attempt, build, collect, exclusive, progress, run_tests,
                      stage, tart, vms, warm_up)
from vm_vnc import hold

RUNNER = 'lody-verify-runner'
IDLE_SECONDS = 30 * 60
HOME = VOLUME / 'runner'
MARKER = HOME / 'active'
STATE = HOME / 'state.json'
KEEPER = HOME / 'keeper.json'
TART_LOG = HOME / 'tart.log'
VNC = HOME / 'vnc.txt'
# xcodebuild exits 65 when tests ran and some failed; that is the suite's verdict, not a broken runner.
TEST_CODES = (0, 65)
DOMAINS = ['app.innei.lody.mac', 'app.innei.lody.mac.uitests.xctrunner', 'lody.mac.settings.catalog']
PATHS = [
    '~/Library/Containers/app.innei.lody.mac*',
    '"$HOME/Library/Application Support/app.innei.lody.mac"',
    '"$HOME/Library/Saved Application State/app.innei.lody.mac.savedState"',
    '~/Library/Caches/app.innei.lody.mac',
    '~/Library/HTTPStorages/app.innei.lody.mac',
    '~/run',
]


def reset_command():
    # The bracketed patterns keep pkill -f from matching the shell that runs this command.
    return '; '.join([
        'pkill -9 -x Lody',
        'pkill -9 -f "[L]odyMacUITests-Runner"',
        'pkill -9 -x xctest',
        'pkill -9 -f "[x]codebuild test-without-building"',
        'pkill -9 -f "[r]un/mac/run.mts"',
        *[f'defaults delete {domain} 2>/dev/null' for domain in DOMAINS],
        'rm -rf ' + ' '.join(PATHS),
        'true',
    ])


def recycle_reason(exists, base, recorded, infra, requested=False):
    if requested:
        return 'reset requested'
    if not exists:
        return 'no runner yet'
    if base != recorded:
        return 'the base VM changed'
    if infra:
        return f'the last run hit an infrastructure failure: {infra}'
    return None


def infra_failure(code, has_result, timed_out):
    if timed_out:
        return 'the guest test run timed out'
    if not has_result:
        return f'xcodebuild exited {code} without a result bundle'
    if code not in TEST_CODES:
        return f'xcodebuild exited {code}'
    return None


def plan(running, keeper):
    if running and keeper:
        return 'attach'
    if running:
        return 'restart'
    return 'start'


def idle_expired(now, last, idle=IDLE_SECONDS):
    return now - last >= idle


def base_stamp():
    return (VOLUME / 'runs' / f'{BASE}.ready').stat().st_mtime_ns


def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def save_state(**state):
    STATE.write_text(json.dumps(state))


def running():
    listed = json.loads(tart('list', '--format', 'json').stdout)
    return any(vm['Name'] == RUNNER and vm.get('Running') for vm in listed)


def keeper_pid():
    try:
        pid = json.loads(KEEPER.read_text())['pid']
    except (OSError, ValueError, KeyError):
        return None
    command = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout
    return pid if 'vm_runner.py keep' in command else None


def clear(directory):
    # A running VM keeps sharing the original directory, so empty it rather than replace it.
    directory.mkdir(parents=True, exist_ok=True)
    for item in directory.iterdir():
        if item.is_dir() and not item.is_symlink():
            shutil.rmtree(item)
        else:
            item.unlink()


def shares():
    return {'products': HOME / 'products', 'out': HOME / 'out', 'Xcode.app': f'{XCODE}:ro'}


def stop_keeper():
    pid = keeper_pid()
    if pid:
        os.kill(pid, signal.SIGTERM)
        deadline = time.monotonic() + 120
        while Alive(pid).poll() is None and time.monotonic() < deadline:
            time.sleep(0.5)
    if running():
        tart('stop', RUNNER, '--timeout', '60', check=False)


def discard():
    stop_keeper()
    if RUNNER in vms():
        tart('delete', RUNNER)
    STATE.unlink(missing_ok=True)


def start_keeper(args):
    VNC.unlink(missing_ok=True)
    command = [sys.executable, str(Path(__file__).resolve()), 'keep']
    if args.vnc_port:
        command += ['--vnc-port', str(args.vnc_port)]
    with (HOME / 'keeper.log').open('w') as log:
        keeper = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                  start_new_session=True)
    deadline = time.monotonic() + 90
    while not VNC.exists():
        if keeper.poll() is not None or time.monotonic() > deadline:
            raise SystemExit(f'the runner keeper did not start the VM; see {HOME / "keeper.log"}')
        time.sleep(0.2)
    return keeper


def ready(args, output):
    pid = keeper_pid()
    action = plan(running(), pid is not None)
    if action == 'attach':
        progress(f'attaching to the running {RUNNER}')
        keeper = Alive(pid)
    else:
        if action == 'restart':
            progress(f'{RUNNER} is running without its keeper; restarting it')
            tart('stop', RUNNER, '--timeout', '60', check=False)
        progress(f'starting {RUNNER} headless while the host builds')
        keeper = start_keeper(args)
    line = VNC.read_text().strip()
    progress(line)
    (output / 'vnc.txt').write_text(line + '\n')
    guest = Guest.attach(RUNNER, SimpleNamespace(name=str(TART_LOG)), keeper)
    warm_up(guest)
    guest.ssh(reset_command(), check=False, timeout=60)
    return guest


def session(args, output):
    state = load_state()
    base = base_stamp()
    reason = recycle_reason(RUNNER in vms(), base, state.get('base'), state.get('infra'))
    if reason:
        progress(f'cloning {RUNNER} from {BASE} ({reason})')
        discard()
        tart('clone', BASE, RUNNER)
        save_state(base=base, infra=None)
    clear(HOME / 'products')
    clear(HOME / 'out')
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=1) as pool:
        booting = pool.submit(ready, args, output)
        stage(build(output / 'build.log'), HOME / 'products', args.in_process)
        try:
            guest = booting.result()
        except SystemExit as failure:
            save_state(base=base, infra=str(failure).splitlines()[0])
            raise
    try:
        code, status = run_tests(guest, args)
        timed_out = False
    except subprocess.TimeoutExpired:
        code, status, timed_out = None, 1, True
    infra = infra_failure(code, (HOME / 'out/LodyMac.xcresult').exists(), timed_out)
    save_state(base=base, infra=infra)
    if infra:
        progress(f'{infra}; the runner will be recycled on the next run')
    result = collect(HOME / 'out', output, started, status)
    if TART_LOG.exists():
        shutil.copy2(TART_LOG, output / 'tart.log')
    if args.hold:
        hold(guest.process, f'holding {RUNNER}; Ctrl-C releases it, and it stops after {IDLE_SECONDS // 60} idle min')
    return result


def run(args, output):
    HOME.mkdir(exist_ok=True)
    with exclusive():
        MARKER.touch()
        try:
            return session(args, output)
        finally:
            MARKER.touch()


def reset():
    HOME.mkdir(exist_ok=True)
    with exclusive():
        discard()
    progress(f'{RUNNER} deleted; the next run clones a fresh one from {BASE}')


def keep(vnc_port):
    progress(f'keeper {os.getpid()} starting {RUNNER}')
    log = TART_LOG.open('w')
    guest = Guest(RUNNER, shares(), log)

    def interrupt(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupt)
    try:
        guest.expose(SimpleNamespace(vnc_port=vnc_port, output=HOME))
        KEEPER.write_text(json.dumps({'pid': os.getpid()}))
        MARKER.touch()
        while guest.process.poll() is None:
            time.sleep(10)
            with attempt(LOCK) as free:
                if free and idle_expired(time.time(), MARKER.stat().st_mtime):
                    progress(f'idle for {IDLE_SECONDS // 60} min; stopping {RUNNER}')
                    guest.stop()
    except KeyboardInterrupt:
        progress('stopping on request')
    finally:
        guest.stop()
        KEEPER.unlink(missing_ok=True)
        VNC.unlink(missing_ok=True)
        log.close()


if __name__ == '__main__' and sys.argv[1:2] == ['keep']:
    keep(int(sys.argv[3]) if sys.argv[2:3] == ['--vnc-port'] else None)
