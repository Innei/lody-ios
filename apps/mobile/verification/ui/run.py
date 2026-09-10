"""Run offline UI baselines on a managed Simulator lease; see README.md."""
import argparse
import json
import os
from pathlib import Path
import signal
import select
import subprocess
import sys
import time
from urllib.request import Request, urlopen
from driver import UI

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from simulator import run_with_simulator, SimulatorPool

CHAT = ROOT / 'apps/mobile/modules/lody-kit/verification/chat'
BATCHES = {
    'pages': ['notifications', 'settings', 'inbox', 'background', 'permission', 'home', 'licenses', 'onboarding', 'live-activity'],
    'send': ['send-queue', 'send-interrupt', 'send-rounds', 'send', 'send-handoff', 'model-options', 'composer', 'composer-glass', 'composer-video', 'composer-success', 'composer-failure', 'model-memory'],
    'chat': ['file-preview', 'chat-performance', 'chat-stream-performance', 'layout', 'tracking', 'smooth-scroll', 'image-preview', 'markdown', 'duration', 'changes', 'inline-diff'],
}
CASES = [case for batch in BATCHES.values() for case in batch]
# These run their own HomePreviewProviders bundle and start from the inbox, not Debug.
STANDALONE = {'home', 'licenses'}
PREVIEW = {
    'notifications': 'notification-preview',
    'live-activity': 'live-activity-preview',
    'permission': 'permission-preview',
    'send-queue': 'send-queue',
    'send-interrupt': 'send-interrupt',
    'send-rounds': 'send-preview',
    'file-preview': 'file-preview',
    'chat-performance': 'chat-performance',
    'chat-stream-performance': 'chat-stream-performance',
    'settings': 'settings-preview',
    'model-memory': 'model-memory',
    'smooth-scroll': 'scroll-preview',
    'duration': 'permission-preview',
    'send': 'send-preview',
    'send-handoff': 'send-handoff',
    'background': 'background-preview',
    'composer': 'composer-preview',
    'composer-glass': 'composer-preview',
    'composer-video': 'composer-success',
    'composer-success': 'composer-success',
    'composer-failure': 'composer-failure',
    'inbox': 'inbox-preview',
    'onboarding': 'onboarding-preview',
}
READY = {
    'notifications': 'notification-preview-ready',
    'live-activity': 'live-activity-preview-ready',
    'send-queue': 'send-status',
    'send-interrupt': 'send-status',
    'send-rounds': 'send-status',
    'file-preview': 'file-links:answer',
    'settings': 'settings-machine',
    'model-memory': 'create-session-input',
    'send': 'send-status',
    'send-handoff': 'create-session-input',
    'background': 'background-status',
    'composer': 'create-session-input',
    'composer-glass': 'create-session-input',
    'composer-video': 'session-input',
    'composer-success': 'session-input',
    'composer-failure': 'session-input',
    'inbox': 'inbox-wait',
    'onboarding': 'onboarding-connect',
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    '--udid',
    default=os.environ.get('LODY_VERIFY_UDID') or None,
    help='Existing Simulator; omit to lease a clean Lody Verify Simulator',
)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', type=Path, default=ROOT / '.artifacts/ui')
parser.add_argument('--port', type=int, default=8097)
selection = parser.add_mutually_exclusive_group()
selection.add_argument('--case', choices=CASES)
selection.add_argument('--batch', choices=BATCHES)
parser.add_argument('--language', choices=['en', 'zh-Hans'], default='en', help='App Language for this run; scenes assert the matching catalog')
args = parser.parse_args()
selected = CASES
if args.batch:
    selected = BATCHES[args.batch]
if args.case:
    selected = [args.case]
if args.udid is None:
    verify_name = 'UI'
    if args.case is not None:
        verify_name = args.case.replace('-', ' ').title()
    command = [sys.executable, __file__, *sys.argv[1:]]
    raise SystemExit(run_with_simulator(SimulatorPool(), verify_name, command))
args.output = args.output.resolve()
args.output.mkdir(parents=True, exist_ok=True)
if (args.output / 'results.json').exists():
    raise SystemExit('Use a new --output directory to preserve earlier evidence')
ui = UI(args.udid, args.output)
standalone_results = []
if args.case is None:
    # Each standalone case needs its own HomePreviewProviders Metro instance.
    for standalone in sorted(STANDALONE.intersection(selected)):
        standalone_output = args.output / standalone
        child = subprocess.run([sys.executable, __file__, '--udid', args.udid, '--app', str(args.app), '--output', str(standalone_output), '--port', str(args.port), '--case', standalone, '--language', args.language], check=False)
        result_path = standalone_output / 'results.json'
        if result_path.exists():
            standalone_results += json.loads(result_path.read_text())
        if child.returncode or not result_path.exists():
            standalone_results.append({'case': standalone, 'status': 'failed', 'error': f'Standalone runner exited {child.returncode}'})
        (args.output / 'results.json').write_text(json.dumps(standalone_results, indent=2))

