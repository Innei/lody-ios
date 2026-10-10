"""Small shared AXe helpers; every command is bounded and uses an explicit device."""
import json
import select
import shlex
import subprocess
import tempfile
import time
from urllib.parse import urlencode
from pathlib import Path


def axe_session_dead(error):
    """AXe's XCTest session can die mid-run; creating or restoring it is retryable."""
    if isinstance(error, subprocess.TimeoutExpired):
        return True
    message = str(error).casefold()
    return 'remote automation session' in message or 'accessibility automation' in message


def restart_accessibility(udid):
    """A hung describe-ui keeps the simulator accessibility session until that client dies.
    AXe restarts testmanagerd only after a channel disconnect, so a client timeout does it here."""
    try:
        subprocess.run(
            ['xcrun', 'simctl', 'spawn', udid, 'launchctl', 'kickstart', '-k',
             'user/foreground/com.apple.testmanagerd'],
            check=False,
            timeout=8,
            capture_output=True,
        )
    except (subprocess.TimeoutExpired, OSError):
        return


def launch_covered(items, app_pid):
    """describe-ui of another process means SpringBoard covered the launched app."""
    if not app_pid or not items:
        return False
    return not any(str(item.get('pid')) == str(app_pid) for item in items)


def allow_custom_scheme(ui):
    """SpringBoard's first-use scheme alert blocks describe-ui; tap Open without reading the tree."""
    ui.invalidate_axe()
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        for label in ('Open', '打开', '開啟'):
            try:
                ui.axe('tap', '--label', label, '--post-delay', '1', timeout=3, recover=False)
                return
            except subprocess.TimeoutExpired:
                ui.axe('tap', '-x', '280', '-y', '450', '--post-delay', '1', timeout=3, recover=False)
                return
            except (subprocess.CalledProcessError, RuntimeError) as error:
                message = getattr(error, 'output', None) or str(error)
                if 'no accessibility element matched' not in message.casefold():
                    ui.axe('tap', '-x', '280', '-y', '450', '--post-delay', '1', timeout=3, recover=False)
                    return
        time.sleep(0.4)


