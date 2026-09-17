"""Real system share extension smoke check, with no login and no cloud writes.

python3 apps/mobile/verification/ui/share-probe.py --app /path/to/Lody.app
"""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import sys

from driver import UI

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simulator import SimulatorPool, run_with_simulator


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True)
parser.add_argument('--udid', default=os.environ.get('LODY_VERIFY_UDID'))
parser.add_argument('--output', default='.artifacts/share-probe/ui')
args = parser.parse_args()
if not args.udid:
    raise SystemExit(run_with_simulator(SimulatorPool(), 'Share Probe', [sys.executable, __file__, *sys.argv[1:]]))

app = Path(args.app).resolve()
assert (app / 'PlugIns/LodyShareProbe.appex').is_dir(), 'Build with LODY_SHARE_PROBE=1 first'
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
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
subprocess.run(['xcrun', 'simctl', 'install', args.udid, str(app)], check=True, timeout=120)
subprocess.run(['xcrun', 'simctl', 'install', args.udid, str(host)], check=True, timeout=60)
# The actual containing app is never launched; the system invokes its extension.
subprocess.run(['xcrun', 'simctl', 'terminate', args.udid, 'app.innei.lody'], capture_output=True, timeout=30)
subprocess.run(['xcrun', 'simctl', 'launch', args.udid, 'app.innei.lody.share-probe-host'], check=True, timeout=30)
ui = UI(args.udid, output)
ui.capture('source')
ui.element('share-probe-host.open')
ui.axe('tap', '--id', 'share-probe-host.open', '--tap-style', 'physical', '--post-delay', '1')
ui.capture('share-tray')
items = ui.state()
lody = next((item for item in items if item.get('AXLabel') == 'Lody'), None)
if lody:
    ui.axe('tap', '--label', 'Lody', '--tap-style', 'physical', '--post-delay', '1')
else:
    # iOS 26.5's compact remote share tray exposes only "dismiss popup" to AXe.
    # ponytail: fixed iOS 26.5 402x874 fixture; use AX nodes when the remote tray exposes them.
    # Visually confirmed row: Reminders, Lody, More.
    # The extension's own identifiers below must still appear; a missed tap fails.
    root = next(item for item in items if item.get('role') == 'AXApplication')
    assert root['frame']['width'] == 402 and root['frame']['height'] == 874
    assert any(item.get('AXLabel') == 'dismiss popup' for item in items)
    ui.axe('tap', '-x', '156', '-y', '653', '--tap-style', 'physical', '--post-delay', '1')
ui.capture('extension-opened')
# Remote extension children are accessible by screen hit-test, not by walking
# the containing source app. Points come from the visually inspected fixture.
points = {name: json.loads(ui.axe('describe-ui', '--point', coordinate)) for name, coordinate in {
    'message': '200,370', 'status': '200,442', 'send': '50,500', 'cancel': '357,114',
}.items()}
(output / 'extension-points.json').write_text(json.dumps(points, indent=2))
assert 'Sign in to the Lody iOS app first' in (points['status'].get('AXLabel') or ''), 'Unauthenticated extension did not show login guidance'
assert points['message'].get('AXValue') == 'Lody share probe: Please reply with exactly OK.'
assert points['send'].get('AXUniqueId') == 'share-probe.send'
assert points['send'].get('enabled') is False, 'Send must be disabled without app authorization'
ui.capture('extension-signed-out')
assert points['cancel'].get('AXLabel') == 'Cancel'
ui.axe('tap', '-x', '357', '-y', '114', '--tap-style', 'physical', '--post-delay', '1')
ui.wait(lambda items: not any(item.get('AXLabel') == 'dismiss popup' for item in items), 'Cancel did not close the extension')
print('PASS: real system share loads appex with parent app stopped; text ingested; unauthenticated send disabled; cancel closes')
print('NOT VERIFIED: authenticated Cloud creation, machine ACK, extension memory under live catalogs')
