import importlib.util
from pathlib import Path
import os
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time
import unittest


def load(name):
    spec = importlib.util.spec_from_file_location(f'lody_verify_mac_{name}', Path(__file__).parent / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


vnc = load('vm_vnc')
vm = load('vm')
guest = load('vm_guest')
runner = load('vm_runner')
base = load('vm_base')
rfb = load('vm_rfb')


class VncTests(unittest.TestCase):
    def test_reads_the_password_and_port_tart_prints(self):
        log = 'Booting\nVNC server is running at vnc://:bold-tide-mint-oak@127.0.0.1:61234\nmore\n'
        self.assertEqual(vnc.vnc_endpoint(log), ('bold-tide-mint-oak', 61234))
        self.assertIsNone(vnc.vnc_endpoint('Booting\n'))

    def test_the_preferred_port_wins_when_free_and_falls_back_when_busy(self):
        busy = {5905, 5906}
        self.assertEqual(vnc.pick_port(5905, fixed=False, free=lambda port: port not in busy), 5907)
        self.assertEqual(vnc.pick_port(5905, fixed=False, free=lambda port: True), 5905)

    def test_an_explicit_port_never_falls_back(self):
        with self.assertRaises(SystemExit):
            vnc.pick_port(6000, fixed=True, free=lambda port: False)
        self.assertEqual(vnc.pick_port(6000, fixed=True, free=lambda port: True), 6000)

    def test_the_viewing_line_names_the_screen_sharing_login_and_observe_mode(self):
        line = vnc.vnc_line(5905)
        self.assertTrue(line.startswith('VNC: vnc://admin@localhost:5905 '))
        self.assertIn('admin / admin', line)
        self.assertIn('Observe', line)

    def test_the_recovery_vnc_warns_that_it_is_reachable_from_the_lan(self):
        line = vnc.recovery_line('bold-tide-mint-oak', 51702)
        self.assertIn('vnc://:bold-tide-mint-oak@127.0.0.1:51702', line)
        self.assertIn('LAN', line)

    def test_only_loopback_listeners_pass_the_exposure_check(self):
        output = '\n'.join([
            'COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME',
            'Python 10 me 3u IPv4 0x1 0t0 TCP 127.0.0.1:5905 (LISTEN)',
            'Python 10 me 4u IPv6 0x2 0t0 TCP [::1]:5905 (LISTEN)',
            'tart 11 me 9u IPv4 0x3 0t0 TCP *:51702 (LISTEN)',
            'tart 11 me 9u IPv4 0x3 0t0 TCP 192.168.1.4:6000 (LISTEN)',
        ])
        self.assertEqual(vnc.exposed(output), ['tart *:51702', 'tart 192.168.1.4:6000'])
        self.assertEqual(vnc.exposed(''), [])

    def test_arguments_default_to_port_5905_without_holding_or_recovery_vnc(self):
        args = vm.parser.parse_args([])
        self.assertEqual((args.vnc_port, args.hold, args.recovery_vnc, args.repair_xcode, args.host_xcode),
                         (None, False, False, False, False))
        args = vm.parser.parse_args(['--vnc-port', '6100', '--hold'])
        self.assertEqual((args.vnc_port, args.hold), (6100, True))

    def test_a_port_left_in_time_wait_by_the_last_run_counts_as_free(self):
        server = socket.create_server(('127.0.0.1', 0))
        port = server.getsockname()[1]
        client = socket.create_connection(('127.0.0.1', port))
        accepted, _ = server.accept()
        accepted.close()
        time.sleep(0.1)
        client.close()
        server.close()
        self.assertTrue(vnc.port_free(port))

    def test_holding_ends_on_sigterm_and_on_an_inherited_ignored_sigint(self):
        class Running:
            def poll(self):
                return None

        previous = signal.signal(signal.SIGINT, signal.SIG_IGN)
        try:
            for signum in (signal.SIGTERM, signal.SIGINT):
                threading.Timer(0.3, os.kill, (os.getpid(), signum)).start()
                started = time.monotonic()
                vnc.hold(Running())
                self.assertLess(time.monotonic() - started, 5)
        finally:
            signal.signal(signal.SIGINT, previous)

    def test_the_forwarder_relays_bytes_on_loopback_only(self):
        upstream = socket.socket()
        upstream.bind(('127.0.0.1', 0))
        upstream.listen()
        forwarder = vnc.Forwarder(0, upstream.getsockname())
        try:
            self.assertEqual(forwarder.address[0], '127.0.0.1')
            client = socket.create_connection(forwarder.address, timeout=5)
            server, _ = upstream.accept()
            client.sendall(b'RFB 003.008\n')
            self.assertEqual(server.recv(64), b'RFB 003.008\n')
            server.sendall(b'ok')
            self.assertEqual(client.recv(64), b'ok')
            client.close()
            server.close()
        finally:
            forwarder.close()
            upstream.close()


class RunnerTests(unittest.TestCase):
    def test_the_reset_kills_leftovers_without_matching_its_own_shell(self):
        command = runner.reset_command()
        for kill in ['pkill -9 -x Lody', 'pkill -9 -x xctest', '[x]codebuild test-without-building',
                     '[L]odyMacUITests-Runner']:
            self.assertIn(kill, command)
        patterns = re.findall(r'pkill -9 -f "([^"]+)"', command)
        self.assertTrue(patterns)
        for pattern in patterns:
            self.assertIsNone(re.search(pattern, command))

    def test_the_reset_clears_lody_state_and_keeps_xcode_caches(self):
        command = runner.reset_command()
        for part in ['defaults delete app.innei.lody.mac ', 'defaults delete lody.mac.settings.catalog',
                     'Application Support/app.innei.lody.mac', 'Containers/app.innei.lody.mac', '~/run']:
            self.assertIn(part, command)
        for kept in ['Developer', 'com.apple.dt', 'DerivedData', 'XProtect']:
            self.assertNotIn(kept, command)
        self.assertTrue(command.endswith('true'))

    def test_only_a_new_base_an_infrastructure_failure_or_a_reset_recycles_the_runner(self):
        same = dict(exists=True, base=7, recorded=7, infra=None)
        self.assertIsNone(runner.recycle_reason(**same))
        self.assertIn('no runner', runner.recycle_reason(**{**same, 'exists': False}))
        self.assertIn('base', runner.recycle_reason(**{**same, 'recorded': 6}))
        self.assertIn('SSH', runner.recycle_reason(**{**same, 'infra': 'the VM did not accept SSH'}))
        self.assertIn('reset', runner.recycle_reason(**same, requested=True))

    def test_failing_tests_are_not_infrastructure_failures(self):
        self.assertIsNone(runner.infra_failure(65, has_result=True, timed_out=False))
        self.assertIsNone(runner.infra_failure(0, has_result=True, timed_out=False))
        self.assertIn('result bundle', runner.infra_failure(65, has_result=False, timed_out=False))
        self.assertIn('255', runner.infra_failure(255, has_result=True, timed_out=False))
        self.assertIn('timed out', runner.infra_failure(None, has_result=False, timed_out=True))

    def test_a_running_runner_is_attached_only_through_its_keeper(self):
        self.assertEqual(runner.plan(running=True, keeper=True), 'attach')
        self.assertEqual(runner.plan(running=True, keeper=False), 'restart')
        self.assertEqual(runner.plan(running=False, keeper=True), 'start')
        self.assertEqual(runner.plan(running=False, keeper=False), 'start')

    def test_the_runner_stops_after_thirty_idle_minutes(self):
        self.assertEqual(runner.IDLE_SECONDS, 1800)
        self.assertFalse(runner.idle_expired(now=1000 + 1799, last=1000))
        self.assertTrue(runner.idle_expired(now=1000 + 1800, last=1000))

    def test_one_run_holds_the_lock_and_the_next_waits_with_a_notice(self):
        path = Path(tempfile.mkdtemp()) / 'lock'
        notices, entered, release = [], threading.Event(), threading.Event()

        def first():
            with guest.exclusive(path, notices.append):
                entered.set()
                release.wait(5)

        holder = threading.Thread(target=first)
        holder.start()
        entered.wait(5)
        with guest.attempt(path) as free:
            self.assertFalse(free)
        threading.Timer(0.3, release.set).start()
        with guest.exclusive(path, notices.append):
            self.assertEqual(len(notices), 1)
        holder.join()
        self.assertIn('waiting', notices[0])
        with guest.attempt(path) as free:
            self.assertTrue(free)

    def test_clearing_a_shared_directory_keeps_the_directory_the_running_vm_shares(self):
        shared = Path(tempfile.mkdtemp()) / 'out'
        (shared / 'LodyMac.xcresult').mkdir(parents=True)
        (shared / 'test.log').write_text('old')
        inode = shared.stat().st_ino
        runner.clear(shared)
        self.assertEqual(shared.stat().st_ino, inode)
        self.assertEqual(list(shared.iterdir()), [])

    def test_watching_opens_the_runner_with_the_guest_login_on_its_loopback_port(self):
        self.assertEqual(runner.viewer_url(vnc.vnc_line(5907)), 'vnc://admin:admin@localhost:5907')
        with self.assertRaises(SystemExit):
            runner.viewer_url('nothing here')
        self.assertEqual(vm.parser.parse_args(['watch']).command, 'watch')
        self.assertFalse(vm.parser.parse_args(['watch']).print_only)
        self.assertTrue(vm.parser.parse_args(['watch', '--print-only']).print_only)

    def test_runs_reuse_the_runner_unless_fresh_and_reset_is_a_command(self):
        self.assertFalse(vm.parser.parse_args([]).fresh)
        self.assertTrue(vm.parser.parse_args(['--fresh']).fresh)
        self.assertEqual(vm.parser.parse_args(['reset']).command, 'reset')


class BaseTests(unittest.TestCase):
    def test_every_disabled_service_names_its_domain_and_a_reason_once(self):
        labels = [label for _, label, _ in base.SERVICES]
        self.assertEqual(len(labels), len(set(labels)))
        for domain, label, reason in base.SERVICES:
            self.assertIn(domain, ('system', 'gui'))
            self.assertTrue(label.startswith('com.apple.'), label)
            self.assertTrue(reason.strip(), label)

    def test_services_the_runner_needs_are_never_disabled(self):
        needed = ['WindowServer', 'tccd', 'sshd', 'screensharing', 'testmanagerd', 'ReportCrash', 'osanalyticshelper',
                  'mDNSResponder', 'configd', 'syspolicyd', 'xprotectd', 'mobileassetd', 'automationmode', 'cfprefsd',
                  'coreservicesd', 'lsd', 'runningboardd', 'trustd', 'securityd', 'notifyd', 'logd']
        for _, label, _ in base.SERVICES:
            parts = label.lower().split('.')
            for name in needed:
                self.assertNotIn(name.lower(), parts)

    def test_services_are_disabled_and_booted_out_in_their_domain(self):
        script = base.service_commands([('system', 'com.apple.backupd', 'Time Machine'),
                                        ('gui', 'com.apple.gamed', 'Game Center')])
        self.assertIn('sudo launchctl disable system/com.apple.backupd', script)
        self.assertIn('sudo launchctl bootout system/com.apple.backupd', script)
        self.assertIn('sudo launchctl disable gui/501/com.apple.gamed', script)
        self.assertIn('sudo launchctl bootout gui/501/com.apple.gamed', script)

    def test_the_integrity_check_verifies_xcode_signatures_quarantine_and_sip(self):
        command = base.integrity_command('/Applications/Xcode-27.1.0.app')
        for path in ['Contents/Developer/usr/bin/xcodebuild', 'Library/Xcode/Agents/xctest', 'XCTest.framework',
                     'DVTFoundation.framework']:
            self.assertIn(path, command)
        self.assertIn('codesign --verify --strict', command)
        self.assertIn('com.apple.quarantine', command)
        self.assertIn('csrutil status', command)

    @unittest.skipUnless(guest.XCODE.exists(), 'needs the host Xcode')
    def test_the_integrity_check_passes_on_a_healthy_xcode_under_the_guest_shell(self):
        output = subprocess.run(['zsh', '-c', base.integrity_command(str(guest.XCODE))], capture_output=True,
                                text=True, timeout=60).stdout
        report = base.integrity(output)
        self.assertEqual(report.broken, [])
        self.assertIn(report.sip, ('enabled', 'disabled'))

    def test_integrity_output_reports_broken_paths_quarantine_and_sip(self):
        healthy = base.integrity('System Integrity Protection status: disabled.\n')
        self.assertEqual((healthy.broken, healthy.quarantined, healthy.sip), ([], False, 'disabled'))
        self.assertTrue(healthy.ok)
        broken = base.integrity('BROKEN Contents/Developer/usr/bin/xcodebuild\nQUARANTINED\n'
                                'System Integrity Protection status: enabled.\n')
        self.assertEqual(broken.broken, ['Contents/Developer/usr/bin/xcodebuild'])
        self.assertTrue(broken.quarantined)
        self.assertEqual(broken.sip, 'enabled')
        self.assertFalse(broken.ok)
        self.assertIn('--repair-xcode', base.integrity_failure(broken))

    def test_screen_sharing_is_enabled_with_its_capture_and_input_grants(self):
        script = base.SCREEN_SHARING
        self.assertIn('launchctl enable system/com.apple.screensharing', script)
        for client in ['com.apple.screensharing.agent', 'com.apple.screensharing.daemon']:
            self.assertIn(client, script)
        for service in ['kTCCServiceScreenCapture', 'kTCCServicePostEvent', 'kTCCServiceListenEvent']:
            self.assertIn(service, script)

    def test_app_behavior_tests_run_alongside_selected_ui_cases(self):
        command = guest.test_command(['sign-in'])
        self.assertIn('-only-testing:LodyMacTests', command)
        self.assertIn('-only-testing:LodyMacUITests/SignInTests', command)
        self.assertNotIn('-only-testing:LodyMacUITests/SidebarTests', command)

    def test_full_run_includes_both_app_behavior_and_ui_tests(self):
        command = guest.test_command([])
        self.assertIn('-only-testing:LodyMacTests ', command)
        self.assertIn('-only-testing:LodyMacUITests ', command)

    def test_the_host_xcode_fallback_points_the_guest_tools_at_the_share(self):
        self.assertNotIn('DEVELOPER_DIR', guest.test_command(['sign-in']))
        self.assertIn("DEVELOPER_DIR='/Volumes/My Shared Files/Xcode.app/Contents/Developer'",
                      guest.test_command(['sign-in'], host_xcode=True))

    def test_recovery_clicks_scale_with_the_framebuffer(self):
        self.assertEqual(base.point('utilities', 3360, 2100), (480, 28))
        self.assertEqual(base.point('utilities', 1680, 1050), (240, 14))

    def test_macos_account_login_encrypts_both_credentials_and_sends_the_public_key(self):
        prime = (23).to_bytes(4, 'big')
        payload = rfb.ard_credentials('admin', 'admin', prime, (5).to_bytes(2, 'big'), (8).to_bytes(4, 'big'), private=6)
        self.assertEqual(len(payload), 128 + 4)
        self.assertEqual(int.from_bytes(payload[128:], 'big'), pow(5, 6, 23))


class Clock:
    def __init__(self):
        self.now = 0.0

    def time(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class RecoveryTests(unittest.TestCase):
    def test_keys_wait_until_a_lit_screen_has_held_still_for_ten_seconds(self):
        clock = Clock()
        frames = iter([('black', False)] * 5 + [('logo', True)] * 4 + [('picker', True)] * 30)
        found = base.steady(lambda: next(frames), stable=10, timeout=120, now=clock.time, sleep=clock.sleep)
        self.assertEqual(found, 'picker')
        self.assertGreaterEqual(clock.now, 19)

    def test_a_screen_that_never_settles_fails_with_its_step(self):
        clock = Clock()
        counter = iter(range(10_000))
        with self.assertRaises(SystemExit) as failure:
            base.steady(lambda: (str(next(counter)), True), stable=10, timeout=60, now=clock.time,
                        sleep=clock.sleep, step='boot picker')
        self.assertIn('boot picker', str(failure.exception))

    def test_lost_keys_are_resent_until_the_frame_changes(self):
        clock = Clock()
        screen = {'frame': 'picker'}
        presses = []

        def commit():
            presses.append('return')
            if presses.count('return') == 3:
                screen['frame'] = 'recovery'

        attempts = base.advance(lambda: (screen['frame'], True), commit, prime=lambda: presses.append('right'),
                                wait=20, now=clock.time, sleep=clock.sleep)
        self.assertEqual(attempts, 3)
        self.assertEqual(presses, ['right', 'return'] * 3)

    def test_keys_that_never_land_fail_after_three_attempts(self):
        clock = Clock()
        presses = []
        with self.assertRaises(SystemExit) as failure:
            base.advance(lambda: ('picker', True), lambda: presses.append('return'), wait=20, now=clock.time,
                         sleep=clock.sleep, step='Terminal')
        self.assertEqual(len(presses), 3)
        self.assertIn('Terminal', str(failure.exception))

    def test_a_display_that_is_not_drawing_yet_reads_as_an_unlit_frame(self):
        def silent():
            raise TimeoutError('timed out')

        self.assertEqual(base.glance(silent, 100, 50), ('unavailable', False))
        self.assertEqual(base.glance(lambda: bytearray(4 * 100 * 50), 100, 50)[1], False)
        self.assertEqual(base.glance(lambda: bytearray(b'\xff' * 4 * 4096 * 50), 4096, 50)[1], True)

    def test_small_flicker_keeps_the_fingerprint_but_a_new_screen_changes_it(self):
        width, height = 320, 200
        frame = bytearray(width * height * 4)
        flicker = bytearray(frame)
        flicker[(100 * width + 101) * 4:(100 * width + 103) * 4] = b'\xff' * 8
        window = bytearray(frame)
        for y in range(40, 160):
            window[(y * width + 40) * 4:(y * width + 280) * 4] = b'\x80' * 240 * 4
        self.assertEqual(base.fingerprint(frame, width, height), base.fingerprint(flicker, width, height))
        self.assertNotEqual(base.fingerprint(frame, width, height), base.fingerprint(window, width, height))

    def test_the_recovery_app_is_told_apart_from_the_language_chooser_by_its_menu_bar(self):
        width, height = 320, 200
        chooser = bytearray(width * height * 4)
        recovery = bytearray(chooser)
        for y in range(0, 4):
            recovery[y * width * 4:(y + 1) * width * 4] = b'\xe0' * width * 4
        self.assertFalse(base.menu_bar(chooser, width, height))
        self.assertTrue(base.menu_bar(recovery, width, height))

    def test_frames_are_fingerprinted_by_their_samples(self):
        black = bytearray(4 * 100 * 50)
        lit = bytearray(b'\xff' * 4 * 100 * 50)
        self.assertEqual(base.fingerprint(black, 100, 50), base.fingerprint(bytearray(4 * 100 * 50), 100, 50))
        self.assertNotEqual(base.fingerprint(black, 100, 50), base.fingerprint(lit, 100, 50))


if __name__ == '__main__':
    unittest.main()
