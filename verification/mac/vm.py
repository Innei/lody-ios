#!/usr/bin/env python3
"""Run the Lody Mac XCUITest suite inside a headless macOS VM.

The host builds once with ``xcodebuild build-for-testing`` while the warm runner
VM ``lody-verify-runner`` boots (or is already up); the guest checks its Xcode's
signatures, resets Lody's state and runs ``test-without-building`` over SSH. The
runner stops after 30 idle minutes and is re-cloned from the base only when the
base changes, after an infrastructure failure, or on ``reset``. Nothing appears
on the host display and the host's pointer and keyboard are never used.

    pnpm verify:mac:vm                     # all cases on the warm runner
    pnpm verify:mac:vm --case sidebar      # one case
    pnpm verify:mac:vm --in-process        # also run pnpm verify:mac inside the guest
    pnpm verify:mac:vm --hold              # keep the run's lock until Ctrl-C
    pnpm verify:mac:vm --fresh             # use a disposable clone instead of the runner
    pnpm verify:mac:vm --host-xcode        # fallback: a disposable clone runs the host's Xcode from a share
    pnpm verify:mac:vm reset               # delete the runner; the next run clones a new one
    pnpm verify:mac:vm prepare --recovery-vnc   # build or update the base VM (idempotent)
    pnpm verify:mac:vm prepare --repair-xcode   # copy Xcode into the base again

The base has its own copy of the host's Xcode with the iOS Simulator runtime,
first launches done, SIP off and background services trimmed (``SERVICES`` in
vm_base.py). Turning SIP off boots recovery, whose Virtualization.framework VNC
server listens on every interface, so prepare does it only with ``--recovery-vnc``.

The runner prints a ``VNC:`` line (also in ``vnc.txt``): the guest's Screen
Sharing, reachable only from this Mac, is forwarded to loopback port 5905 (or the
next free port, or ``--vnc-port``) while the VM is up. Log in as admin / admin
and use View → Observe so the viewer's pointer and keys never reach the run.

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
import time

from vm_base import prepare, warm_up
from vm_guest import (BASE, CASES, OUTPUT, VOLUME, XCODE, Guest, build, collect, exclusive, mount, progress, run_tests,
                      stage, tart, vms)
import vm_runner
from vm_vnc import VNC_PORT, hold

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
    raise SystemExit(run_fresh(args, output) if args.fresh or args.host_xcode else vm_runner.run(args, output))


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
        shares = {'products': work / 'products', 'out': work / 'out'}
        if args.host_xcode:
            shares['Xcode.app'] = f'{XCODE}:ro'
        guest = Guest(name, shares, log)
        started = time.monotonic()
        pool = ThreadPoolExecutor(max_workers=1)
        try:
            progress(f'booting {name} headless while the host builds')
            ready = pool.submit(lambda: (guest.expose(args), warm_up(guest, args.host_xcode)))
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
parser.add_argument('--host-xcode', action='store_true',
                    help="run the host's Xcode from a read-only share in a disposable clone (fallback)")
parser.add_argument('--force', action='store_true', help='prepare: reinstall and reprovision the base VM')
parser.add_argument('--repair-xcode', action='store_true', help='prepare: copy Xcode into the base again')
parser.add_argument('--recovery-vnc', action='store_true',
                    help="prepare: allow the recovery boot's LAN-reachable VNC server to turn SIP off")
parser.add_argument('--cpu', type=int, default=6)
parser.add_argument('--memory', type=int, default=16, help='GB')
parser.add_argument('--display', default='1680x1050')

if __name__ == '__main__':
    arguments = parser.parse_args()
    {'prepare': prepare, 'reset': reset, 'run': run}[arguments.command](arguments)
