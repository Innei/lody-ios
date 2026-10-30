import importlib.util
from pathlib import Path
import os
import re
import signal
import socket
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

    def test_the_viewing_line_carries_the_url_and_observe_hint(self):
        line = vnc.vnc_line('bold-tide-mint-oak', 5905)
        self.assertTrue(line.startswith('VNC: vnc://localhost:5905 '))
        self.assertIn('password bold-tide-mint-oak', line)
        self.assertIn('no username', line)
        self.assertIn('vnc.txt', line)
        self.assertIn('Observe', line)

    def test_arguments_default_to_port_5905_without_holding(self):
        args = vm.parser.parse_args([])
        self.assertEqual((args.vnc_port, args.hold), (None, False))
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
        forwarder = vnc.Forwarder(0, upstream.getsockname()[1])
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

    def test_runs_reuse_the_runner_unless_fresh_and_reset_is_a_command(self):
        self.assertFalse(vm.parser.parse_args([]).fresh)
        self.assertTrue(vm.parser.parse_args(['--fresh']).fresh)
        self.assertEqual(vm.parser.parse_args(['reset']).command, 'reset')


if __name__ == '__main__':
    unittest.main()
