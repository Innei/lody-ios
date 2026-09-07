"""Run offline UI baselines on a disposable Simulator; see README.md."""
import argparse
import json
import os
from pathlib import Path
import signal
import select
import subprocess
import sys
import time
from urllib.request import urlopen
from driver import UI

ROOT = Path(__file__).resolve().parents[4]
CHAT = ROOT / 'apps/mobile/modules/lody-kit/verification/chat'
CASES = ['send', 'send-handoff', 'layout', 'tracking', 'model-options', 'image-preview', 'composer', 'composer-success', 'composer-failure', 'markdown', 'changes', 'inbox', 'background', 'home']
PREVIEW = {
    'send': 'send-preview',
    'send-handoff': 'send-handoff',
    'background': 'background-preview',
    'composer': 'composer-preview',
    'composer-success': 'composer-success',
    'composer-failure': 'composer-failure',
    'inbox': 'inbox-preview',
}
READY = {
    'send': 'send-status',
    'send-handoff': 'create-session-input',
    'background': 'background-status',
    'composer': 'create-session-input',
    'composer-success': 'session-input',
    'composer-failure': 'session-input',
    'inbox': 'inbox-wait',
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--udid', required=True, help='Disposable simulator, never a personal device')
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', type=Path, default=ROOT / '.artifacts/ui')
parser.add_argument('--port', type=int, default=8097)
parser.add_argument('--case', choices=CASES)
parser.add_argument('--language', choices=['en', 'zh-Hans'], default='en', help='App Language for this run; scenes assert the matching catalog')
args = parser.parse_args()
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
if (args.output / 'results.json').exists():
    raise SystemExit('Use a new --output directory to preserve earlier evidence')
ui = UI(args.udid, args.output)
home_results = []
if args.case is None:
    home_output = args.output / 'home'
    subprocess.run([sys.executable, __file__, '--udid', args.udid, '--app', str(args.app), '--output', str(home_output), '--port', str(args.port), '--case', 'home', '--language', args.language], check=True)
    home_results = json.loads((home_output / 'results.json').read_text())

def sim(*command, check=True):
    return subprocess.run(['xcrun', 'simctl', *command], check=check, timeout=60, capture_output=True, text=True)

# Never reuse a Metro whose bundle may restore credentials or select another checkout.
import socket
try:
    with socket.create_connection(('localhost', args.port), timeout=2):
        raise SystemExit(f'Port {args.port} is occupied; choose another --port')
except OSError:
    pass
metro_log = (args.output / 'metro.log').open('w')
metro = subprocess.Popen(['pnpm', '--filter', '@lody-ios/mobile', 'exec', 'expo', 'start', '--dev-client', '--host', 'lan', '--port', str(args.port)],
                         cwd=ROOT, env={**os.environ, 'CI': '1', 'EXPO_NO_DOTENV': '1', 'EXPO_PUBLIC_UI_VERIFY': '1', 'EXPO_PUBLIC_UI_VERIFY_HOME': '1' if args.case == 'home' else '0', 'REACT_NATIVE_PACKAGER_HOSTNAME': '127.0.0.1'},
                         stdout=metro_log, stderr=subprocess.STDOUT, start_new_session=True)
results = home_results
try:
    deadline = time.monotonic() + 90
    while True:
        if metro.poll() is not None:
            raise RuntimeError('Metro exited; inspect metro.log')
        try:
            with urlopen(f'http://localhost:{args.port}/status', timeout=2) as response:
                if b'packager-status:running' in response.read():
                    break
        except OSError:
            pass
        if time.monotonic() > deadline:
            raise TimeoutError('Metro did not become ready')
        time.sleep(.5)
    (args.output / 'environment.json').write_text(json.dumps({
        'udid': args.udid, 'app': str(args.app.resolve()), 'language': args.language,
        'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'worktreeDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'axe': subprocess.check_output(['axe', '--version'], text=True).strip(),
    }, indent=2))
    sim('spawn', args.udid, 'defaults', 'write', 'com.apple.keyboard.preferences', 'AutomaticMinimizationEnabled', '-bool', 'false')
    keyboard = args.output / 'software-keyboard'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(Path(__file__).with_name('software-keyboard.m')), '-o', str(keyboard)], check=True, timeout=60)
    subprocess.run([str(keyboard), subprocess.check_output(['xcode-select', '-p'], text=True).strip(), args.udid], check=True, timeout=30)
    sim('install', args.udid, str(args.app.resolve()))
    sim('ui', args.udid, 'content_size', 'large')
    cases = [args.case] if args.case else [case for case in CASES if case != 'home']
    for appearance in ['light', 'dark']:
        sim('ui', args.udid, 'appearance', appearance)
        for case in cases:
            output = args.output / appearance / case
            ui = UI(args.udid, output)
            recording = None
            started = time.monotonic()
            result = {'case': case, 'appearance': appearance, 'language': args.language, 'status': 'failed'}
            try:
                sim('terminate', args.udid, 'app.innei.lody', check=False)
                sim('launch', args.udid, 'app.innei.lody', '--ui-verify', '--initialUrl', f'http://localhost:{args.port}?disableOnboarding=1', '-expo.devlauncher.hasGrantedNetworkPermission', 'YES', '-AppleLanguages', f'({args.language})', '-AppleLocale', 'en_US' if args.language == 'en' else 'zh_CN')
                ui.element('ui-verify-ready', timeout=90)
                preview = PREVIEW.get(case, 'chat-preview')
                ready = 'new-session-tab' if case == 'home' else READY.get(case, 'chat-navigation-title')
                if case != 'home':
                    ui.axe('tap', '--id', preview, '--pre-delay', '0.8', '--post-delay', '0.8', *(['--tap-style', 'physical'] if case == 'background' else []))
                try:
                    ui.element(ready)
                except AssertionError:
                    if case in ['inbox', 'send', 'send-handoff'] and any(item.get('AXUniqueId') == preview for item in ui.state()):
                        ui.axe('tap', '--id', preview, '--pre-delay', '0.5', '--post-delay', '1.2')
                        ui.element(ready)
                    else:
                        raise
                if case == 'image-preview':
                    ui.axe('tap', '--label', 'Image Fixture')
                    ui.element('preview-image:user')
                recording = subprocess.Popen(['xcrun', 'simctl', 'io', args.udid, 'recordVideo', '--codec=h264', str(output / 'run.mp4')], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    if select.select([recording.stderr], [], [], .5)[0]:
                        line = recording.stderr.readline()
                        if b'Recording started' in line:
                            break
                        if not line:
                            raise RuntimeError('Video recorder exited before its first frame')
                else:
                    raise TimeoutError('Video recorder did not start')
                ui.capture('before')
                script = Path(__file__).with_name(f'{case}.py') if case in ['send', 'send-handoff', 'composer', 'markdown', 'changes', 'background', 'inbox', 'home'] else CHAT / ('composer.py' if case.startswith('composer-') else f'{case}.py')
                command = [sys.executable, str(script), args.udid]
                if case.startswith('composer-'):
                    command += ['--expect', case.removeprefix('composer-'), '--output', str(output)]
                elif case == 'layout':
                    command += ['--send']
                else:
                    command += [str(output)]
                with (output / 'check.log').open('w') as log:
                    subprocess.run(command, check=True, timeout=180, stdout=log, stderr=subprocess.STDOUT,
                                   env={**os.environ, 'LODY_UI_LANGUAGE': args.language})
                ui.capture('after')
                result['status'] = 'passed'
            except Exception as error:
                result['error'] = str(error)
                native_log = sim('spawn', args.udid, 'log', 'show', '--last', '3m', '--style', 'compact', '--predicate', 'process == "Lody"', check=False)
                (output / 'native.log').write_text(native_log.stdout + native_log.stderr)
                try:
                    ui.capture('failure')
                except Exception as capture_error:
                    result['captureError'] = str(capture_error)
            finally:
                if recording is not None:
                    recording.send_signal(signal.SIGINT)
                    try:
                        recording.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        recording.kill()
                        recording.wait()
                    recording.stderr.close()
                if recording is not None and (not (output / 'run.mp4').exists() or (output / 'run.mp4').stat().st_size == 0):
                    result.update(status='failed', error='Required video was not captured')
                result['seconds'] = round(time.monotonic() - started, 2)
                results.append(result)
                (args.output / 'results.json').write_text(json.dumps(results, indent=2))
                print(json.dumps(result), flush=True)
finally:
    sim('terminate', args.udid, 'app.innei.lody', check=False)
    if metro.poll() is None:
        os.killpg(metro.pid, signal.SIGTERM)
    try:
        metro.wait(timeout=20)
    except subprocess.TimeoutExpired:
        os.killpg(metro.pid, signal.SIGKILL)
        metro.wait()
    metro_log.close()
if not results or any(r['status'] != 'passed' for r in results):
    raise SystemExit(1)
