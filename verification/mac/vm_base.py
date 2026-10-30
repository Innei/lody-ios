from dataclasses import dataclass
import re
import subprocess
import time

from vm_guest import (BASE, GUEST_PASSWORD, GUEST_USER, GUEST_XCODE, IPSW, IPSW_URL, KEY, SHARED, SHARED_XCODE, TART_HOME,
                      VOLUME, XCODE, Guest, exclusive, mount, progress, tart, vms)
from vm_rfb import RFB

ARCHIVES = VOLUME / 'xcode'
RUNTIMES = VOLUME / 'runtimes'
INTEGRITY = [
    'Contents/Developer/usr/bin/xcodebuild',
    'Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest',
    'Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework',
    'Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCUIAutomation.framework',
    'Contents/Developer/Platforms/MacOSX.platform/Developer/Library/PrivateFrameworks/XCTestCore.framework',
    'Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend',
    'Contents/SharedFrameworks/DVTFoundation.framework',
    'Contents/Frameworks/IDEFoundation.framework',
]
SERVICES = [
    ('system', 'com.apple.softwareupdated', 'Software Update checks and downloads'),
    ('system', 'com.apple.mobile.softwareupdated', 'Software Update checks and downloads'),
    ('gui', 'com.apple.SoftwareUpdateNotificationManager', 'Software Update banners'),
    ('system', 'com.apple.backupd', 'Time Machine'),
    ('system', 'com.apple.backupd-helper', 'Time Machine scheduling'),
    ('gui', 'com.apple.corespotlightd', 'Spotlight app indexing; mdutil already stops volume indexing'),
    ('gui', 'com.apple.spotlightknowledged', 'Spotlight knowledge indexing'),
    ('gui', 'com.apple.spotlightknowledged.importer', 'Spotlight knowledge indexing'),
    ('gui', 'com.apple.spotlightknowledged.updater', 'Spotlight knowledge indexing'),
    ('gui', 'com.apple.assistantd', 'Siri'),
    ('gui', 'com.apple.assistant_service', 'Siri'),
    ('gui', 'com.apple.assistant_cdmd', 'Siri'),
    ('gui', 'com.apple.siriactionsd', 'Siri actions'),
    ('gui', 'com.apple.siriinferenced', 'Siri inference'),
    ('gui', 'com.apple.siriknowledged', 'Siri knowledge'),
    ('gui', 'com.apple.sirittsd', 'Siri speech'),
    ('gui', 'com.apple.SiriTTSTrainingAgent', 'Siri speech training'),
    ('gui', 'com.apple.intelligenceplatformd', 'Apple Intelligence'),
    ('gui', 'com.apple.intelligenceflowd', 'Apple Intelligence'),
    ('gui', 'com.apple.intelligencecontextd', 'Apple Intelligence'),
    ('gui', 'com.apple.intelligencetasksd', 'Apple Intelligence'),
    ('gui', 'com.apple.generativeexperiencesd', 'Apple Intelligence'),
    ('gui', 'com.apple.knowledgeconstructiond', 'Apple Intelligence knowledge graph'),
    ('gui', 'com.apple.ModelCatalogAgent', 'Apple Intelligence model catalog'),
    ('system', 'com.apple.modelcatalogd', 'Apple Intelligence model catalog'),
    ('system', 'com.apple.modelmanagerd', 'Apple Intelligence models'),
    ('gui', 'com.apple.mediaanalysisd', 'photo and video analysis'),
    ('gui', 'com.apple.photoanalysisd', 'photo analysis'),
    ('gui', 'com.apple.suggestd', 'Siri Suggestions'),
    ('gui', 'com.apple.tipsd', 'Tips'),
    ('gui', 'com.apple.parsecd', 'Spotlight web suggestions'),
    ('system', 'com.apple.analyticsd', 'analytics submission'),
    ('system', 'com.apple.SubmitDiagInfo', 'diagnostics submission'),
    ('gui', 'com.apple.analyticsagent', 'analytics'),
    ('gui', 'com.apple.cloudd', 'iCloud sync'),
    ('gui', 'com.apple.bird', 'iCloud Drive'),
    ('gui', 'com.apple.cloudphotod', 'iCloud Photos'),
    ('system', 'com.apple.XProtect.daemon.scan', 'background XProtect scans; launch assessment stays on'),
    ('system', 'com.apple.XProtect.daemon.scan.startup', 'background XProtect scans at boot'),
    ('gui', 'com.apple.XProtect.agent.scan', 'background XProtect scans'),
    ('gui', 'com.apple.XProtect.agent.scan.startup', 'background XProtect scans at login'),
    ('gui', 'com.apple.notificationcenterui.agent', 'notification banners over the app under test'),
    ('gui', 'com.apple.gamed', 'Game Center'),
    ('gui', 'com.apple.ScreenTimeAgent', 'Screen Time'),
    ('gui', 'com.apple.UsageTrackingAgent', 'Screen Time usage tracking'),
    ('system', 'com.apple.locationd', 'Location Services'),
]
SCREEN_SHARING = '\n'.join([
    'sudo launchctl enable system/com.apple.screensharing',
    'sudo launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null || true',
    *[f"sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' \"insert or replace into access (service, "
      f"client, client_type, auth_value, auth_reason, auth_version, indirect_object_identifier, flags) values "
      f"('{service}', '{client}', 0, 2, 4, 1, 'UNUSED', 0)\""
      for client in ('com.apple.screensharing.agent', 'com.apple.screensharing.daemon')
      for service in ('kTCCServiceScreenCapture', 'kTCCServicePostEvent', 'kTCCServiceListenEvent')],
])
ACCOUNT = f'''
set -e
echo {GUEST_PASSWORD} | sudo -S sh -c "echo '{GUEST_USER} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/{GUEST_USER}-nopasswd; chmod 440 /etc/sudoers.d/{GUEST_USER}-nopasswd"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qf '{SHARED}/key/id_ed25519.pub' ~/.ssh/authorized_keys 2>/dev/null || cat '{SHARED}/key/id_ed25519.pub' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
'''
SYSTEM = f'''
sudo systemsetup -setsleep Off >/dev/null 2>&1 || true
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0
defaults -currentHost write com.apple.screensaver idleTime 0
sysadminctl -screenLock off -password {GUEST_PASSWORD} 2>/dev/null || true
sudo mdutil -a -i off >/dev/null || true
sudo softwareupdate --schedule off >/dev/null 2>&1 || true
sudo DevToolsSecurity -enable
sudo automationmodetool enable-automationmode-without-authentication
defaults write com.apple.WindowManager StandardHideWidgets -int 1
defaults write com.apple.WindowManager StageManagerHideWidgets -int 1
'''
FIRST_LAUNCH = f'''
[ -f ~/.lody-first-launch ] && exit 0
x='{GUEST_XCODE}'
open -a "$x"
for i in $(seq 120); do pgrep -x Xcode >/dev/null && break; sleep 1; done
sleep 60; pkill -x Xcode || true
open -a "$x/Contents/Developer/Applications/Simulator.app"
for i in $(seq 120); do pgrep -x Simulator >/dev/null && break; sleep 1; done
sleep 90; xcrun simctl shutdown all || true; pkill -x Simulator || true
touch ~/.lody-first-launch
'''
POINTS = {'utilities': (480 / 3360, 28 / 2100), 'terminal': (487 / 3360, 192 / 2100)}


