"""Small shared AXe helpers; every command is bounded and uses an explicit device."""
import json
import subprocess
import time
from pathlib import Path


class UI:
    def __init__(self, udid, output):
        self.udid, self.output = udid, Path(output)
        self.output.mkdir(parents=True, exist_ok=True)

    def axe(self, *args):
        output = subprocess.check_output(['axe', *args, '--udid', self.udid], text=True, timeout=20)
        if output.startswith('Error:'):
            raise RuntimeError(output)
        return output

    def type_into(self, identifier, text):
        """A Chinese App Language activates the pinyin IME, which holds typed Latin
        fixture text as composition instead of committing it. Switch to the English
        keyboard and retype only when the field disagrees, so a run never toggles a
        keyboard that is already Latin."""
        import catalog
        self.axe('type', text)
        if catalog.LANGUAGE == 'en' or self.element(identifier).get('AXValue') == text:
            return
        self.axe('tap', '--label', catalog.system('nextKeyboard'), '--post-delay', '.6')
        for _ in range(len(text) + 4):
            self.axe('key', '42')
        self.axe('type', text)
        assert self.element(identifier).get('AXValue') == text, 'Typed text did not commit'

    def state(self):
        def walk(node):
            if isinstance(node, dict):
                yield node
                for child in node.get('children', []):
                    yield from walk(child)
            elif isinstance(node, list):
                for child in node:
                    yield from walk(child)
        return list(walk(json.loads(self.axe('describe-ui'))))

    def wait(self, predicate, message, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = predicate(self.state())
            if result:
                return result
            time.sleep(.2)
        raise AssertionError(message)

    def element(self, identifier, timeout=30):
        return self.wait(lambda items: next((i for i in items if i.get('AXUniqueId') == identifier), None),
                         f'Missing {identifier}', timeout)

    def capture(self, name):
        (self.output / f'{name}.json').write_text(self.axe('describe-ui'))
        subprocess.run(['xcrun', 'simctl', 'io', self.udid, 'screenshot', str(self.output / f'{name}.png')], check=True, timeout=20, capture_output=True)