def sim(*command, check=True):
    return subprocess.run(['xcrun', 'simctl', *command], check=check, timeout=60, capture_output=True, text=True)

# Never reuse a Metro whose bundle may restore credentials or select another checkout.
import socket
try:
    with socket.create_connection(('127.0.0.1', args.port), timeout=2):
        raise SystemExit(f'Port {args.port} is occupied; choose another --port')
except OSError:
    pass
metro_log = (args.output / 'metro.log').open('w')
metro = subprocess.Popen(['pnpm', '--filter', '@lody-ios/mobile', 'exec', 'expo', 'start', '--dev-client', '--host', 'lan', '--port', str(args.port)],
                         cwd=ROOT, env={**os.environ, 'NODE_OPTIONS': os.environ.get('NODE_OPTIONS', '') + f' --require="{Path(__file__).resolve().with_name("metro-diagnostics.cjs")}"', 'LODY_UI_METRO_DIAGNOSTICS': '1', 'CI': '1', 'EXPO_NO_DOTENV': '1', 'EXPO_PUBLIC_UI_VERIFY': '1', 'EXPO_PUBLIC_UI_VERIFY_HOME': '1' if args.case in STANDALONE else '0', 'REACT_NATIVE_PACKAGER_HOSTNAME': '127.0.0.1'},
                         stdout=metro_log, stderr=subprocess.STDOUT, start_new_session=True)
def diagnose_metro(phase, output=args.output):
    # Never dump headers, manifests, bundle bodies or the process environment.
    probes = []
    for method, path in [('GET', '/status'), ('HEAD', '/?disableOnboarding=1'), ('GET', '/?disableOnboarding=1')]:
        started = time.monotonic()
        probe = {'method': method, 'path': path.split('?')[0]}
        try:
            request = Request(f'http://127.0.0.1:{args.port}{path}', method=method,
                              headers={'expo-platform': 'ios', 'accept': 'application/expo+json,application/json'})
            with urlopen(request, timeout=10) as response:
                probe['status'] = response.status
                probe['bytes'] = len(response.read())
        except Exception as error:
            probe['error'] = str(error)
        probe['seconds'] = round(time.monotonic() - started, 3)
        probes.append(probe)
    diagnostic = {'phase': phase, 'metroExitCode': metro.poll(), 'probes': probes}
    (output / f'metro-{phase}.json').write_text(json.dumps(diagnostic, indent=2))
    print(json.dumps(diagnostic), flush=True)