@dataclass
class Integrity:
    broken: list
    quarantined: bool
    sip: str

    @property
    def ok(self):
        return not self.broken and not self.quarantined


def service_commands(services=SERVICES):
    lines = []
    for domain, label, _ in services:
        target = 'system' if domain == 'system' else 'gui/501'
        lines += [f'sudo launchctl disable {target}/{label}', f'sudo launchctl bootout {target}/{label} 2>/dev/null']
    return '\n'.join(lines + ['true'])


def integrity_command(xcode):
    paths = ' '.join(f"'{path}'" for path in INTEGRITY)
    return (f"cd '{xcode}' 2>/dev/null || echo 'BROKEN {xcode}'; "
            f"for item in {paths}; do codesign --verify --strict \"$item\" 2>/dev/null || echo \"BROKEN $item\"; done; "
            f"xattr -p com.apple.quarantine '{xcode}' >/dev/null 2>&1 && echo QUARANTINED; csrutil status")


def integrity(output):
    lines = output.splitlines()
    sip = re.search(r'Protection status: (\w+)', output)
    return Integrity([line[len('BROKEN '):] for line in lines if line.startswith('BROKEN ')],
                     'QUARANTINED' in lines, sip[1] if sip else 'unknown')


def integrity_failure(report):
    problems = report.broken + (['quarantine attribute on Xcode'] if report.quarantined else [])
    return (f'the guest Xcode failed its integrity check ({", ".join(problems)}); '
            'run pnpm verify:mac:vm prepare --repair-xcode')


