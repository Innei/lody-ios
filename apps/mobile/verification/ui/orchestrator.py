"""One owned Metro, optionally serving independent Simulator workers."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.request import Request, urlopen


def diagnose_metro(port, output, phase, metro=None):
    # Never dump headers, manifests, bundle bodies or the process environment.
    probes = []
    for method, path in [('GET', '/status'), ('HEAD', '/?disableOnboarding=1'), ('GET', '/?disableOnboarding=1')]:
        started = time.monotonic()
        probe = {'method': method, 'path': path.split('?')[0]}
        try:
            request = Request(f'http://127.0.0.1:{port}{path}', method=method,
                              headers={'expo-platform': 'ios', 'accept': 'application/expo+json,application/json'})
            with urlopen(request, timeout=10) as response:
                probe['status'] = response.status
                probe['bytes'] = len(response.read())
        except Exception as error:
            probe['error'] = str(error)
        probe['seconds'] = round(time.monotonic() - started, 3)
        probes.append(probe)
    diagnostic = {'phase': phase, 'port': port, 'metroExitCode': metro.poll() if metro else None, 'probes': probes}
    (output / f'metro-{phase}.json').write_text(json.dumps(diagnostic, indent=2))
    print(json.dumps(diagnostic), flush=True)


def stop_process(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGINT)
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()


@contextmanager
def managed_metro(root, port, output):
    # Never attach a verification run to another task's server/bundle.
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=2):
            raise RuntimeError(f'Port {port} is occupied; choose another --port')
    except OSError:
        pass
    with (output / 'metro.log').open('w') as log:
        environment = {
            **os.environ,
            'NODE_OPTIONS': os.environ.get('NODE_OPTIONS', '') + f' --require="{Path(__file__).with_name("metro-diagnostics.cjs")}"',
            'LODY_UI_METRO_DIAGNOSTICS': '1', 'CI': '1', 'EXPO_NO_DOTENV': '1',
            'EXPO_PUBLIC_UI_VERIFY': '1', 'EXPO_PUBLIC_UI_VERIFY_HOME': '0',
            'REACT_NATIVE_PACKAGER_HOSTNAME': '127.0.0.1',
        }
        metro = subprocess.Popen(
            ['pnpm', '--filter', '@lody-ios/mobile', 'exec', 'expo', 'start', '--dev-client', '--host', 'lan', '--port', str(port)],
            cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 90
            while True:
                if metro.poll() is not None:
                    raise RuntimeError('Metro exited; inspect metro.log')
                try:
                    with urlopen(f'http://127.0.0.1:{port}/status', timeout=2) as response:
                        if b'packager-status:running' in response.read():
                            break
                except OSError:
                    pass
                if time.monotonic() > deadline:
                    raise TimeoutError('Metro did not become ready')
                time.sleep(.5)
            diagnose_metro(port, output, 'startup', metro)
            request = Request(f'http://127.0.0.1:{port}/?disableOnboarding=1',
                              headers={'expo-platform': 'ios', 'accept': 'application/expo+json'})
            with urlopen(request, timeout=30) as response:
                manifest = json.load(response)
            with urlopen(manifest['launchAsset']['url'], timeout=90) as response:
                response.read()
            yield
        finally:
            stop_process(metro)


def run_batches(commands, output):
    """Launch all workers before waiting; one failure never cancels a sibling."""
    workers = []
    started = time.monotonic()
    results = []
    try:
        for batch, command in commands.items():
            directory = output / batch
            directory.mkdir(parents=True, exist_ok=True)
            log = (directory / 'worker.log').open('w')
            try:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            except BaseException:
                log.close()
                raise
            workers.append((batch, process, log))
        pending = list(workers)
        while pending:
            for worker in pending[:]:
                batch, process, _ = worker
                code = process.poll()
                if code is not None:
                    result = {'batch': batch, 'exitCode': code, 'seconds': round(time.monotonic() - started, 2)}
                    results.append(result)
                    (output / 'batches.json').write_text(json.dumps(results, indent=2))
                    print(json.dumps(result), flush=True)
                    pending.remove(worker)
            if pending:
                time.sleep(.5)
        cases = []
        for batch in commands:
            path = output / batch / 'results.json'
            if path.exists():
                cases.extend({**case, 'batch': batch} for case in json.loads(path.read_text()))
            else:
                cases.append({'batch': batch, 'status': 'failed', 'error': 'Worker did not produce results.json'})
        (output / 'results.json').write_text(json.dumps(cases, indent=2))
        return int(any(result['exitCode'] != 0 for result in results) or any(case['status'] != 'passed' for case in cases))
    finally:
        for _, process, log in workers:
            try:
                stop_process(process)
            finally:
                log.close()