results = standalone_results
try:
    deadline = time.monotonic() + 90
    while True:
        if metro.poll() is not None:
            raise RuntimeError('Metro exited; inspect metro.log')
        try:
            with urlopen(f'http://127.0.0.1:{args.port}/status', timeout=2) as response:
                if b'packager-status:running' in response.read():
                    break
        except OSError:
            pass
        if time.monotonic() > deadline:
            raise TimeoutError('Metro did not become ready')
        time.sleep(.5)
    diagnose_metro('startup')
    # Metro binds REACT_NATIVE_PACKAGER_HOSTNAME, so the literal address avoids the
    # Simulator resolving localhost to ::1, connecting, and then never being answered.
    request = Request(f'http://127.0.0.1:{args.port}/?disableOnboarding=1', headers={'expo-platform': 'ios', 'accept': 'application/expo+json'})
    with urlopen(request, timeout=30) as response:
        manifest = json.load(response)
    with urlopen(manifest['launchAsset']['url'], timeout=90) as response:
        response.read()
    (args.output / 'environment.json').write_text(json.dumps({
        'node': subprocess.check_output(['node', '--version'], text=True).strip(),
        'batch': args.batch, 'cases': selected,
        'udid': args.udid, 'app': str(args.app.resolve()), 'language': args.language,
        'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'worktreeDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'axe': subprocess.check_output(['axe', '--version'], text=True).strip(),
    }, indent=2))
    sim('spawn', args.udid, 'defaults', 'write', 'com.apple.keyboard.preferences', 'AutomaticMinimizationEnabled', '-bool', 'false')
    # A Chinese App Language otherwise brings up the pinyin IME, which buffers typed
    # fixture text as composition instead of committing it to the field.
    sim('spawn', args.udid, 'defaults', 'write', 'com.apple.Preferences', 'AppleKeyboards', '-array', 'en_US@sw=QWERTY')
    keyboard = args.output / 'software-keyboard'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(Path(__file__).with_name('software-keyboard.m')), '-o', str(keyboard)], check=True, timeout=60)
    subprocess.run([str(keyboard), subprocess.check_output(['xcode-select', '-p'], text=True).strip(), args.udid], check=True, timeout=30)
    sim('install', args.udid, str(args.app.resolve()))
    sim('ui', args.udid, 'content_size', 'large')
    cases = [case for case in selected if args.case or case not in STANDALONE]
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
                if case == 'chat-performance':
                    container = Path(sim('get_app_container', args.udid, 'app.innei.lody', 'data').stdout.strip())
                    (container / 'tmp/lody-chat-loading.json').unlink(missing_ok=True)
                sim('launch', args.udid, 'app.innei.lody', '--ui-verify', *(['--ui-verify-scroll'] if case == 'smooth-scroll' else []), *(['--ui-verify-throw'] if case in ['send', 'send-handoff', 'send-rounds', 'send-queue'] else []), '--initialUrl', f'http://127.0.0.1:{args.port}?disableOnboarding=1', '-expo.devlauncher.hasGrantedNetworkPermission', 'YES', '-EXDevMenuShowsAtLaunch', 'NO', '-EXDevMenuIsOnboardingFinished', 'YES', '-EXDevMenuShowFloatingActionButton', 'NO', '-AppleLanguages', f'({args.language})', '-AppleLocale', 'en_US' if args.language == 'en' else 'zh_CN',
                    '-AppleKeyboards', '(en_US@sw=QWERTY)')
                ui.element('ui-verify-ready', timeout=180)
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
                preview = PREVIEW.get(case, 'chat-preview')
                ready = 'ui-verify-ready' if case in STANDALONE else READY.get(case, 'session-input')
                if case not in STANDALONE:
                    # The Debug list is a native UICollectionView; offscreen rows are not in the tree.
                    for _ in range(8):
                        if any(item.get('AXUniqueId') == preview for item in ui.state()):
                            break
                        ui.axe('swipe', '--start-x', '200', '--start-y', '700', '--end-x', '200', '--end-y', '500', '--duration', '0.5', '--post-delay', '0.6')
                    ui.axe('tap', '--id', preview, '--pre-delay', '0.8', '--post-delay', '0.8', '--tap-style', 'physical')
                try:
                    ui.element(ready)
                except AssertionError:
                    if case in ['inbox', 'send', 'send-handoff', 'send-rounds', 'send-queue', 'send-interrupt', 'smooth-scroll'] and any(item.get('AXUniqueId') == preview for item in ui.state()):
                        ui.axe('tap', '--id', preview, '--tap-style', 'physical', '--pre-delay', '0.5', '--post-delay', '1.2')
                        ui.element(ready)
                    else:
                        raise
                if case == 'permission':
                    ui.wait(lambda items: any(i.get('AXLabel') == 'Fixtures' for i in items), 'Missing permission fixture toolbar')
                if case == 'image-preview':
                    ui.axe('tap', '--label', 'Fixtures')
                    ui.axe('tap', '--label', 'Image Fixture')
                    ui.element('preview-image:user')
                ui.capture('before')
                script = Path(__file__).with_name(f'{case}.py') if case in ['notifications', 'file-preview', 'chat-performance', 'chat-stream-performance', 'settings', 'send', 'send-handoff', 'send-rounds', 'send-queue', 'send-interrupt', 'smooth-scroll', 'composer', 'composer-glass', 'composer-video', 'markdown', 'duration', 'changes', 'inline-diff', 'background', 'inbox', 'permission', 'home', 'licenses', 'model-memory', 'onboarding', 'live-activity'] else CHAT / ('composer.py' if case.startswith('composer-') else f'{case}.py')
                command = [sys.executable, str(script), args.udid]
                if case in ['composer-success', 'composer-failure']:
                    command += ['--expect', case.removeprefix('composer-'), '--output', str(output)]
                elif case == 'layout':
                    command += ['--send']
                else:
                    command += [str(output)]
                with (output / 'check.log').open('w') as log:
                    subprocess.run(command, check=True, timeout=300 if case in ('chat-stream-performance', 'home') else 180, stdout=log, stderr=subprocess.STDOUT,
                                   env={**os.environ, 'LODY_UI_LANGUAGE': args.language})
                ui.capture('after')
                result['status'] = 'passed'
            except Exception as error:
                result['error'] = str(error)
                diagnose_metro('failure', output)
                native_log = sim('spawn', args.udid, 'log', 'show', '--last', '5m', '--style', 'compact', '--predicate', 'process == "Lody"', check=False)
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
                    result['status'] = 'failed'
                    result.setdefault('error', 'Required video was not captured')
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
