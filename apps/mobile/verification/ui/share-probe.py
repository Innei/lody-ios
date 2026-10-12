"""Real system share sheet check for the Share Extension, with no login and no cloud.

python3 apps/mobile/verification/ui/share-probe.py --app /path/to/Lody.app

Signed out: the extension loads with Lody stopped, explains sign-in and keeps Send
disabled. With a fixture App Group snapshot: the shared text fills the native form,
Send writes one inbox entry carrying the chosen agent, and the prepared offline
containing app comes forward. This does not verify a cold-main or authenticated drain.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import subprocess
import sys
import time

from driver import UI

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simulator import SimulatorPool, run_with_simulator

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True)
parser.add_argument('--udid', default=os.environ.get('LODY_VERIFY_UDID'))
parser.add_argument('--output', default='.artifacts/share-probe/ui')
parser.add_argument('--appearance', choices=['light', 'dark'], default='light')
parser.add_argument('--branches', action='store_true', help='Exercise cached GitHub branch selection and missing-cache handoff')
parser.add_argument('--run-options', action='store_true', help='Exercise cached Role/MCP selections and local worktree in the real Share Extension')
args = parser.parse_args()
if not args.udid:
    raise SystemExit(run_with_simulator(SimulatorPool(), 'Share Probe', [sys.executable, __file__, *sys.argv[1:]]))

app = Path(args.app).resolve()
assert (app / 'PlugIns/LodyShare.appex').is_dir(), 'Build the Share Extension target first'
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)


def sim(*command, **kwargs):
    return subprocess.run(['xcrun', 'simctl', *command], check=True, timeout=120, **kwargs)


host = output / 'ShareProbeHost.app'
host.mkdir(exist_ok=True)
(host / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'app.innei.lody.share-probe-host',
    'CFBundleExecutable': 'ShareProbeHost',
    'CFBundleName': 'ShareProbeHost',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '1.0',
    'CFBundleVersion': '1',
    'MinimumOSVersion': '26.0',
    'LSRequiresIPhoneOS': True,
    'UIDeviceFamily': [1],
    'UILaunchScreen': {},
    'UIApplicationSceneManifest': {
        'UIApplicationSupportsMultipleScenes': False,
        'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{
            'UISceneConfigurationName': 'Share Source',
            'UISceneDelegateClassName': 'ShareProbeHost.ShareProbeHostScene',
        }]},
    },
}))
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
subprocess.run([
    'xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-swift-version', '6', '-parse-as-library', '-module-name', 'ShareProbeHost',
    '-sdk', sdk, '-target', f'{arch}-apple-ios26.0-simulator',
    str(Path(__file__).with_name('share-probe-host.swift')), '-o', str(host / 'ShareProbeHost'),
], check=True, timeout=120)
subprocess.run(['codesign', '--force', '--sign', '-', str(host)], check=True, timeout=30)
sim('install', args.udid, str(app))
sim('install', args.udid, str(host))
sim('ui', args.udid, 'appearance', args.appearance)
for bundle in ['app.innei.lody', 'app.innei.lody.share', 'app.innei.lody.share-probe-host']:
    sim('spawn', args.udid, 'defaults', 'write', bundle, 'AppleLanguages', '-array', 'en')
    sim('spawn', args.udid, 'defaults', 'write', bundle, 'AppleLocale', 'en_US')
group = Path(subprocess.check_output(
    ['xcrun', 'simctl', 'get_app_container', args.udid, 'app.innei.lody', 'group.app.innei.lody'], text=True).strip())
store = group / 'Library/LodyShare'
ui = UI(args.udid, output)


def flatten(node):
    yield node
    for child in node.get('children', []):
        yield from flatten(child)


def open_extension(name, containing_app_stopped=True):
    # Signed-out entry proves that the system hosts the extension with Lody stopped.
    # Cached handoff leaves the explicitly prepared offline main process backgrounded.
    if containing_app_stopped:
        subprocess.run(['xcrun', 'simctl', 'terminate', args.udid, 'app.innei.lody'], capture_output=True, timeout=30)
    subprocess.run(['xcrun', 'simctl', 'terminate', args.udid, 'app.innei.lody.share-probe-host'], capture_output=True, timeout=30)
    sim('launch', args.udid, 'app.innei.lody.share-probe-host', '-AppleLanguages', '(en)', '-AppleLocale', 'en_US')
    ui.element('share-probe-host.open')
    ui.axe('tap', '--id', 'share-probe-host.open', '--tap-style', 'physical', '--post-delay', '1')
    ui.wait(lambda items: any(item.get('AXLabel') in ['Lody', 'dismiss popup'] for item in items), 'System share tray did not appear')
    ui.capture(f'{name}-tray')
    items = ui.state()
    if any(item.get('AXLabel') == 'Lody' for item in items):
        ui.axe('tap', '--label', 'Lody', '--tap-style', 'physical', '--post-delay', '1')
    else:
        # iOS 26.5's compact remote tray exposes only "dismiss popup" to AXe. Visually
        # confirmed 402x874 row: Reminders, Lody, More. A missed tap fails below.
        root = next(item for item in items if item.get('role') == 'AXApplication')
        assert root['frame']['width'] == 402 and root['frame']['height'] == 874
        ui.axe('tap', '-x', '156', '-y', '653', '--tap-style', 'physical', '--post-delay', '1')
    # Remote extension trees are hit-tested, not descendants of the source app.
    deadline = time.monotonic() + 30
    retried_tray = False
    while True:
        send = find_send()
        if send and send['frame']['y'] < 830:
            return send
        if not retried_tray and time.monotonic() > deadline - 25:
            items = ui.state()
            if any(item.get('AXLabel') in ['Lody', 'dismiss popup'] for item in items):
                ui.axe('tap', '-x', '156', '-y', '653', '--tap-style', 'physical', '--post-delay', '1')
            retried_tray = True
        if time.monotonic() >= deadline:
            ui.capture(f'{name}-unsettled')
            log = subprocess.run(['xcrun', 'simctl', 'spawn', args.udid, 'log', 'show', '--last', '2m', '--style', 'compact',
                '--predicate', 'process == "LodyShare" OR (eventMessage CONTAINS "LodyShare")'], capture_output=True, text=True, timeout=120)
            (output / f'{name}-extension.log').write_text(log.stdout)
            raise AssertionError('Extension did not settle')
        time.sleep(.2)


SEND_POINTS = ['362,808', '362,790', '200,808']


def find_send():
    for point in SEND_POINTS:
        nodes = list(flatten(json.loads(ui.axe('describe-ui', '--point', point))))
        send = next((n for n in nodes if n.get('AXUniqueId') == 'session-send'), None)
        if send:
            return send
    return None


def labels_at(*points):
    return [n.get('AXLabel') or '' for point in points for n in flatten(json.loads(ui.axe('describe-ui', '--point', point)))]


def remote(identifier):
    deadline = time.monotonic() + 15
    nodes = []
    while time.monotonic() < deadline:
        for point in ['200,244', '200,320', '350,320', '200,440', '350,440', '200,580', '200,680', '200,740', '200,150']:
            nodes = list(flatten(json.loads(ui.axe('describe-ui', '--point', point))))
            item = next((n for n in nodes if n.get('AXUniqueId') == identifier), None)
            if item:
                (output / ('remote-' + identifier.replace(':', '-') + '.json')).write_text(json.dumps(nodes, indent=2))
                return item
    (output / ('missing-' + identifier.replace(':', '-') + '.json')).write_text(json.dumps(nodes, indent=2))
    ui.capture('missing-remote-element')
    raise AssertionError('Missing remote extension element: ' + identifier)


def remote_tap(identifier):
    frame = remote(identifier)['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.4')


def remote_back():
    nodes = list(flatten(json.loads(ui.axe('describe-ui', '--point', '30,112'))))
    button = next(n for n in nodes if n.get('type') == 'Button' and n.get('AXLabel') in ['Back', 'New Session'])
    frame = button['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.4')


def dismiss_prior_permission_sheet():
    items = ui.state()
    if any(item.get('type') == 'Sheet' and 'Lody' in (item.get('AXLabel') or '')
           and 'Notifications' in (item.get('AXLabel') or '') for item in items):
        # A previously diagnosed failed probe can leave its permission sheet visible.
        # Deny that exact stale dialog; the offline launch itself does not request one.
        ui.axe('tap', '--label', 'Don’t Allow', '--post-delay', '.4')
        return True
    return False


def prepare_offline_main():
    # A system cold URL launch cannot carry ProcessInfo arguments. Reuse the suite's
    # explicit offline launch before returning to the real cached Share form.
    launch = ['launch', '--terminate-running-process', args.udid, 'app.innei.lody', '--ui-verify',
              '-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-AppleKeyboards', '(en_US@sw=QWERTY)']
    started = time.monotonic()
    result = sim(*launch, capture_output=True, text=True)
    ui.invalidate_axe()
    cleared_prompt = dismiss_prior_permission_sheet()
    ui.element('ui-verify-ready', timeout=90)
    ui.capture('prepared-offline-main')
    (output / 'main-baseline.json').write_text(json.dumps({
        'command': ['xcrun', 'simctl', *launch], 'stdout': result.stdout, 'stderr': result.stderr,
        'elapsedSeconds': round(time.monotonic() - started, 3), 'clearedPriorPermissionSheet': cleared_prompt or cleared_initial_prompt,
        'readiness': 'ui-verify-ready', 'handoff': 'cold-extension entry + prepared-offline-main foreground handoff',
        'coldMainVerified': False, 'authenticatedDrainVerified': False,
    }, indent=2))


video = subprocess.Popen(['xcrun', 'simctl', 'io', args.udid, 'recordVideo', '--codec=h264', '--force', str(output / 'run.mp4')],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    cleared_initial_prompt = dismiss_prior_permission_sheet()
    shutil.rmtree(store, ignore_errors=True)
    send = open_extension('signed-out')
    assert send['enabled'] is False, 'Send must stay disabled without a snapshot'
    ui.capture('signed-out')
    assert any('sign in' in label for label in labels_at('200,300', '200,760')), 'Missing sign-in guidance'
    close = next((n for n in flatten(json.loads(ui.axe('describe-ui', '--point', '362,112'))) if n.get('AXLabel') == 'Close New Session'), None)
    assert close, 'Close button missing'
    ui.axe('tap', '-x', '362', '-y', '112', '--tap-style', 'physical', '--post-delay', '1')
    ui.element('share-probe-host.open')

    prepare_offline_main()
    (store / 'options').mkdir(parents=True)
    project = {'id': 'ui:local:alpha', 'machineId': 'ui', 'name': 'Alpha', 'rootPath': '/tmp/alpha'}
    if args.branches:
        project = {'id': 'github:Owner/Repo', 'machineId': '', 'name': 'Owner/Repo', 'rootPath': ''}
        (store / 'branches').mkdir()
        (store / 'branches' / 'Owner%2FRepo.json').write_text(json.dumps({
            'names': ['trunk', 'feature/cached'], 'defaultBranch': 'trunk', 'nextPage': 2,
        }))
    (store / 'catalog.json').write_text(json.dumps({'userId': 'probe-user', 'workspaceId': 'probe-ws', 'projects': [project], 'machineNames': {'ui': 'Fixture Mac'}}))
    options = {'sessionId': 'cached', 'project': project, 'agents': [{'id': 'agent', 'name': 'Fixture Agent', 'machineId': 'ui', 'machineName': 'Fixture Mac', 'cliType': 'builtin', 'agentType': 'codex'}],
        'capabilities': [{'machineId': 'ui', 'cliType': 'builtin', 'agentType': 'codex', 'models': [{'id': 'a', 'name': 'Model A'}], 'modes': [], 'reasoningEfforts': {}}]}
    if args.run_options:
        options['capabilities'][0]['modes'] = [{'id': 'read-only', 'name': 'Read Only'}, {'id': 'agent-full-access', 'name': 'Full Access'}]
        options['runOptions'] = {
            'roles': [{'id': 'reviewer', 'name': 'Reviewer', 'agentName': 'Fixture Agent', 'machineId': 'ui', 'agentConfigId': 'agent',
                'revision': 3, 'available': True, 'runConfig': {'modelId': 'a', 'modeId': 'read-only'}}],
            'mcpServers': [{'id': 'docs', 'name': 'Documentation', 'transport': 'stdio', 'enabledByDefault': True},
                {'id': 'browser', 'name': 'Browser', 'transport': 'http', 'enabledByDefault': False}],
            'worktreeAvailable': not args.branches,
        }
    from urllib.parse import quote
    for target in ['chat', quote(project['id'], safe='')]:
        (store / 'options' / f'{target}.json').write_text(json.dumps(options))
    send = open_extension('ready', containing_app_stopped=False)
    deadline = time.monotonic() + 10
    while not send['enabled']:
        assert time.monotonic() < deadline, 'Send stayed disabled with a ready snapshot'
        time.sleep(.3)
        send = find_send() or send
    ui.capture('ready')
    if args.run_options:
        remote_tap('role')
        remote('reviewer')
        ui.capture('share-run-options-role-picker')
        remote_tap('reviewer')
        assert 'Reviewer' in str(remote('role')), 'Share form lost the Role selection'
        ui.capture('share-run-options-role-applied')
        remote_tap('role')
        remote_tap('lody:role:none')
        assert 'Reviewer' not in str(remote('role')) and 'Model A' in str(remote('model')), 'Explicit None must preserve pinned model values'
        ui.capture('share-run-options-role-cleared')
        remote_tap('role')
        remote_tap('reviewer')
        if not args.branches:
            remote_tap('worktree')
            remote('worktree')
            ui.capture('share-run-options-worktree-picker')
            remote_tap('worktree')
            assert 'New worktree' in str(remote('worktree')), 'Remote worktree choice missing'
        remote_tap('mcp')
        remote_tap('docs:toggle')
        remote_tap('browser:toggle')
        assert str(remote('docs:toggle').get('AXValue')) == '0' and str(remote('browser:toggle').get('AXValue')) == '1', 'MCP toggles did not update independently'
        ui.capture('share-run-options-mcp')
        remote_back()
        mcp_labels = [value for node in flatten(remote('mcp')) for value in [node.get('AXLabel'), node.get('AXValue')] if isinstance(value, str)]
        assert '1 enabled' in mcp_labels and not any('{{count}}' in label for label in mcp_labels), 'MCP count must show the exact numeric selection'
        ui.capture('share-run-options-selected')
        send = find_send()
        assert send and send['enabled'], 'Valid cached run selections must allow Share handoff'
    if args.branches:
        assert 'trunk' in str(remote('branch')), 'Cached default must be chosen in the extension'
        remote_tap('branch')
        remote('branch:trunk')
        remote('branches-cached')
        ui.capture('cached-branches')
        remote_tap('list-search')
        ui.axe('type', 'cached')
        assert (remote('list-search').get('AXValue') or '').casefold() == 'cached', 'Search lost characters while refreshing'
        remote('branch:feature/cached')
        ui.capture('cached-search')
        remote_tap('branch:feature/cached')
        assert 'feature/cached' in str(remote('branch'))
        ui.capture('cached-selected')
        send = find_send()
        assert send and send['enabled']
    frame = send['frame']
    ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '3')
    entries = [json.loads((entry / 'manifest.json').read_text()) for entry in (store / 'inbox').iterdir()]
    assert len(entries) == 1, f'Expected one inbox entry, found {len(entries)}'
    entry = entries[0]
    assert 'Lody share probe' in entry['text'], 'Shared text must reach the manifest'
    assert entry['draft']['agent']['id'] == 'agent' and entry['draft']['sessionId'] != 'cached', 'Draft must carry the agent and a fresh session id'
    if args.branches:
        assert entry['draft']['branch'] == 'feature/cached', 'Selected branch must reach the inbox draft'
    if args.run_options:
        choice = entry['draft']['choice']
        assert choice['agentRoleId'] == 'reviewer' and choice['agentRoleRevision'] == 3, 'Role provenance must reach the Share inbox'
        assert choice['frozenRole'] == {'modelId': 'a', 'modeId': 'read-only'}, 'Share must preserve the selected frozen run values'
        assert choice['mcpServerIds'] == ['browser'], 'Share must preserve the exact per-turn MCP ids'
        assert bool(entry['draft'].get('useWorktree')) == (not args.branches), 'Worktree belongs only to the local project selection'
    (output / 'manifest.json').write_text(json.dumps(entry, indent=2))
    deadline = time.monotonic() + 12
    while any(item.get('AXUniqueId') == 'share-probe-host.open' for item in ui.state()):
        if time.monotonic() >= deadline:
            ui.capture('handoff-missing')
            log = subprocess.run(['xcrun', 'simctl', 'spawn', args.udid, 'log', 'show', '--last', '2m', '--style', 'compact',
                '--predicate', 'process == "LodyShare" OR eventMessage CONTAINS[c] "lody" OR eventMessage CONTAINS[c] "openURL"'], capture_output=True, text=True, timeout=120)
            (output / 'handoff-extension.log').write_text(log.stdout)
            raise AssertionError('Lody did not come forward')
        time.sleep(.5)
    try:
        ui.wait(lambda items: any(item.get('AXLabel') == 'Lody' and item.get('type') == 'Application' for item in items)
                and any(item.get('type') in ['Button', 'TextInput', 'TextView'] and (item.get('AXLabel') or item.get('AXUniqueId')) for item in items),
                'Lody UI did not settle after the Share handoff', timeout=30)
    except AssertionError:
        ui.capture('handoff-not-ready')
        log = subprocess.run(['xcrun', 'simctl', 'spawn', args.udid, 'log', 'show', '--last', '2m', '--style', 'compact',
            '--predicate', 'process == "Lody"'], capture_output=True, text=True, timeout=60)
        (output / 'handoff-native.log').write_text(log.stdout)
        raise
    ui.capture('handoff')
    if args.branches:
        shutil.rmtree(store / 'branches')
        shutil.rmtree(store / 'inbox', ignore_errors=True)
        send = open_extension('missing-cache')
        remote_tap('branch')
        remote('branches-cached')
        ui.capture('missing-cache')
        # Back belongs to the remote extension's own navigation stack.
        nodes = list(flatten(json.loads(ui.axe('describe-ui', '--point', '30,112'))))
        button = next(n for n in nodes if n.get('type') == 'Button' and n.get('AXLabel') in ['Back', 'New Session'])
        frame = button['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '.6')
        send = find_send()
        assert send and send['enabled'], 'No branch cache must still allow handoff to the app'
        frame = send['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--tap-style', 'physical', '--post-delay', '3')
        entries = [json.loads((entry / 'manifest.json').read_text()) for entry in (store / 'inbox').iterdir()]
        assert len(entries) == 1 and entries[0].get('draft') is None and 'Lody share probe' in entries[0]['text'], 'Missing branch must preserve text and defer resolution'
        (output / 'unresolved-manifest.json').write_text(json.dumps(entries[0], indent=2))
    print('PASS: cold-extension signed-out guidance, cached snapshot form, inbox entry written, prepared offline-main foreground handoff')
    print('NOT VERIFIED: cold-main URL launch or authenticated drain into the outbox; domain checks are separate and no signed-in device run was performed')
finally:
    video.send_signal(signal.SIGINT)
    video.wait(timeout=20)
    shutil.rmtree(store, ignore_errors=True)
