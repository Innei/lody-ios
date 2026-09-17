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
    'pages': ['pull-request', 'mentions-production', 'project-history-entry', 'project-history', 'notifications', 'settings', 'appearance', 'queued-message-behavior', 'inbox', 'background', 'permission', 'home', 'licenses', 'navigation', 'navigation-toolbar', 'onboarding', 'community-notice', 'live-activity', 'project-picker'],
    'send': ['root-reuse', 'mention-chat', 'mention-sheet', 'send-transition', 'send-transition-handoff', 'send-queue', 'steer', 'send-guide', 'send-interrupt', 'send-rounds', 'send', 'send-handoff', 'send-handoff-delayed', 'model-options', 'fast-chat', 'fast-sheet', 'composer', 'composer-glass', 'composer-glass-chat', 'composer-video', 'composer-success', 'composer-failure', 'model-memory'],
    'chat': ['user-mentions', 'file-preview', 'mcp-files', 'chat-performance', 'chat-stream-performance', 'layout', 'tracking', 'smooth-scroll', 'image-preview', 'markdown', 'duration', 'process-counts', 'process-failed', 'agent-error', 'changes', 'inline-diff', 'chat-chrome'],
}
SUITES = {
    'glass-transitions': ['chat-chrome', 'mention-chat', 'mention-sheet', 'send-queue', 'send-transition', 'send-transition-handoff'],
    'core': ['onboarding', 'inbox', 'navigation', 'send', 'send-handoff', 'composer-success'],
    'core-home': ['onboarding', 'inbox', 'navigation'],
    'core-send': ['send', 'send-handoff', 'composer-success'],
    'send-reliability': ['send-guide', 'outbox', 'queued-message-behavior', 'send-queue', 'send-interrupt', 'send', 'send-handoff', 'send-transition', 'send-transition-handoff'],
}
CORE_SUITES = {name for name in SUITES if name.startswith('core')}
PHONE_CASES = [case for batch in BATCHES.values() for case in batch]
# These lease an iPad. `--case` still accepts them; the default phone run must not.
PAD_CASES = ['ipad', 'ipad-chrome', 'native-shell', 'native-collection']
CASES = PHONE_CASES + PAD_CASES + ['morph', 'composer-relay', 'outbox', 'scroll-edge', 'scroll-edge-pages', 'scroll-edge-diff']
# These select HomePreviewProviders at app launch, using the same shared bundle.
HOME_CASES = {'morph', 'mentions-production', 'home', 'licenses', 'navigation', 'navigation-toolbar', 'project-history-entry', 'ipad', 'ipad-chrome'}
PREVIEW = {
    'scroll-edge': 'chat-preview',
    'scroll-edge-pages': 'scroll-edge-pages',
    'scroll-edge-diff': 'scroll-edge-diff',
    'agent-error': 'agent-error-preview',
    'outbox': 'outbox-preview',
    'composer-relay': 'composer-relay',
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
    'steer': 'steer-preview',
    'send-guide': 'send-guide',
    'send-interrupt': 'send-interrupt',
    'send-rounds': 'send-preview',
    'user-mentions': 'file-preview',
    'file-preview': 'file-preview',
    'mcp-files': 'file-preview',
    'chat-performance': 'chat-performance',
    'chat-stream-performance': 'chat-stream-performance',
    'project-history': 'project-history-preview',
    'project-picker': 'project-picker-preview',
    'settings': 'settings-preview',
    'appearance': 'appearance-preview',
    'queued-message-behavior': 'queued-message-behavior-preview',
    'model-memory': 'model-memory',
    'smooth-scroll': 'scroll-preview',
    'duration': 'permission-preview',
    'process-counts': 'chat-preview',
    'process-failed': 'chat-preview',
    'chat-chrome': 'chat-preview',
    'send': 'send-preview',
    'send-handoff': 'send-handoff',
    'send-handoff-delayed': 'send-handoff-delayed',
    'background': 'background-preview',
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
    'scroll-edge': 'session-input',
    'scroll-edge-pages': 'create-session-input',
    'scroll-edge-diff': 'scroll-edge-diff-toolbar',
    'agent-error': 'error-system:failure:title',
    'outbox': 'outbox-state',
    'composer-relay': 'composer-relay-open',
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
    'steer': 'steer-next',
    'send-guide': 'send-status',
    'send-interrupt': 'send-status',
    'send-rounds': 'send-status',
    'user-mentions': 'file-links:answer',
    'file-preview': 'file-links:answer',
    'mcp-files': 'file-links:answer',
    'project-history': 'history-project:["studio","demo"]',
    'project-picker': 'ui:local:alpha',
    'settings': 'settings-machine',
    'appearance': 'dark-background-soft',
    'queued-message-behavior': 'queued-message-behavior-queue',
    'model-memory': 'create-session-input',
    'send': 'send-status',
    'send-handoff': 'create-session-input',
    'send-handoff-delayed': 'create-session-input',
    'background': 'background-status',
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
selection.add_argument('--suite', choices=SUITES, help='Named case set; core* is the PR regression')
selection.add_argument('--parallel', action='store_true', help='Run all three batches on separate leased Simulators sharing one Metro')
parser.add_argument('--shared-metro', action='store_true', help=argparse.SUPPRESS)
parser.add_argument('--language', choices=['en', 'zh-Hans'], default='en', help='App Language for this run; scenes assert the matching catalog')
parser.add_argument('--appearance', choices=['light', 'dark'], help='One appearance; omit to run light and dark, or light only for --suite core')
parser.add_argument('--fail-fast', action='store_true', help='Stop after the first failed case')
parser.add_argument(
    '--embedded',
    action='store_true',
    help='Use a Release app with an embedded bundle; do not start Metro',
)
parser.add_argument(
    '--require-video',
    action=argparse.BooleanOptionalAction,
    default=None,
    help='Require a captured run.mp4; --suite core defaults to off',
)
args = parser.parse_args()
if args.parallel and (args.udid or args.shared_metro or args.embedded):
    parser.error('--parallel owns three Simulator leases and its Metro; omit --udid, --shared-metro and --embedded')
if args.embedded and args.shared_metro:
    parser.error('--embedded does not start Metro')
args.output = args.output.resolve()
# Stale evidence is replaced in place; only a run needing A/B comparison picks a different --output.
if not args.shared_metro and any((args.output / marker).exists() for marker in ['results.json', 'batches.json', 'environment.json', 'metro.log']):
    shutil.rmtree(args.output)
args.output.mkdir(parents=True, exist_ok=True)
if args.parallel:
    commands = {
        batch: [sys.executable, __file__, '--app', str(args.app.resolve()), '--batch', batch,
                '--output', str(args.output / batch), '--port', str(args.port),
                '--language', args.language, '--shared-metro']
        for batch in BATCHES
    }
    with managed_metro(ROOT, args.port, args.output):
        raise SystemExit(run_batches(commands, args.output))
selected = PHONE_CASES
if args.suite:
    selected = SUITES[args.suite]
elif args.batch:
    selected = BATCHES[args.batch]
elif args.case:
    selected = [args.case]
core_suite = args.suite in CORE_SUITES
if args.appearance:
    appearances = [args.appearance]
elif core_suite:
    appearances = ['light']
else:
    appearances = ['light', 'dark']
if args.fail_fast:
    fail_fast = True
else:
    fail_fast = core_suite
if args.require_video is None:
    require_video = not core_suite
else:
    require_video = args.require_video
if args.udid is None:
    verify_name = f'UI {args.batch}' if args.batch else 'UI'
    if args.suite is not None:
        verify_name = f'UI {args.suite}'
    if args.case is not None:
        verify_name = args.case.replace('-', ' ').title()
    command = [sys.executable, __file__, *sys.argv[1:]]
    device_type = DEVICE_TYPES['ipad'] if args.case in PAD_CASES else DEVICE_TYPES['iphone']
    raise SystemExit(
        run_with_simulator(
            SimulatorPool(device_type=device_type), verify_name, command
        )
    )
def sim(*command, check=True):
    return subprocess.run(['xcrun', 'simctl', *command], check=check, timeout=60, capture_output=True, text=True)

results = []
# Only the parent starts/prewarms/stops Metro; batch workers and embedded apps never own it.
metro_context = nullcontext() if args.shared_metro or args.embedded else managed_metro(ROOT, args.port, args.output)
with metro_context:
    try:
        (args.output / 'environment.json').write_text(json.dumps({
            'node': subprocess.check_output(['node', '--version'], text=True).strip(),
            'batch': args.batch, 'suite': args.suite, 'cases': selected, 'appearances': appearances,
            'failFast': fail_fast, 'requireVideo': require_video, 'embedded': args.embedded,
            'metroPort': None if args.embedded else args.port, 'sharedMetro': args.shared_metro,
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
        cases = sorted(HOME_CASES.intersection(selected)) + [case for case in selected if case not in HOME_CASES]
        launch_mode = None
        app_pid = None
        trace_throw = bool(set(selected).intersection({'send-transition', 'send-transition-handoff', 'send', 'send-handoff', 'send-handoff-delayed', 'send-rounds', 'send-queue', 'steer', 'send-guide', 'ipad-chrome'}))
        for appearance in appearances:
            sim('ui', args.udid, 'appearance', appearance)
            for case in cases:
                output = args.output / appearance / case
                ui = UI(args.udid, output)
                recording = None
                started = time.monotonic()
                result = {'case': case, 'appearance': appearance, 'language': args.language, 'status': 'failed'}
                try:
                    mode = (case in HOME_CASES, case in ('smooth-scroll', 'chat-performance'))
                    if case == 'chat-performance':
                        container = Path(sim('get_app_container', args.udid, 'app.innei.lody', 'data').stdout.strip())
                        (container / 'tmp/lody-chat-loading.json').unlink(missing_ok=True)
                    restart = args.embedded or launch_mode != mode or case in HOME_CASES
                    if restart:
                        result['appLifecycle'] = 'launch'
                        sim('terminate', args.udid, 'app.innei.lody', check=False)
                        launch = ['launch', args.udid, 'app.innei.lody', '--ui-verify']
                        if case in HOME_CASES:
                            launch.append('--ui-verify-home')
                        if case in {'morph', 'mentions-production', 'home', 'ipad', 'ipad-chrome'}:
                            launch.append('--ui-verify-mentions')
                        if mode[1]:
                            launch.append('--ui-verify-scroll')
                        if case == 'navigation-toolbar':
                            launch.append('--ui-verify-opening')
                        if trace_throw:
                            launch.append('--ui-verify-throw')
                        if not args.embedded:
                            launch += [
                                '--initialUrl', f'http://127.0.0.1:{args.port}?disableOnboarding=1',
                                '-expo.devlauncher.hasGrantedNetworkPermission', 'YES',
                                '-EXDevMenuShowsAtLaunch', 'NO',
                                '-EXDevMenuIsOnboardingFinished', 'YES',
                                '-EXDevMenuShowFloatingActionButton', 'NO',
                            ]
                        launch += [
                            '-AppleLanguages', f'({args.language})',
                            '-AppleLocale', 'en_US' if args.language == 'en' else 'zh_CN',
                            '-AppleKeyboards', '(en_US@sw=QWERTY)',
                        ]
                        sim(*launch)
                        launch_mode = mode
                    if require_video:
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
                    if case not in HOME_CASES:
                        # The Debug list is a native UICollectionView; offscreen rows are not in the tree.
                        for _ in range(8):
                            if any(item.get('AXUniqueId') == preview for item in ui.state()):
                                break
                            ui.axe('swipe', '--start-x', '200', '--start-y', '700', '--end-x', '200', '--end-y', '500', '--duration', '0.5', '--post-delay', '0.6')
                        if case == 'agent-error':
                            # UIKit can expose a prefetched row above the transparent header.
                            for _ in range(4):
                                frame = ui.element(preview)['frame']
                                if 140 <= frame['y'] <= 700:
                                    break
                                start, end = ('300', '550') if frame['y'] < 140 else ('650', '400')
                                ui.axe('swipe', '--start-x', '200', '--start-y', start, '--end-x', '200', '--end-y', end, '--duration', '0.5', '--post-delay', '0.6')
                        ui.axe('tap', '--id', preview, '--pre-delay', '0.8', '--post-delay', '0.8', '--tap-style', 'physical')
                    try:
                        ui.element(ready)
                    except AssertionError:
                        if case in ['send-transition', 'send-transition-handoff', 'inbox', 'send', 'send-handoff', 'send-handoff-delayed', 'send-rounds', 'send-queue', 'steer', 'send-guide', 'send-interrupt', 'smooth-scroll'] and any(item.get('AXUniqueId') == preview for item in ui.state()):
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
                    script = Path(__file__).with_name(f'{case}.py') if case in ['pull-request', 'project-history-entry', 'project-history', 'project-picker', 'notifications', 'user-mentions', 'file-preview', 'chat-performance', 'chat-stream-performance', 'settings', 'appearance', 'queued-message-behavior', 'send', 'send-handoff', 'send-rounds', 'send-queue', 'steer', 'send-guide', 'send-interrupt', 'smooth-scroll', 'composer', 'composer-glass', 'composer-video', 'markdown', 'duration', 'process-counts', 'process-failed', 'agent-error', 'changes', 'inline-diff', 'background', 'inbox', 'permission', 'home', 'ipad', 'licenses', 'navigation', 'model-memory', 'onboarding', 'community-notice', 'live-activity', 'chat-chrome'] else CHAT / ('composer.py' if case.startswith('composer-') else f'{case}.py')
                    if case in {'morph', 'native-shell', 'native-collection', 'ipad-chrome', 'composer-relay', 'outbox', 'navigation-toolbar', 'scroll-edge', 'scroll-edge-pages', 'scroll-edge-diff'}:
                        script = Path(__file__).with_name(f'{case}.py')
                    if case == 'send-handoff-delayed':
                        script = Path(__file__).with_name('send-handoff.py')
                    if case in ['fast-chat', 'fast-sheet']:
                        script = Path(__file__).with_name('fast.py')
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
                    if case == 'chat-performance':
                        check_timeout = 480
                    elif case == 'live-activity':
                        # Includes a real 61-second dismissal wait plus lock/unlock
                        # and Dynamic Island transitions; 180s cuts off deep links.
                        check_timeout = 300
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
                    if not args.embedded:
                        diagnose_metro(args.port, output, 'failure')
                    try:
                        native_log = sim('spawn', args.udid, 'log', 'show', '--last', '5m', '--style', 'compact', '--predicate', 'process == "Lody"', check=False)
                        (output / 'native.log').write_text(native_log.stdout + native_log.stderr)
                    except Exception as log_error:
                        result['nativeLogError'] = str(log_error)
                    try:
                        ui.screenshot('failure')
                    except Exception as screenshot_error:
                        result['screenshotError'] = str(screenshot_error)
                    try:
                        (output / 'failure.json').write_text(ui.axe('describe-ui'))
                    except Exception as capture_error:
                        result['captureError'] = str(capture_error)
                    failure_png = output / 'failure.png'
                    if failure_png.exists():
                        failures = args.output / 'failures'
                        failures.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(failure_png, failures / f'{appearance}-{case}.png')
                finally:
                    if recording is not None:
                        recording.send_signal(signal.SIGINT)
                        try:
                            recording.wait(timeout=15)
                        except subprocess.TimeoutExpired:
                            recording.kill()
                            recording.wait()
                        recording.stderr.close()
                    if require_video and recording is not None and (not (output / 'run.mp4').exists() or (output / 'run.mp4').stat().st_size == 0):
                        result['status'] = 'failed'
                        result.setdefault('error', 'Required video was not captured')
                    result['seconds'] = round(time.monotonic() - started, 2)
                    results.append(result)
                    (args.output / 'results.json').write_text(json.dumps(results, indent=2))
                    print(json.dumps(result), flush=True)
                if fail_fast and result['status'] != 'passed':
                    break
            if fail_fast and results and results[-1]['status'] != 'passed':
                break
    finally:
        sim('terminate', args.udid, 'app.innei.lody', check=False)
if not results or any(r['status'] != 'passed' for r in results):
    raise SystemExit(1)
