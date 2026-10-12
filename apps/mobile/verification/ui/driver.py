"""Small shared AXe helpers; every command is bounded and uses an explicit device."""
import json
import math
import select
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


def empty_accessibility_root(items):
    """XCTest can return a zero-size application stub after a native debugger detaches."""
    if len(items) != 1:
        return False
    root = items[0]
    frame = root.get('frame') or {}
    return (root.get('type') == 'Application' and root.get('children') == []
            and frame.get('width') == 0 and frame.get('height') == 0)


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
        self._text_input_sequence = 0

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
            if len(args) != 2:
                raise ValueError('Ordinary text input requires one complete string')
            return self.paste_text(args[1])
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
        """Paste one complete string, then check the actual field without replay."""
        self.paste_text(text, expected_identifier=identifier)
        got = self.element(identifier).get('AXValue') or ''
        assert got == text, f'Typed text did not commit: {got!r}'

    def _focused_input(self, name):
        """Read public UITextInput focus/selection/caret getters; never change native input."""
        application = next((item for item in self.state() if item.get('type') == 'Application'), None)
        if not application or not application.get('pid'):
            raise RuntimeError('Cannot inspect the focused text input without an application PID')
        expression = '''({ NSMutableArray *q = [NSMutableArray array];
          for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
            if ([scene isKindOfClass:[UIWindowScene class]]) [q addObjectsFromArray:(NSArray *)[scene windows]];
          }
          NSMutableArray *fields = [NSMutableArray array];
          for (NSUInteger i = 0; i < [q count]; i++) {
            UIView *v = q[i];
            if (([v isKindOfClass:[UITextField class]] || [v isKindOfClass:[UITextView class]]) && [v isFirstResponder]) {
              UITextView *input = (UITextView *)v;
              UITextRange *selection = [input selectedTextRange];
              if (selection) {
                auto start = [input offsetFromPosition:[input beginningOfDocument] toPosition:[selection start]];
                auto end = [input offsetFromPosition:[input beginningOfDocument] toPosition:[selection end]];
                UIView *geometryView = [input textInputView];
                auto caret = [geometryView convertRect:[input caretRectForPosition:[selection end]] toView:nil];
                auto selected = [geometryView convertRect:[input firstRectForRange:selection] toView:nil];
                auto frame = [v convertRect:[v bounds] toView:nil];
                CGFloat touchX = fmin(frame.origin.x + frame.size.width - 2,
                  fmax(frame.origin.x + 2, caret.origin.x + caret.size.width + 2));
                CGFloat touchY = caret.origin.y + caret.size.height / 2;
                if (start != end) {
                  touchX = selected.origin.x + selected.size.width / 2;
                  touchY = selected.origin.y + selected.size.height / 2;
                }
                CGPoint touchPoint;
                touchPoint.x = touchX; touchPoint.y = touchY;
                UIView *hit = [[v window] hitTest:touchPoint withEvent:nil];
                BOOL ownsTouch = hit == v || [hit isDescendantOfView:v]
                  || hit == geometryView || [hit isDescendantOfView:geometryView];
                NSString *identifier = [v accessibilityIdentifier] ?: @"";
                for (UIView *parent = [v superview]; identifier.length == 0 && parent; parent = [parent superview]) {
                  identifier = [parent accessibilityIdentifier] ?: @"";
                }
                [fields addObject:@{@"id":identifier, @"class":NSStringFromClass([v class]),
                  @"text":[v valueForKey:@"text"] ?: @"", @"firstResponder":@YES,
                  @"selection":@{@"start":@(start), @"end":@(end)},
                  @"touchOwner":@{@"class":hit ? NSStringFromClass([hit class]) : @"",
                    @"id":[hit accessibilityIdentifier] ?: @"", @"belongsToInput":@(ownsTouch),
                    @"point":@{@"x":@(touchPoint.x), @"y":@(touchPoint.y)}},
                  @"frame":@{@"x":@(frame.origin.x), @"y":@(frame.origin.y), @"width":@(frame.size.width), @"height":@(frame.size.height)},
                  @"selectedFrame":@{@"x":@(selected.origin.x), @"y":@(selected.origin.y), @"width":@(selected.size.width), @"height":@(selected.size.height)},
                  @"caret":@{@"x":@(caret.origin.x), @"y":@(caret.origin.y), @"width":@(caret.size.width), @"height":@(caret.size.height)}}];
              }
            }
            [q addObjectsFromArray:(NSArray *)[v subviews]];
          }
          [@"FOCUSED_INPUT=" stringByAppendingString:[[NSString alloc] initWithData:
            [NSJSONSerialization dataWithJSONObject:fields options:0 error:nil] encoding:NSUTF8StringEncoding]];
        })'''
        started = time.monotonic()
        result = subprocess.run([
            'lldb', '--batch', '-p', str(application['pid']),
            '-o', 'expr -l objc++ -- @import UIKit;',
            '-o', 'expr -l objc++ -O -- ' + expression.replace('\n', ' '), '-o', 'detach',
        ], capture_output=True, text=True, timeout=45)
        (self.output / f'{name}-native.log').write_text(result.stdout + result.stderr)
        result.check_returncode()
        if 'FOCUSED_INPUT=' not in result.stdout:
            raise RuntimeError('Native focus inspection did not return a text input')
        fields = json.loads(result.stdout.rsplit('FOCUSED_INPUT=', 1)[1].splitlines()[0])
        if len(fields) != 1:
            raise RuntimeError(f'Expected one existing focused text input, found {len(fields)}')
        focused = fields[0]
        focused['pid'] = application['pid']
        focused['inspectionSeconds'] = round(time.monotonic() - started, 3)
        return focused

    def paste_text(self, text, *, expected_identifier=None):
        """Use the actual system Paste menu at the existing caret, preserving selection."""
        import catalog
        self._text_input_sequence += 1
        name = f'text-input-{self._text_input_sequence}'
        started = time.monotonic()
        record = {'event': 'system-paste', 'udid': self.udid, 'text': text, 'sequence': self._text_input_sequence}
        if expected_identifier is not None:
            record['expectedIdentifier'] = expected_identifier
        try:
            focused = self._focused_input(name + '-before')
            record['before'] = focused
            if expected_identifier is not None and focused.get('id') != expected_identifier:
                raise RuntimeError(f'The existing focused input does not belong to {expected_identifier!r}: {focused.get("id")!r}')
            frame, caret = focused['frame'], focused['caret']
            if caret['height'] <= 0 or frame['width'] <= 0 or frame['height'] <= 0:
                raise RuntimeError('The existing focused input has no visible caret')
            x = min(frame['x'] + frame['width'] - 2, max(frame['x'] + 2, caret['x'] + caret['width'] + 2))
            y = caret['y'] + caret['height'] / 2
            selected = focused['selectedFrame']
            if focused['selection']['start'] != focused['selection']['end']:
                if selected['width'] <= 0 or selected['height'] <= 0:
                    raise RuntimeError('The existing text selection has no visible rectangle')
                x = selected['x'] + selected['width'] / 2
                y = selected['y'] + selected['height'] / 2
            if not frame['y'] <= y <= frame['y'] + frame['height']:
                raise RuntimeError('The existing caret is outside the focused input')
            record['caretPoint'] = {'x': x, 'y': y}
            native_point = focused['touchOwner']['point']
            if (not math.isclose(native_point['x'], x, rel_tol=0, abs_tol=1e-6)
                    or not math.isclose(native_point['y'], y, rel_tol=0, abs_tol=1e-6)):
                raise RuntimeError('The native hit-test point differs from the caret touch')
            if (focused['selection']['start'] == focused['selection']['end']
                    and not focused['touchOwner']['belongsToInput']):
                raise RuntimeError('The existing caret touch belongs to another view: '
                                   + focused['touchOwner']['class'])
            copied = time.monotonic()
            subprocess.run(['xcrun', 'simctl', 'pbcopy', self.udid], input=text, text=True,
                           capture_output=True, check=True, timeout=30)
            clipboard = subprocess.check_output(['xcrun', 'simctl', 'pbpaste', self.udid], text=True, timeout=30)
            if clipboard != text:
                raise RuntimeError('Simulator clipboard did not preserve the complete text')
            record['clipboardSeconds'] = round(time.monotonic() - copied, 3)
            gesture = time.monotonic()
            def paste_menu(items):
                return max((item for item in items if item.get('AXLabel') == catalog.system('paste')),
                           key=lambda item: item['frame']['width'] * item['frame']['height'], default=None)
            paste = None
            if focused['selection']['start'] != focused['selection']['end']:
                paste = paste_menu(self.state())
                record['menuAction'] = 'existing-menu'
                if not paste:
                    # shortcut: Hidden selected-range menus fail closed. Add a
                    # host-specific GUI gesture only when an actual case needs it.
                    raise RuntimeError('The existing selected range has no visible Paste menu')
            elif (focused['class'] == 'RCTUITextField' and focused['text'] == ''
                  and focused['selection'] == {'start': 0, 'end': 0}):
                self.axe('tap', '-x', str(x), '-y', str(y), '--post-delay', '.5', recover=False)
                record['menuAction'] = 'repeat-caret-tap'
            else:
                self.axe('touch', '-x', str(x), '-y', str(y), '--down', '--up', '--delay', '.8', recover=False)
                record['menuAction'] = 'caret-long-press'
            if not paste:
                paste = self.wait(paste_menu, 'Paste did not appear in the edit menu', timeout=5)
            record['menuSeconds'] = round(time.monotonic() - gesture, 3)
            if focused['text'] or record['menuAction'] == 'repeat-caret-tap':
                current = self._focused_input(name + '-menu')
                record['afterMenu'] = current
                if record['menuAction'] == 'caret-long-press':
                    record['afterLongPress'] = current
                if any(current[key] != focused[key] for key in ['pid', 'id', 'class', 'text', 'selection']):
                    raise RuntimeError('Opening Paste changed the existing focused input or selection')
            frame = paste['frame']
            record['pasteFrame'] = frame
            action = time.monotonic()
            self.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2),
                     '--post-delay', '.5', recover=False)
            if any(item.get('AXLabel') == 'Allow Paste' for item in self.state()):
                self.axe('tap', '--label', 'Allow Paste', '--post-delay', '.5', recover=False)
            record['pasteSeconds'] = round(time.monotonic() - action, 3)
            record['status'] = 'performed'
            return 'Pasted text through the system edit menu'
        except BaseException as error:
            record['status'] = 'failed'
            record['error'] = str(error)
            raise
        finally:
            record['seconds'] = round(time.monotonic() - started, 3)
            with (self.output / 'text-input.jsonl').open('a') as log:
                log.write(json.dumps(record) + '\n')

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
        recovery_requested = False
        recovery_logged = False
        deadline = time.monotonic() + 90
        last = None

        def recovery_event(event, **details):
            record = {'event': event, 'udid': self.udid, 'monotonicSeconds': time.monotonic(), **details}
            with (self.output / 'accessibility-recovery.jsonl').open('a') as log:
                log.write(json.dumps(record) + '\n')

        def walk(node):
            if isinstance(node, dict):
                yield node
                for child in node.get('children', []):
                    yield from walk(child)
            elif isinstance(node, list):
                for child in node:
                    yield from walk(child)
        def describe():
            nonlocal recovery_requested, recovery_logged
            items = list(walk(json.loads(self.axe('describe-ui', timeout=30 if not self._axe_ready else 20))))
            if empty_accessibility_root(items):
                self.invalidate_axe()
                if not recovery_requested:
                    recovery_requested = True
                    recovery_event('empty-root', pid=items[0].get('pid'), frame=items[0]['frame'], restart='requested')
                    restart_accessibility(self.udid)
                raise RuntimeError('Accessibility automation returned an empty application root')
            if recovery_requested and items and not recovery_logged:
                recovery_logged = True
                recovery_event('root-restored', nodes=len(items), pid=items[0].get('pid'))
            return items
        if self._axe_ready:
            try:
                return describe()
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError, json.JSONDecodeError) as error:
                last = error
                self._axe_ready = False
        while time.monotonic() < deadline:
            try:
                items = describe()
                self._axe_ready = True
                return items
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError, json.JSONDecodeError) as error:
                last = error
                time.sleep(2)
        if recovery_requested:
            recovery_event('unresolved', error=str(last))
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
