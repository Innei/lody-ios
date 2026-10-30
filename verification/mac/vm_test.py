import importlib.util
from pathlib import Path
import os
import signal
import socket
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


if __name__ == '__main__':
    unittest.main()
