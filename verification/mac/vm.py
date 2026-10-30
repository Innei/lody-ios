#!/usr/bin/env python3
"""Run the Lody Mac XCUITest suite inside a headless macOS VM.

The host builds once with ``xcodebuild build-for-testing`` while the warm runner
VM ``lody-verify-runner`` boots (or is already up); the guest resets Lody's state
and runs ``test-without-building`` over SSH with the host's Xcode shared read-only.
The runner stops after 30 idle minutes and is re-cloned from the base only when
the base changes, after an infrastructure failure, or on ``reset``. Nothing
appears on the host display and the host's pointer and keyboard are never used.

    pnpm verify:mac:vm                     # all cases on the warm runner
    pnpm verify:mac:vm --case sidebar      # one case
    pnpm verify:mac:vm --in-process        # also run pnpm verify:mac inside the guest
    pnpm verify:mac:vm --hold              # keep the run's lock until Ctrl-C
    pnpm verify:mac:vm --fresh             # use a disposable clone instead of the runner
    pnpm verify:mac:vm reset               # delete the runner; the next run clones a new one
    pnpm verify:mac:vm prepare             # build the base VM once (about 30 min)

The runner prints a ``VNC:`` line (also in ``vnc.txt``) for watching the guest:
Virtualization.framework's VNC server is forwarded to loopback port 5905, or the
next free port, or ``--vnc-port``, for as long as the VM is up. Connect with
Screen Sharing in Observe mode so the viewer's pointer and keys never reach the run.

VM disks, clones and the IPSW live in an APFS sparse bundle (default
``/Volumes/WD/lody-vm.sparsebundle``, mounted at ``/Volumes/LodyVM``) with
``TART_HOME`` inside it. Screenshots and the .xcresult land in
``.artifacts/mac-verify-vm``.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import subprocess
import time

from vm_guest import (BASE, CASES, GUEST_PASSWORD, GUEST_USER, IPSW, IPSW_URL, KEY, OUTPUT, SHARED, TART_HOME, VOLUME,
                      XCODE, GUEST_XCODE, Guest, build, collect, exclusive, mount, progress, run_tests, stage, tart,
                      vms, warm_up)
import vm_runner
from vm_vnc import VNC_PORT, hold

# ditto and cp fail on symlinks crossing virtiofs ("Too many levels of symbolic links"); tar copies them intact.
PROVISION = f'''
set -e
echo {GUEST_PASSWORD} | sudo -S sh -c "echo '{GUEST_USER} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/{GUEST_USER}-nopasswd; chmod 440 /etc/sudoers.d/{GUEST_USER}-nopasswd"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qf '{SHARED}/key/id_ed25519.pub' ~/.ssh/authorized_keys 2>/dev/null || cat '{SHARED}/key/id_ed25519.pub' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
sudo systemsetup -setsleep Off >/dev/null 2>&1 || true
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0
defaults -currentHost write com.apple.screensaver idleTime 0
sysadminctl -screenLock off -password {GUEST_PASSWORD} 2>/dev/null || true
sudo mdutil -a -i off >/dev/null || true
sudo softwareupdate --schedule off >/dev/null 2>&1 || true
sudo rm -rf /Applications/Xcode.app
sudo xcode-select -s '{GUEST_XCODE}'
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
sudo DevToolsSecurity -enable
sudo automationmodetool enable-automationmode-without-authentication
defaults write com.apple.WindowManager StandardHideWidgets -int 1
defaults write com.apple.WindowManager StageManagerHideWidgets -int 1
'''


def prepare(args):
    mount()
    TART_HOME.mkdir(exist_ok=True)
    VOLUME.joinpath('runs').mkdir(exist_ok=True)
    ready = VOLUME / 'runs' / f'{BASE}.ready'
    if BASE in vms() and ready.exists() and not args.force:
        progress(f'{BASE} is already prepared; pass --force to rebuild it')
        return
    if BASE in vms() and args.force:
        tart('delete', BASE)
    ready.unlink(missing_ok=True)
    if not IPSW.exists():
        IPSW.parent.mkdir(exist_ok=True)
        progress(f'downloading {IPSW.name}')
        subprocess.run(['curl', '-fL', '-C', '-', '--retry', '5', '-o', str(IPSW), IPSW_URL], check=True)
    if not KEY.exists():
        KEY.parent.mkdir(exist_ok=True)
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'lody-mac-verify', '-f', str(KEY)],
                       check=True)
    if BASE not in vms():
        progress(f'installing macOS from {IPSW.name}')
        tart('create', '--from-ipsw', str(IPSW), '--disk-size', '80', '--disk-format', 'asif', BASE, capture=False)
    tart('set', BASE, '--cpu', str(args.cpu), '--memory', str(args.memory * 1024), '--display', args.display)
    # Provisioning options only take effect on the first boot after creation.
    options = ','.join(['fullName=Lody Verify', f'username={GUEST_USER}', f'password={GUEST_PASSWORD}',
                        'logsInAutomatically=true', 'enablesRemoteLogin=true'])
    with (VOLUME / 'runs/prepare.log').open('w') as log:
        guest = Guest(BASE, {'Xcode.app': f'{XCODE}:ro', 'key': f'{KEY.parent}:ro'}, log,
                      extra=[f'--provisioning-opts={options}'])
        try:
            guest.expose(args)
            progress('waiting for the first boot to provision the admin account')
            guest.boot(timeout=1200, password=True)
            progress('provisioning: passwordless sudo, no sleep or lock, Xcode, automation mode')
            guest.ssh(PROVISION, password=True, timeout=3600)
            guest.ssh('sudo shutdown -h now', check=False, timeout=30)
            guest.process.wait(timeout=180)
        finally:
            guest.stop()
        settle(log, args)
    ready.touch()
    progress(f'{BASE} is ready')


def settle(log, args):
    # One more login lets first-run banners (Xcode's extensions notice) fire in the base, not in every clone.
    guest = Guest(BASE, {'Xcode.app': f'{XCODE}:ro'}, log)
    try:
        guest.expose(args)
        progress('settling a second login')
        guest.boot()
        guest.ssh('sleep 90; sudo shutdown -h now', check=False, timeout=180)
        guest.process.wait(timeout=180)
    finally:
        guest.stop()


def run(args):
    if not shutil.which('tart') and not (Path.home() / '.local/bin/tart').exists():
        raise SystemExit('tart is not installed; put the signed release from github.com/cirruslabs/tart on PATH')
    unknown = [name for name in args.case if name not in CASES]
    if unknown:
        raise SystemExit(f'unknown case {", ".join(unknown)}; choose from {", ".join(CASES)}')
    mount()
    if BASE not in vms():
        raise SystemExit(f'no base VM {BASE}; run pnpm verify:mac:vm prepare first')
    output = Path(args.output).resolve()
    shutil.rmtree(output, ignore_errors=True)
    output.mkdir(parents=True)
    raise SystemExit(run_fresh(args, output) if args.fresh else vm_runner.run(args, output))


def reset(args):
    mount()
    vm_runner.reset()


def run_fresh(args, output):
    with exclusive():
        name = f'lody-verify-{os.getpid()}'
        work = VOLUME / 'runs' / name
        (work / 'products').mkdir(parents=True)
        (work / 'out').mkdir()
        tart('clone', BASE, name)
        log = (work / 'tart.log').open('w')
        guest = Guest(name, {'products': work / 'products', 'out': work / 'out', 'Xcode.app': f'{XCODE}:ro'}, log)
        started = time.monotonic()
        pool = ThreadPoolExecutor(max_workers=1)
        try:
            guest.expose(args)
            progress(f'booting {name} headless while the host builds')
            ready = pool.submit(warm_up, guest)
            stage(build(output / 'build.log'), work / 'products', args.in_process)
            ready.result()
            _, status = run_tests(guest, args)
            code = collect(work / 'out', output, started, status)
            if args.hold:
                hold(guest.process)
        finally:
            guest.stop()
            pool.shutdown()
            tart('delete', name, check=False)
            log.close()
            shutil.move(work / 'tart.log', output / 'tart.log')
            shutil.rmtree(work, ignore_errors=True)
    return code


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('command', nargs='?', default='run', choices=['run', 'prepare', 'reset'])
parser.add_argument('--case', action='append', default=[], help=f'one of {", ".join(CASES)}; repeatable')
parser.add_argument('--output', default=str(OUTPUT))
parser.add_argument('--in-process', action='store_true',
                    help='also run the in-process suite (pnpm verify:mac) inside the guest')
parser.add_argument('--vnc-port', type=int, help=f'fixed loopback port for the VNC viewer (default {VNC_PORT}, '
                    'or the next free one)')
parser.add_argument('--hold', action='store_true', help='keep the VM and VNC up after the run until Ctrl-C')
parser.add_argument('--fresh', action='store_true', help='run in a disposable clone instead of the warm runner')
parser.add_argument('--timeout', type=int, default=1800, help='seconds allowed for the guest test run')
parser.add_argument('--force', action='store_true', help='prepare: reinstall and reprovision the base VM')
parser.add_argument('--cpu', type=int, default=6)
parser.add_argument('--memory', type=int, default=16, help='GB')
parser.add_argument('--display', default='1680x1050')

if __name__ == '__main__':
    arguments = parser.parse_args()
    {'prepare': prepare, 'reset': reset, 'run': run}[arguments.command](arguments)