def point(name, width, height):
    x, y = POINTS[name]
    return round(x * width), round(y * height)


def warm_up(guest, host_xcode=False):
    guest.boot()
    started = time.monotonic()
    xcode = SHARED_XCODE if host_xcode else GUEST_XCODE
    wait = f"for i in $(seq 30); do [ -d '{xcode}' ] && break; sleep 1; done; " if host_xcode else ''
    developer = f"DEVELOPER_DIR='{xcode}/Contents/Developer' " if host_xcode else ''
    result = guest.ssh(f'{wait}{integrity_command(xcode)}; {developer}xcodebuild -version >/dev/null 2>&1 '
                       '|| echo "BROKEN xcodebuild -version"', check=False, timeout=900)
    report = integrity(result.stdout)
    if not report.ok:
        raise SystemExit(integrity_failure(report))
    progress(f'guest Xcode verified and ready after {time.monotonic() - started:.0f}s (SIP {report.sip})')


def archive():
    build = subprocess.run(['/usr/libexec/PlistBuddy', '-c', 'Print ProductBuildVersion',
                            str(XCODE / 'Contents/version.plist')], capture_output=True, text=True, check=True)
    path = ARCHIVES / f'{XCODE.stem}-{build.stdout.strip()}.zip'
    if not path.exists():
        ARCHIVES.mkdir(exist_ok=True)
        progress(f'archiving {XCODE} for the guest')
        partial = path.with_suffix('.partial')
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', '--zlibCompressionLevel', '0',
                        str(XCODE), str(partial)], check=True)
        partial.rename(path)
    return path


def xcode_script(name, repair):
    return f'''
x='{GUEST_XCODE}'
if [ {int(repair)} = 1 ] || ! codesign --verify --strict "$x/Contents/Developer/usr/bin/xcodebuild" 2>/dev/null; then
  sudo rm -rf "$x" ~/.lody-first-launch
  sudo ditto -x -k '{SHARED}/xcode/{name}' /Applications
fi
sudo xattr -dr com.apple.quarantine "$x" 2>/dev/null || true
sudo xcode-select -s "$x"
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
'''


RUNTIME = f'''
version=$(xcrun --sdk iphonesimulator --show-sdk-version)
if ! xcrun simctl list runtimes | grep -q "^iOS $version "; then
  bundle=$(ls -d '{SHARED}/runtimes/'*_"$version"_*.exportedBundle 2>/dev/null | head -1)
  if [ -z "$bundle" ]; then
    xcodebuild -downloadPlatform iOS -buildVersion "$version" -exportPath '{SHARED}/runtimes'
    bundle=$(ls -d '{SHARED}/runtimes/'*_"$version"_*.exportedBundle | head -1)
  fi
  xcodebuild -importPlatform "$bundle"
fi
xcrun simctl list runtimes | grep "^iOS $version "
'''


def step(guest, label, script, timeout=3600):
    started = time.monotonic()
    progress(f'{label}...')
    guest.ssh(script, timeout=timeout)
    progress(f'{label}: {time.monotonic() - started:.0f}s')


def shutdown(guest):
    guest.ssh('sudo shutdown -h now', check=False, timeout=30)
    guest.process.wait(timeout=180)


def install(args, log):
    progress(f'installing macOS from {IPSW.name}')
    tart('create', '--from-ipsw', str(IPSW), '--disk-size', '80', '--disk-format', 'asif', BASE, capture=False)
    tart('set', BASE, '--cpu', str(args.cpu), '--memory', str(args.memory * 1024), '--display', args.display)
    # Provisioning options only take effect on the first boot after creation.
    options = ','.join(['fullName=Lody Verify', f'username={GUEST_USER}', f'password={GUEST_PASSWORD}',
                        'logsInAutomatically=true', 'enablesRemoteLogin=true'])
    guest = Guest(BASE, {'key': f'{KEY.parent}:ro'}, log, extra=[f'--provisioning-opts={options}'])
    try:
        progress('waiting for the first boot to provision the admin account')
        guest.boot(timeout=1200, password=True)
        guest.ssh(ACCOUNT, password=True, timeout=600)
        shutdown(guest)
    finally:
        guest.stop()


