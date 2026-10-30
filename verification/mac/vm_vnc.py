"""Watch a verification VM over VNC without touching the host display.

Tart's Virtualization.framework VNC server picks a random port; ``Forwarder``
republishes it on a fixed loopback port so a Screen Sharing bookmark keeps working.
"""
import re
import signal
import socket
import sys
import threading
import time

VNC_PORT = 5905


def vnc_endpoint(log):
    found = re.search(r'VNC server is running at vnc://:([^@\s]+)@127\.0\.0\.1:(\d+)', log)
    return (found[1], int(found[2])) if found else None


def port_free(port):
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind(('127.0.0.1', port))
        except OSError:
            return False
        return True


def pick_port(preferred, fixed, free=port_free):
    candidates = [preferred] if fixed else range(preferred, preferred + 20)
    for port in candidates:
        if free(port):
            return port
    raise SystemExit(f'VNC port {preferred} is in use' if fixed else f'no free VNC port from {preferred}')


def vnc_line(password, port):
    return (f'VNC: vnc://localhost:{port}  password {password} (no username; paste it from vnc.txt). '
            'Screen Sharing → View → Observe keeps your mouse and keyboard out of the run')


def pump(source, target):
    try:
        while data := source.recv(65536):
            target.sendall(data)
    except OSError:
        pass
    finally:
        for end in (source, target):
            try:
                end.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


class Forwarder:
    def __init__(self, port, upstream):
        self.upstream = upstream
        self.server = socket.create_server(('127.0.0.1', port))
        self.address = self.server.getsockname()
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            try:
                client, _ = self.server.accept()
            except OSError:
                return
            try:
                upstream = socket.create_connection(('127.0.0.1', self.upstream))
            except OSError:
                client.close()
                continue
            for source, target in ((client, upstream), (upstream, client)):
                threading.Thread(target=pump, args=(source, target), daemon=True).start()

    def close(self):
        self.server.close()


def hold(process, message='holding the VM for inspection; press Ctrl-C to stop and delete it'):
    print(message, file=sys.stderr, flush=True)

    def interrupt(signum, frame):
        raise KeyboardInterrupt

    # Shells start background jobs with SIGINT ignored, so install the handler rather than rely on the default.
    previous = {signum: signal.signal(signum, interrupt) for signum in (signal.SIGINT, signal.SIGTERM)}
    try:
        while process.poll() is None:
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
