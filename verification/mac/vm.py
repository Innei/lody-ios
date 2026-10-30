#!/usr/bin/env python3
"""Run the Lody Mac XCUITest suite inside a disposable macOS VM.

The host builds once with ``xcodebuild build-for-testing``; a Tart clone of the
prepared base VM boots headless, runs ``test-without-building`` over SSH with the
host's Xcode shared read-only, and is deleted afterwards. Nothing appears on the host display and the host's pointer
and keyboard are never used.

    pnpm verify:mac:vm                     # all cases
    pnpm verify:mac:vm --case sidebar      # one case
    pnpm verify:mac:vm --in-process        # also run pnpm verify:mac inside the guest
    pnpm verify:mac:vm prepare             # build the base VM once (about 30 min)

VM disks, clones and the IPSW live in an APFS sparse bundle (default
``/Volumes/WD/lody-vm.sparsebundle``, mounted at ``/Volumes/LodyVM``) with
``TART_HOME`` inside it. Screenshots and the .xcresult land in
``.artifacts/mac-verify-vm``.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import fcntl
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / 'Lody.xcodeproj'
OUTPUT = ROOT / '.artifacts/mac-verify-vm'
BUNDLE = Path(os.environ.get('LODY_VM_BUNDLE', '/Volumes/WD/lody-vm.sparsebundle'))
VOLUME = Path(os.environ.get('LODY_VM_VOLUME', '/Volumes/LodyVM'))
TART_HOME = VOLUME / 'tart'
BASE = 'lody-macos-27.2'
IPSW = VOLUME / 'ipsw/UniversalMac_27.2_26B123_Restore.ipsw'
IPSW_URL = ('https://updates.cdn-apple.com/2026FallFCS/c9671975-52db-4fb5-9af2-00217169ba8d/'
            'UniversalMac_27.2_26B123_Restore.ipsw')
XCODE = Path(os.environ.get('LODY_VM_XCODE', '/Applications/Xcode-27.1.0.app'))
GUEST_XCODE = '/Volumes/My Shared Files/Xcode.app'
KEY = VOLUME / 'ssh/id_ed25519'
GUEST_USER = 'admin'
GUEST_PASSWORD = 'admin'
SHARED = '/Volumes/My Shared Files'
CASES = {
    'sign-in': 'SignInTests',
    'sidebar': 'SidebarTests',
    'tabs': 'TabsTests',
    'transcript': 'TranscriptTests',
    'composer-new': 'ComposerNewTests',
    'composer-reply': 'ComposerReplyTests',
    'accent': 'AccentTests',
    'offscreen': 'OffscreenTests',
    'settings': 'SettingsTests',
}


def progress(message):
    print(message, file=sys.stderr, flush=True)


def tart(*args, check=True, capture=True, timeout=None):
    binary = shutil.which('tart') or str(Path.home() / '.local/bin/tart')
    env = {**os.environ, 'TART_HOME': str(TART_HOME)}
    result = subprocess.run([binary, *args], env=env, text=True, capture_output=capture, timeout=timeout)
    if check and result.returncode:
        raise SystemExit(f'tart {" ".join(args)} failed: {(result.stderr or "").strip()}')
    return result


def mount():
    if VOLUME.is_dir():
        return
    if not BUNDLE.exists():
        raise SystemExit(f'no VM bundle at {BUNDLE}; create it with: hdiutil create -size 200g -type SPARSEBUNDLE '
                         f'-fs APFS -volname {VOLUME.name} {BUNDLE}')
    subprocess.run(['hdiutil', 'attach', '-nobrowse', '-owners', 'on', str(BUNDLE)], check=True,
                   stdout=subprocess.DEVNULL)


@contextmanager
def locked():
    VOLUME.joinpath('runs').mkdir(exist_ok=True)
    with open(VOLUME / 'runs/.lock', 'w') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def vms():
    return {vm['Name'] for vm in json.loads(tart('list', '--format', 'json').stdout)}


class Guest:
    def __init__(self, name, shares, log, extra=()):
        self.name = name
        self.log = log
        dirs = [f'--dir={tag}:{path}' for tag, path in shares.items()]
        binary = shutil.which('tart') or str(Path.home() / '.local/bin/tart')
        self.process = subprocess.Popen(
            [binary, 'run', '--no-graphics', '--no-audio', *extra, *dirs, name],
            env={**os.environ, 'TART_HOME': str(TART_HOME)},
            stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        self.ip = None

    def boot(self, timeout=600, password=False):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise SystemExit(f'the VM exited during boot; see {self.log.name}')
            if not self.ip:
                found = tart('ip', self.name, '--wait', '5', check=False)
                self.ip = found.stdout.strip() if found.returncode == 0 else None
            if self.ip and self.ssh('true', check=False, timeout=15, password=password).returncode == 0:
                return self
            time.sleep(3)
        raise SystemExit(f'the VM did not accept SSH within {timeout}s')

    def ssh(self, command, check=True, timeout=None, password=False, stdout=None):
        options = ['-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'LogLevel=ERROR',
                   '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=15']
        env = dict(os.environ)
        if password:
            askpass = Path(tempfile.mkdtemp()) / 'askpass'
            askpass.write_text(f'#!/bin/sh\necho {GUEST_PASSWORD}\n')
            askpass.chmod(0o700)
            env.update(SSH_ASKPASS=str(askpass), SSH_ASKPASS_REQUIRE='force', DISPLAY=':0')
            options += ['-o', 'PubkeyAuthentication=no', '-o', 'PreferredAuthentications=password,keyboard-interactive']
        else:
            options += ['-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-i', str(KEY)]
        result = subprocess.run(['ssh', *options, f'{GUEST_USER}@{self.ip}', command], env=env, text=True,
                                stdin=subprocess.DEVNULL, stdout=stdout or subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
        if check and result.returncode:
            raise SystemExit(f'guest command failed ({result.returncode}): {command}\n{result.stdout or ""}')
        return result

    def stop(self):
        if self.process.poll() is None:
            tart('stop', self.name, '--timeout', '60', check=False)
            try:
                self.process.wait(timeout=90)
            except subprocess.TimeoutExpired:
                self.process.kill()


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
            progress('waiting for the first boot to provision the admin account')
            guest.boot(timeout=1200, password=True)
            progress('provisioning: passwordless sudo, no sleep or lock, Xcode, automation mode')
            guest.ssh(PROVISION, password=True, timeout=3600)
            guest.ssh('sudo shutdown -h now', check=False, timeout=30)
            guest.process.wait(timeout=180)
        finally:
            guest.stop()
        settle(log)
    ready.touch()
    progress(f'{BASE} is ready')


def settle(log):
    # One more login lets first-run banners (Xcode's extensions notice) fire in the base, not in every clone.
    guest = Guest(BASE, {'Xcode.app': f'{XCODE}:ro'}, log)
    try:
        progress('settling a second login')
        guest.boot()
        guest.ssh('sleep 90; sudo shutdown -h now', check=False, timeout=180)
        guest.process.wait(timeout=180)
    finally:
        guest.stop()


def build(log):
    command = ['xcodebuild', '-project', str(PROJECT), '-scheme', 'LodyMac', '-configuration', 'Debug',
               '-destination', 'platform=macOS']
    progress('building LodyMac and LodyMacUITests for testing')
    with log.open('w') as handle:
        result = subprocess.run(command + ['build-for-testing'], cwd=ROOT, stdout=handle, stderr=subprocess.STDOUT)
    if result.returncode:
        errors = [line for line in log.read_text().splitlines() if 'error:' in line]
        raise SystemExit('\n'.join(errors[-20:]) + f'\nbuild-for-testing failed; log {log}')
    settings = subprocess.run(command + ['-showBuildSettings'], cwd=ROOT, capture_output=True, text=True,
                              check=True).stdout
    values = dict(line.strip().partition(' = ')[::2] for line in settings.splitlines() if ' = ' in line)
    return Path(values['BUILD_DIR'])


def warm_up(guest):
    guest.boot()
    started = time.monotonic()
    healthy = guest.ssh(f"for i in $(seq 30); do [ -d '{GUEST_XCODE}' ] && break; sleep 1; done; "
                        'xcodebuild -version', check=False, timeout=900)
    if healthy.returncode:
        raise SystemExit(f'the guest cannot run the shared Xcode at {XCODE}\n{healthy.stdout.strip()}')
    progress(f'guest Xcode ready after {time.monotonic() - started:.0f}s (first launch scans the share)')


def stage(products, target, in_process):
    runs = sorted(products.glob('LodyMac_*.xctestrun'), key=lambda path: path.stat().st_mtime)
    if not runs:
        raise SystemExit(f'no LodyMac .xctestrun in {products}')
    shutil.copy2(runs[-1], target / 'LodyMac.xctestrun')
    for name in ['Lody.app', 'LodyMacUITests-Runner.app', 'PackageFrameworks']:
        source = products / 'Debug' / name
        if source.exists():
            subprocess.run(['ditto', str(source), str(target / 'Debug' / name)], check=True)
    if in_process:
        node = shutil.which('node')
        if not node:
            raise SystemExit('--in-process needs node on the host to copy into the guest')
        shutil.copy2(Path(node).resolve(), target / 'node')
        for name in ['run.mts', 'lib', 'cases']:
            subprocess.run(['ditto', str(ROOT / 'verification/mac' / name), str(target / 'mac' / name)], check=True)


def export(result, output):
    attachments = output / 'attachments'
    subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                    '--output-path', str(attachments)], check=True, stdout=subprocess.DEVNULL)
    manifest = json.loads((attachments / 'manifest.json').read_text())
    named = []
    for test in manifest:
        for attachment in test.get('attachments', []):
            source = attachments / attachment['exportedFileName']
            human = Path(attachment.get('suggestedHumanReadableName') or source.name).stem
            stem = re.sub(r'_\d+_[0-9A-F-]{36}$', '', human).replace('/', '-')
            target = output / f'{stem}{source.suffix}'
            shutil.move(source, target)
            named.append(target.name)
    shutil.rmtree(attachments)
    summary = json.loads(subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path',
                                         str(result)], capture_output=True, text=True, check=True).stdout)
    return summary, sorted(named)


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
    with locked():
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
            progress(f'booting {name} headless while the host builds')
            ready = pool.submit(warm_up, guest)
            stage(build(output / 'build.log'), work / 'products', args.in_process)
            ready.result()
            only = [f'-only-testing:LodyMacUITests/{CASES[case]}' for case in args.case]
            test = ' '.join([
                f"rm -rf ~/run && mkdir ~/run && (cd '{SHARED}/products' && tar --no-mac-metadata -cf - .) | (cd ~/run && tar -xpf -) &&",
                'xcodebuild test-without-building -xctestrun ~/run/LodyMac.xctestrun -destination platform=macOS',
                '-resultBundlePath ~/run/LodyMac.xcresult', *only,
                f"> '{SHARED}/out/test.log' 2>&1; code=$?;",
                f"(cd ~/run && tar --no-mac-metadata -cf - LodyMac.xcresult) | (cd '{SHARED}/out' && tar -xf -); exit $code",
            ])
            progress('running XCUITest in the guest')
            finished = guest.ssh(test, check=False, timeout=args.timeout)
            status = finished.returncode
            if finished.stdout.strip():
                progress(finished.stdout.strip())
            if args.in_process:
                progress('running the in-process suite in the guest')
                cases = ' '.join(f'--case {case}' for case in args.case)
                in_process = guest.ssh(' '.join([
                    '~/run/node --experimental-strip-types ~/run/mac/run.mts --app ~/run/Debug/Lody.app',
                    f"--output '{SHARED}/out/in-process' {cases} > '{SHARED}/out/in-process.log' 2>&1",
                ]), check=False, timeout=args.timeout).returncode
                status = status or in_process
        finally:
            guest.stop()
            pool.shutdown()
            tart('delete', name, check=False)
            log.close()
        for item in ['test.log', 'LodyMac.xcresult', 'in-process', 'in-process.log']:
            if (work / 'out' / item).exists():
                shutil.move(work / 'out' / item, output / item)
        shutil.move(work / 'tart.log', output / 'tart.log')
        shutil.rmtree(work, ignore_errors=True)
    result = output / 'LodyMac.xcresult'
    if not result.exists():
        raise SystemExit(f'the guest produced no result bundle; see {output / "test.log"}')
    summary, files = export(result, output)
    print(json.dumps({
        'result': summary.get('result'),
        'passed': summary.get('passedTests'),
        'failed': summary.get('failedTests'),
        'failures': [f"{item.get('testName')}: {item.get('failureText')}" for item in summary.get('testFailures', [])],
        'seconds': round(time.monotonic() - started, 1),
        'output': str(output),
        'attachments': len(files),
    }, indent=1, ensure_ascii=False))
    raise SystemExit(0 if status == 0 and summary.get('result') == 'Passed' else 1)


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('command', nargs='?', default='run', choices=['run', 'prepare'])
parser.add_argument('--case', action='append', default=[], help=f'one of {", ".join(CASES)}; repeatable')
parser.add_argument('--output', default=str(OUTPUT))
parser.add_argument('--in-process', action='store_true',
                    help='also run the in-process suite (pnpm verify:mac) inside the guest')
parser.add_argument('--timeout', type=int, default=1800, help='seconds allowed for the guest test run')
parser.add_argument('--force', action='store_true', help='prepare: reinstall and reprovision the base VM')
parser.add_argument('--cpu', type=int, default=6)
parser.add_argument('--memory', type=int, default=16, help='GB')
parser.add_argument('--display', default='1680x1050')

if __name__ == '__main__':
    arguments = parser.parse_args()
    prepare(arguments) if arguments.command == 'prepare' else run(arguments)