def sip_state(log):
    guest = Guest(BASE, {}, log)
    try:
        guest.boot()
        state = integrity(guest.ssh('csrutil status', check=False).stdout).sip
        shutdown(guest)
    finally:
        guest.stop()
    return state


def disable_sip(log):
    guest = Guest(BASE, {}, log, extra=['--recovery'], recovery_vnc=True)
    try:
        password, port = guest.recovery()
        deadline = time.monotonic() + 300
        while True:
            try:
                screen = RFB(port, password)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(2)
        while sum(1 for value in screen.capture().pixels[::4096] if value > 40) < 40:
            if time.monotonic() > deadline:
                raise SystemExit('the recovery boot picker never appeared')
            time.sleep(3)
        time.sleep(5)
        screen.key('right').key('right').key('return')
        time.sleep(45)
        screen.click(*point('utilities', screen.width, screen.height))
        time.sleep(2)
        screen.click(*point('terminal', screen.width, screen.height))
        time.sleep(8)
        screen.type('csrutil disable').key('return')
        time.sleep(5)
        screen.type('y').key('return')
        time.sleep(4)
        screen.type(GUEST_PASSWORD).key('return')
        time.sleep(10)
        screen.capture(VOLUME / 'runs/recovery.png')
        screen.type('halt').key('return')
        screen.close()
        guest.process.wait(timeout=180)
    finally:
        guest.stop()


def configure(args, log):
    name = archive().name
    RUNTIMES.mkdir(exist_ok=True)
    guest = Guest(BASE, {'xcode': f'{ARCHIVES}:ro', 'runtimes': RUNTIMES}, log)
    try:
        guest.expose(args)
        guest.boot()
        step(guest, 'system settings: no sleep or lock, no indexing, automation mode', SYSTEM)
        step(guest, f'Xcode in /Applications/{XCODE.name}', xcode_script(name, args.repair_xcode))
        step(guest, 'iOS Simulator runtime', RUNTIME, timeout=7200)
        step(guest, 'Screen Sharing for the loopback VNC viewer', SCREEN_SHARING)
        step(guest, f'disabling {len(SERVICES)} background services', service_commands())
        step(guest, 'first launch of Xcode and Simulator', FIRST_LAUNCH, timeout=900)
        report = integrity(guest.ssh(integrity_command(GUEST_XCODE), check=False).stdout)
        if not report.ok:
            raise SystemExit(integrity_failure(report))
        progress(f'integrity check passed (SIP {report.sip})')
        shutdown(guest)
    finally:
        guest.stop()


def settle(args, log):
    # One more login lets first-run banners fire in the base, not in every clone.
    guest = Guest(BASE, {}, log)
    try:
        guest.expose(args)
        progress('settling a second login')
        guest.boot()
        guest.ssh('sleep 90; sudo shutdown -h now', check=False, timeout=180)
        guest.process.wait(timeout=180)
    finally:
        guest.stop()


def prepare(args):
    mount()
    TART_HOME.mkdir(exist_ok=True)
    VOLUME.joinpath('runs').mkdir(exist_ok=True)
    ready = VOLUME / 'runs' / f'{BASE}.ready'
    if not IPSW.exists():
        IPSW.parent.mkdir(exist_ok=True)
        progress(f'downloading {IPSW.name}')
        subprocess.run(['curl', '-fL', '-C', '-', '--retry', '5', '-o', str(IPSW), IPSW_URL], check=True)
    if not KEY.exists():
        KEY.parent.mkdir(exist_ok=True)
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'lody-mac-verify', '-f', str(KEY)],
                       check=True)
    with exclusive(), (VOLUME / 'runs/prepare.log').open('w') as log:
        if BASE in vms() and args.force:
            tart('delete', BASE)
        ready.unlink(missing_ok=True)
        if BASE not in vms():
            install(args, log)
        if sip_state(log) != 'disabled':
            if not args.recovery_vnc:
                raise SystemExit('SIP is on in the base. Turning it off boots recovery with Virtualization.framework '
                                 'VNC, which listens on every interface for a few minutes; rerun with --recovery-vnc')
            progress('turning SIP off in recovery')
            disable_sip(log)
            if sip_state(log) != 'disabled':
                raise SystemExit(f'SIP is still on; see {VOLUME / "runs/recovery.png"}')
        configure(args, log)
        settle(args, log)
    ready.touch()
    progress(f'{BASE} is ready')