class UI:
    def __init__(self, udid, output):
        self.udid, self.output = udid, Path(output)
        self.output.mkdir(parents=True, exist_ok=True)
        self._axe_ready = False

    def open_case(self, preview):
        """Enter an offline Debug action without depending on the menu's scroll position."""
        query = urlencode({'verifyCase': preview, 'request': time.monotonic_ns()})
        subprocess.run(['xcrun', 'simctl', 'openurl', self.udid, f'lody:///debug?{query}'],
                       check=True, timeout=30, capture_output=True)

    def invalidate_axe(self):
        """Forget the XCTest session after terminate/relaunch so the next describe retries."""
        self._axe_ready = False

    def axe(self, *args, timeout=20, recover=True):
        if args and args[0] == 'type':
            args = ('batch', '--type-submission', 'composite', '--step', shlex.join(args))
        # AXe's automatic style sends a simulator tapAt, which a focused Lexical input's keyboard session can swallow; fingers are down/up.
        if args and args[0] == 'tap' and '--tap-style' not in args:
            args = (*args, '--tap-style', 'physical')
        deadline = time.monotonic() + (90 if recover else timeout)
        last = None
        while True:
            try:
                bound = 30 if not self._axe_ready else timeout
                output = subprocess.check_output(['axe', *args, '--udid', self.udid], text=True, stderr=subprocess.STDOUT, timeout=bound)
                if output.startswith('Error:'):
                    raise RuntimeError(output.strip())
                self._axe_ready = True
                return output
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError) as error:
                last = error
                if not recover or not axe_session_dead(error) or time.monotonic() >= deadline:
                    raise
                self._axe_ready = False
                if isinstance(error, subprocess.TimeoutExpired):
                    restart_accessibility(self.udid)
                time.sleep(2)

    def type_into(self, identifier, text):
        """Batch input under the runner's shared English keyboard baseline."""
        self.axe('type', text)
        got = self.element(identifier).get('AXValue') or ''
        assert got.casefold() == text.casefold(), f'Typed text did not commit: {got!r}'

    def paste_file(self, identifier):
        return self._paste_provider(identifier, 'file-pasteboard.swift', ['clipboard-fixture.txt'])

    def paste_video(self, identifier):
        return self._paste_provider(identifier, 'video-pasteboard.swift', ['IMG_3933.mov', 'IMG_3933.mp4'])

    def paste_html(self, identifier):
        return self._paste_provider(identifier, 'html-pasteboard.swift', None)

    def _paste_provider(self, identifier, helper, names):
        import catalog
        with tempfile.TemporaryDirectory(prefix='lody-pasteboard-') as output:
            binary = Path(output) / Path(helper).stem
            sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
            subprocess.run([
                'xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-sdk', sdk,
                '-target', 'arm64-apple-ios18.0-simulator',
                str(Path(__file__).with_name(helper)), '-o', str(binary),
            ], check=True, timeout=60)
            provider = subprocess.Popen(
                ['xcrun', 'simctl', 'spawn', self.udid, str(binary)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            try:
                if not select.select([provider.stdout], [], [], 10)[0] or provider.stdout.readline().strip() != 'READY':
                    raise RuntimeError(f'{helper} did not become ready')
                self.axe('tap', '--id', identifier, '--post-delay', '.3')
                frame = self.element(identifier)['frame']
                self.axe('touch', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--down', '--up', '--delay', '.8')
                paste = self.wait(
                    lambda items: max(
                        (item for item in items if item.get('AXLabel') == catalog.system('paste')),
                        key=lambda item: item['frame']['width'] * item['frame']['height'], default=None,
                    ), 'Paste did not appear in the edit menu', timeout=5,
                )
                frame = paste['frame']
                self.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.5')
                if any(item.get('AXLabel') == 'Allow Paste' for item in self.state()):
                    self.axe('tap', '--label', 'Allow Paste', '--post-delay', '.5')
                if names is None:
                    return None
                labels = [catalog.text('native.chat.attachment.preview', name=name) for name in names]
                found = self.wait(
                    lambda items: next((label for label in labels if any(item.get('AXLabel') == label for item in items)), None),
                    'Pasted attachment did not appear',
                )
                return found
            finally:
                provider.terminate()
                try:
                    provider.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    provider.kill()
                    provider.wait()
                provider.stdout.close()
                provider.stderr.close()

    def state(self):
        def walk(node):
            if isinstance(node, dict):
                yield node
                for child in node.get('children', []):
                    yield from walk(child)
            elif isinstance(node, list):
                for child in node:
                    yield from walk(child)
        def describe():
            return list(walk(json.loads(self.axe('describe-ui', timeout=30 if not self._axe_ready else 20))))
        if self._axe_ready:
            try:
                return describe()
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError, json.JSONDecodeError):
                self._axe_ready = False
        deadline = time.monotonic() + 90
        last = None
        while time.monotonic() < deadline:
            try:
                items = describe()
                self._axe_ready = True
                return items
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError, json.JSONDecodeError) as error:
                last = error
                time.sleep(2)
        raise last

    def wait(self, predicate, message, timeout=30):
        deadline = time.monotonic() + timeout
        last = None
        while time.monotonic() < deadline:
            try:
                result = predicate(self.state())
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError, json.JSONDecodeError) as error:
                if not axe_session_dead(error):
                    raise
                last = error
                time.sleep(2)
                continue
            if result:
                return result
            last = None
            time.sleep(.2)
        if last is not None:
            raise last
        raise AssertionError(message)

    def element(self, identifier, timeout=30):
        return self.wait(lambda items: next((i for i in items if i.get('AXUniqueId') == identifier), None),
                         f'Missing {identifier}', timeout)

    def screenshot(self, name):
        """Framebuffer capture that does not depend on AXe remaining responsive."""
        path = self.output / f'{name}.png'
        for attempt in range(2):
            try:
                subprocess.run(
                    ['xcrun', 'simctl', 'io', self.udid, 'screenshot', str(path)],
                    check=True,
                    timeout=20,
                    capture_output=True,
                )
                return path
            except subprocess.TimeoutExpired:
                if attempt:
                    raise

    def capture(self, name):
        self.screenshot(name)
        (self.output / f'{name}.json').write_text(self.axe('describe-ui'))
