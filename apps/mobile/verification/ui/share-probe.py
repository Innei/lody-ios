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
import signal
import time

from driver import UI

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simulator import SimulatorPool, run_with_simulator


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True)
parser.add_argument('--udid', default=os.environ.get('LODY_VERIFY_UDID'))
parser.add_argument('--output', default='.artifacts/share-probe/ui')
parser.add_argument('--appearance', choices=['light', 'dark'], default='light')
args = parser.parse_args()
if not args.udid:
    raise SystemExit(run_with_simulator(SimulatorPool(), 'Share Probe', [sys.executable, __file__, *sys.argv[1:]]))

app = Path(args.app).resolve()
assert (app / 'PlugIns/LodyShare.appex').is_dir(), 'Build the Share Extension target first'
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
subprocess.run(['xcrun', 'simctl', 'ui', args.udid, 'appearance', args.appearance], check=True)
for bundle in ['app.innei.lody.share', 'app.innei.lody.share-probe-host']:
    subprocess.run(['xcrun', 'simctl', 'spawn', args.udid, 'defaults', 'write', bundle, 'AppleLanguages', '-array', 'en'], check=True)
    subprocess.run(['xcrun', 'simctl', 'spawn', args.udid, 'defaults', 'write', bundle, 'AppleLocale', 'en_US'], check=True)
# The actual containing app is never launched; the system invokes its extension.
subprocess.run(['xcrun', 'simctl', 'terminate', args.udid, 'app.innei.lody'], capture_output=True, timeout=30)
subprocess.run(['xcrun', 'simctl', 'launch', args.udid, 'app.innei.lody.share-probe-host', '-AppleLanguages', '(en)', '-AppleLocale', 'en_US'], check=True, timeout=30)
ui = UI(args.udid, output)
ui.element('share-probe-host.open')
ui.capture('source')
video = subprocess.Popen(['xcrun', 'simctl', 'io', args.udid, 'recordVideo', '--codec=h264', '--force', str(output / 'run.mp4')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
ui.axe('tap', '--id', 'share-probe-host.open', '--tap-style', 'physical', '--post-delay', '1')
ui.capture('share-tray')
items = ui.state()
lody = next((item for item in items if item.get('AXLabel') == 'Lody'), None)
if lody:
    ui.axe('tap', '--label', 'Lody', '--tap-style', 'physical', '--post-delay', '1')
else:
    # iOS 26.5's compact remote share tray exposes only "dismiss popup" to AXe.
    # Fixed iOS 26.5 402x874 fixture; use AX nodes when the remote tray exposes them.
    # Visually confirmed row: Reminders, Lody, More.
    # The extension's own identifiers below must still appear; a missed tap fails.
    root = next(item for item in items if item.get('role') == 'AXApplication')
    assert root['frame']['width'] == 402 and root['frame']['height'] == 874
    assert any(item.get('AXLabel') == 'dismiss popup' for item in items)
    ui.axe('tap', '-x', '156', '-y', '653', '--tap-style', 'physical', '--post-delay', '1')
def flatten(node):
    yield node
    for child in node.get('children', []):
        yield from flatten(child)

try:
    # Remote extension trees are hit-tested, not descendants of the source app.
    # Wait for presentation to settle; an animation-frame screenshot is not proof.
    deadline = time.monotonic() + 30
    while True:
        tree = json.loads(ui.axe('describe-ui', '--point', '200,840'))
        nodes = list(flatten(tree))
        send = next((n for n in nodes if n.get('AXUniqueId') == 'session-send'), None)
        if send and send['frame']['y'] < 830:
            break
        assert time.monotonic() < deadline, 'Extension did not settle'
        time.sleep(.2)
    assert send['enabled'] is False
    assert any('Open Lody and sign in' in (n.get('AXLabel') or '') for n in nodes), 'Missing English login guidance'
    (output / 'extension-points.json').write_text(json.dumps(tree, indent=2))
    ui.capture('extension-signed-out')
    cancel = json.loads(ui.axe('describe-ui', '--point', '38,110'))
    assert cancel.get('AXLabel') in ['Cancel', 'Close'], 'Cancel action missing'
    ui.axe('tap', '-x', '38', '-y', '110', '--tap-style', 'physical', '--post-delay', '1')
    ui.element('share-probe-host.open')
    ui.capture('cancelled')
    print('PASS: real share extension loads with app stopped, English guidance, disabled Send, Cancel returns to source')
    print('NOT VERIFIED: authenticated Cloud creation, machine ACK, live catalog memory budget')
finally:
    video.send_signal(signal.SIGINT)
    video.wait(timeout=20)
