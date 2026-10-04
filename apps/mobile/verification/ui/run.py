"""Run offline UI baselines on a managed Simulator lease; see README.md."""
import argparse
import json
import os
from pathlib import Path
import signal
import select
import shutil
import subprocess
import sys
import time
from contextlib import nullcontext
from orchestrator import diagnose_metro, managed_metro, run_batches
from driver import UI
from inspector import inspector

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from simulator import DEVICE_TYPES, run_with_simulator, SimulatorPool

CHAT = ROOT / 'apps/mobile/modules/lody-kit/verification/chat'
BATCHES = {
    'pages': ['pull-request', 'mentions-production', 'project-history-entry', 'project-history', 'notifications', 'settings', 'appearance', 'inbox', 'background', 'permission', 'home', 'licenses', 'navigation', 'onboarding', 'community-notice', 'live-activity'],
    'send': ['root-reuse', 'mention-chat', 'mention-sheet', 'send-transition', 'send-transition-handoff', 'send-queue', 'send-interrupt', 'send-rounds', 'send', 'send-handoff', 'model-options', 'fast-chat', 'fast-sheet', 'composer', 'attachment-overlay-chat', 'attachment-overlay-sheet', 'attachment-camera-chat', 'attachment-camera-sheet', 'composer-glass', 'composer-glass-chat', 'composer-video', 'composer-success', 'composer-failure', 'model-memory'],
    'chat': ['user-mentions', 'file-preview', 'mcp-files', 'chat-performance', 'chat-stream-performance', 'layout', 'tracking', 'smooth-scroll', 'image-preview', 'markdown', 'duration', 'changes', 'inline-diff'],
}
PHONE_CASES = [case for batch in BATCHES.values() for case in batch]
# These lease an iPad. `--case` still accepts them; the default phone run must not.
PAD_CASES = ['ipad', 'ipad-chrome', 'native-shell', 'native-collection']
CASES = PHONE_CASES + PAD_CASES
# These select HomePreviewProviders at app launch, using the same shared bundle.
HOME_CASES = {'mentions-production', 'home', 'licenses', 'navigation', 'project-history-entry', 'ipad', 'ipad-chrome'}
PREVIEW = {
    'native-shell': 'native-shell-poc',
    'native-collection': 'native-collection-poc',
    'pull-request': 'pull-request-preview',
    'mention-chat': 'mention-chat',
    'mention-sheet': 'mention-sheet',
    'send-transition': 'send-preview',
    'send-transition-handoff': 'send-handoff',
    'notifications': 'notification-preview',
    'live-activity': 'live-activity-preview',
    'permission': 'permission-preview',
    'send-queue': 'send-queue',
    'send-interrupt': 'send-interrupt',
    'send-rounds': 'send-preview',
    'user-mentions': 'file-preview',
    'file-preview': 'file-preview',
    'mcp-files': 'file-preview',
    'chat-performance': 'chat-performance',
    'chat-stream-performance': 'chat-stream-performance',
    'project-history': 'project-history-preview',
    'settings': 'settings-preview',
    'appearance': 'appearance-preview',
    'model-memory': 'model-memory',
    'smooth-scroll': 'scroll-preview',
    'duration': 'permission-preview',
    'send': 'send-preview',
    'send-handoff': 'send-handoff',
    'background': 'background-preview',
    'attachment-camera-chat': 'composer-success',
    'attachment-camera-sheet': 'composer-preview',
    'attachment-overlay-chat': 'composer-success',
    'attachment-overlay-sheet': 'composer-preview',
    'composer': 'composer-preview',
    'composer-glass': 'composer-preview',
    'fast-chat': 'chat-preview',
    'fast-sheet': 'composer-preview',
    'composer-glass-chat': 'composer-success',
    'composer-video': 'composer-success',
    'composer-success': 'composer-success',
    'composer-failure': 'composer-failure',
    'inbox': 'inbox-preview',
    'onboarding': 'onboarding-preview',
    'community-notice': 'community-notice',
}
READY = {
    'native-shell': 'native-shell-ready',
    'native-collection': 'poc-native-collection',
    'pull-request': 'session-input',
    'mention-chat': 'session-input',
    'mention-sheet': 'create-session-input',
    'send-transition': 'send-status',
    'send-transition-handoff': 'create-session-input',
    'notifications': 'notification-preview-ready',
    'live-activity': 'live-activity-preview-ready',
    'send-queue': 'send-status',
    'send-interrupt': 'send-status',
    'send-rounds': 'send-status',
    'user-mentions': 'file-links:answer',
    'file-preview': 'file-links:answer',
    'mcp-files': 'file-links:answer',
    'project-history': 'history-project:["studio","demo"]',
    'settings': 'settings-machine',
    'appearance': 'dark-background-soft',
    'model-memory': 'create-session-input',
    'send': 'send-status',
    'send-handoff': 'create-session-input',
    'background': 'background-status',
    'attachment-camera-chat': 'session-input',
    'attachment-camera-sheet': 'create-session-input',
    'attachment-overlay-chat': 'session-input',
    'attachment-overlay-sheet': 'create-session-input',
    'composer': 'create-session-input',
    'composer-glass': 'create-session-input',
    'fast-chat': 'session-input',
    'fast-sheet': 'create-session-input',
    'composer-glass-chat': 'session-input',
    'composer-video': 'session-input',
    'composer-success': 'session-input',
    'composer-failure': 'session-input',
    'inbox': 'inbox-wait',
    'onboarding': 'onboarding-connect',
    'community-notice': 'community-notice',
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
selection.add_argument('--parallel', action='store_true', help='Run all three batches on separate leased Simulators sharing one Metro')
parser.add_argument('--shared-metro', action='store_true', help=argparse.SUPPRESS)
parser.add_argument('--camera-access', choices=['fixture', 'allow', 'deny'], default='fixture', help='Camera capture fixture or real system permission return')
parser.add_argument('--photo-access', choices=['full', 'limited', 'denied', 'settings'], default='full', help='Real system Photos permission outcome for attachment overlay cases')
parser.add_argument('--language', choices=['en', 'zh-Hans'], default='en', help='App Language for this run; scenes assert the matching catalog')
args = parser.parse_args()
if args.parallel and (args.udid or args.shared_metro):
    parser.error('--parallel owns three Simulator leases and its Metro; omit --udid and --shared-metro')
os.environ['LODY_UI_PHOTO_ACCESS'] = args.photo_access
os.environ['LODY_UI_CAMERA_ACCESS'] = args.camera_access
args.output = args.output.resolve()
# Stale evidence is replaced in place; only a run needing A/B comparison picks a different --output.
if not args.shared_metro and any((args.output / marker).exists() for marker in ['results.json', 'batches.json', 'environment.json', 'metro.log']):
    shutil.rmtree(args.output)
args.output.mkdir(parents=True, exist_ok=True)
if args.parallel:
    commands = {
        batch: [sys.executable, __file__, '--app', str(args.app.resolve()), '--batch', batch,
                '--output', str(args.output / batch), '--port', str(args.port),
                '--language', args.language, '--camera-access', args.camera_access, '--photo-access', args.photo_access, '--shared-metro']
        for batch in BATCHES
    }
    with managed_metro(ROOT, args.port, args.output):
        raise SystemExit(run_batches(commands, args.output))
selected = PHONE_CASES
if args.batch:
    selected = BATCHES[args.batch]
if args.case:
    selected = [args.case]
if args.udid is None:
    verify_name = f'UI {args.batch}' if args.batch else 'UI'
    if args.case is not None:
        verify_name = args.case.replace('-', ' ').title()
    command = [sys.executable, __file__, *sys.argv[1:]]
    device_type = DEVICE_TYPES['ipad'] if args.case in PAD_CASES else DEVICE_TYPES['iphone']
    raise SystemExit(
        run_with_simulator(
            SimulatorPool(device_type=device_type), verify_name, command
        )
    )
def sim(*command, check=True, timeout=60):
    result = subprocess.run(['xcrun', 'simctl', *command], timeout=timeout, capture_output=True, text=True)
    if check and result.returncode:
        print(result.stderr or result.stdout, file=sys.stderr)
        result.check_returncode()
    return result

def terminate_app():
    # Reinstall/reset can already have stopped the app. Some runtime versions
    # wait indefinitely when asked to terminate an absent UIKit process.
    running = sim('spawn', args.udid, 'launchctl', 'list').stdout.splitlines()
    if any(line.split()[0].isdigit() and 'UIKitApplication:app.innei.lody[' in line for line in running):
        sim('terminate', args.udid, 'app.innei.lody', check=False)

results = []
# Only the parent starts/prewarms/stops Metro; batch workers never own it.
metro_context = nullcontext() if args.shared_metro else managed_metro(ROOT, args.port, args.output)
with metro_context:
    try:
        (args.output / 'environment.json').write_text(json.dumps({
            'node': subprocess.check_output(['node', '--version'], text=True).strip(),
            'batch': args.batch, 'cases': selected, 'metroPort': args.port, 'sharedMetro': args.shared_metro,
            'udid': args.udid, 'app': str(args.app.resolve()), 'language': args.language,
            'photoAccess': args.photo_access, 'cameraAccess': args.camera_access,
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
        if args.photo_access in ['full', 'limited'] and any(case.startswith('attachment-overlay-') for case in selected):
            # Photos outlives app launches. Seed once per app container so repeats
            # don't fill the grid with duplicates or reinitialize the photo service.
            container = Path(sim('get_app_container', args.udid, 'app.innei.lody', 'data').stdout.strip())
            seeded = container / 'Library/Caches/lody-ui-photo-fixture-v3'
            if not seeded.exists():
                terminate_app()
                # Enough rows to exercise layout changes while scrolled.
                fixtures = args.output / 'photo-fixtures'
                fixtures.mkdir(parents=True, exist_ok=True)
                photos = []
                for index in range(12):
                    photo = fixtures / f'photo-{index}.png'
                    shutil.copyfile(ROOT / 'apps/mobile/assets/icon.png', photo)
                    photos.append(str(photo.resolve()))
                sim('addmedia', args.udid, *photos, timeout=120)
                seeded.parent.mkdir(parents=True, exist_ok=True)
                seeded.touch()
        sim('ui', args.udid, 'content_size', 'large')
        cases = sorted(HOME_CASES.intersection(selected)) + [case for case in selected if case not in HOME_CASES]
        launch_mode = None
        app_pid = None
        trace_throw = bool(set(selected).intersection({'send-transition', 'send-transition-handoff', 'send', 'send-handoff', 'send-rounds', 'send-queue', 'ipad-chrome'}))
        for appearance in ['light', 'dark']:
            sim('ui', args.udid, 'appearance', appearance)
            for case in cases:
                output = args.output / appearance / case
                ui = UI(args.udid, output)
                recording = None
                started = time.monotonic()
                result = {'case': case, 'appearance': appearance, 'language': args.language, 'status': 'failed'}
                try:
                    if case.startswith('attachment-camera-'):
                        terminate_app()
                        launch_mode = None
                        if args.camera_access != 'fixture':
                            sim('privacy', args.udid, 'reset', 'camera', 'app.innei.lody')
                    if case.startswith('attachment-overlay-'):
                        terminate_app()
                        sim('privacy', args.udid, 'reset', 'photos', 'app.innei.lody')
                        launch_mode = None
                    mode = (case in HOME_CASES, case in ('smooth-scroll', 'chat-performance'))
                    if case == 'chat-performance':
                        container = Path(sim('get_app_container', args.udid, 'app.innei.lody', 'data').stdout.strip())
                        (container / 'tmp/lody-chat-loading.json').unlink(missing_ok=True)
                    restart = launch_mode != mode or case in HOME_CASES
                    if restart:
                        result['appLifecycle'] = 'launch'
                        terminate_app()
                        sim('launch', args.udid, 'app.innei.lody', '--ui-verify', *(['--ui-verify-camera'] if case.startswith('attachment-camera-') and args.camera_access == 'fixture' else []), *(['--ui-verify-home'] if case in HOME_CASES else []), *(['--ui-verify-mentions'] if case in {'mentions-production', 'home', 'ipad', 'ipad-chrome'} else []), *(['--ui-verify-scroll'] if mode[1] else []), *(['--ui-verify-throw'] if trace_throw else []), '--initialUrl', f'http://127.0.0.1:{args.port}?disableOnboarding=1', '-expo.devlauncher.hasGrantedNetworkPermission', 'YES', '-EXDevMenuShowsAtLaunch', 'NO', '-EXDevMenuIsOnboardingFinished', 'YES', '-EXDevMenuShowFloatingActionButton', 'NO', '-AppleLanguages', f'({args.language})', '-AppleLocale', 'en_US' if args.language == 'en' else 'zh_CN',
                            '-AppleKeyboards', '(en_US@sw=QWERTY)')
                        launch_mode = mode
                    recording = subprocess.Popen(['xcrun', 'simctl', 'io', args.udid, 'recordVideo', '--codec=hevc', str(output / 'run.mp4')], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
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
                    if not restart:
                        result['appLifecycle'] = 'return-to-root'
                        inspector(args.udid, args.port, 'Runtime.evaluate', {
                            'expression': 'globalThis.__lodyUiVerifyReset()',
                        })
                    processes = sim('spawn', args.udid, 'launchctl', 'list').stdout.splitlines()
                    result['appPid'] = next((line.split()[0] for line in processes if 'UIKitApplication:app.innei.lody[' in line), None)
                    assert result['appPid'], 'Lody process is missing'
                    if result['appLifecycle'] == 'return-to-root':
                        assert result['appPid'] == app_pid, 'Returning to root unexpectedly replaced the App process'
                    app_pid = result['appPid']
                    ui.element('ui-verify-ready', timeout=180)
                    preview = PREVIEW.get(case, 'chat-preview')
                    ready = 'ui-verify-ready' if case in HOME_CASES else READY.get(case, 'session-input')
                    if case.startswith(('attachment-overlay-', 'attachment-camera-')):
                        # Native list AX includes clipped rows. Only touch a row
                        # inside the content viewport, using its current frame.
                        for _ in range(24):
                            row = next((i for i in ui.state() if i.get('AXUniqueId') == preview), None)
                            center = None
                            if row:
                                frame = row['frame']
                                center = frame['y'] + frame['height'] / 2
                            if center is not None and 140 < center < 740:
                                ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(center), '--tap-style', 'physical', '--post-delay', '.8')
                                break
                            start, end = 650, 450
                            if center is not None and center <= 140:
                                start, end = 400, 600
                            ui.axe('swipe', '--start-x', '200', '--start-y', str(start), '--end-x', '200', '--end-y', str(end), '--duration', '.8', '--post-delay', '1')
                        else:
                            raise AssertionError(f'Debug row is not visible: {preview}')
                    elif case not in HOME_CASES:
                        # The Debug list is a native UICollectionView; offscreen rows are not in the tree.
                        for _ in range(8):
                            if any(item.get('AXUniqueId') == preview for item in ui.state()):
                                break
                            ui.axe('swipe', '--start-x', '200', '--start-y', '700', '--end-x', '200', '--end-y', '500', '--duration', '0.5', '--post-delay', '0.6')
                        ui.axe('tap', '--id', preview, '--pre-delay', '0.8', '--post-delay', '0.8', '--tap-style', 'physical')
                    try:
                        ui.element(ready)
                    except AssertionError:
                        if case in ['send-transition', 'send-transition-handoff', 'inbox', 'send', 'send-handoff', 'send-rounds', 'send-queue', 'send-interrupt', 'smooth-scroll'] and any(item.get('AXUniqueId') == preview for item in ui.state()):
                            ui.axe('tap', '--id', preview, '--tap-style', 'physical', '--pre-delay', '0.5', '--post-delay', '1.2')
                            ui.element(ready)
                        else:
                            raise
                    if case == 'permission':
                        ui.wait(lambda items: any(i.get('AXLabel') == 'Fixtures' for i in items), 'Missing permission fixture toolbar')
                    if case == 'image-preview':
                        ui.axe('tap', '--label', 'Fixtures')
                        ui.axe('tap', '--label', 'Image Fixture')
                        ui.element('preview-image:attachment:ui-verify-image')
                    ui.capture('before')
                    script = Path(__file__).with_name(f'{case}.py') if case in ['pull-request', 'project-history-entry', 'project-history', 'notifications', 'user-mentions', 'file-preview', 'chat-performance', 'chat-stream-performance', 'settings', 'appearance', 'send', 'send-handoff', 'send-rounds', 'send-queue', 'send-interrupt', 'smooth-scroll', 'composer', 'composer-glass', 'composer-video', 'markdown', 'duration', 'changes', 'inline-diff', 'background', 'inbox', 'permission', 'home', 'ipad', 'licenses', 'navigation', 'model-memory', 'onboarding', 'community-notice', 'live-activity'] else CHAT / ('composer.py' if case.startswith('composer-') else f'{case}.py')
                    if case in {'native-shell', 'native-collection', 'ipad-chrome'}:
                        script = Path(__file__).with_name(f'{case}.py')
                    if case in ['fast-chat', 'fast-sheet']:
                        script = Path(__file__).with_name('fast.py')
                    if case.startswith('attachment-overlay-'):
                        script = Path(__file__).with_name('attachment-overlay.py')
                    if case.startswith('attachment-camera-'):
                        script = Path(__file__).with_name('attachment-camera.py')
                    if case == 'composer-glass-chat':
                        script = Path(__file__).with_name('composer-glass.py')
                    if case == 'mentions-production':
                        script = Path(__file__).with_name('mentions-production.py')
                    if case == 'root-reuse':
                        script = Path(__file__).with_name('root-reuse.py')
                    if case in ['mention-chat', 'mention-sheet']:
                        script = Path(__file__).with_name('mentions.py')
                    if case in ['send-transition', 'send-transition-handoff']:
                        script = Path(__file__).with_name('send-transition.py')
                    command = [sys.executable, str(script), args.udid]
                    if case in ['composer-success', 'composer-failure']:
                        command += ['--expect', case.removeprefix('composer-'), '--output', str(output)]
                    elif case == 'layout':
                        command += ['--send']
                    else:
                        command += [str(output)]
                    check_timeout = 180
                    if case.startswith('attachment-overlay-') and args.photo_access == 'full':
                        check_timeout = 300
                    elif case == 'chat-performance':
                        check_timeout = 480
                    elif case in ('chat-stream-performance', 'home', 'model-memory', 'mention-chat', 'mention-sheet', 'mentions-production'):
                        check_timeout = 300
                    with (output / 'check.log').open('w') as log:
                        subprocess.run(command, check=True, timeout=check_timeout, stdout=log, stderr=subprocess.STDOUT,
                                       env={**os.environ, 'LODY_UI_LANGUAGE': args.language, 'LODY_UI_METRO_PORT': str(args.port)})
                    ui.capture('after')
                    result['status'] = 'passed'
                except Exception as error:
                    # A failed case may have crashed or left a system modal; recover explicitly.
                    launch_mode = None
                    result['error'] = str(error)
                    diagnose_metro(args.port, output, 'failure')
                    try:
                        native_log = sim('spawn', args.udid, 'log', 'show', '--last', '5m', '--style', 'compact', '--predicate', 'process == "Lody"', check=False)
                        (output / 'native.log').write_text(native_log.stdout + native_log.stderr)
                    except Exception as log_error:
                        result['nativeLogError'] = str(log_error)
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
        terminate_app()
if not results or any(r['status'] != 'passed' for r in results):
    raise SystemExit(1)
