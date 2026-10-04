"""File links open documents, code and Quick Look, and return to their owning chat."""
import json
import os
import subprocess
from pathlib import Path
import sys
import time
from driver import UI
import catalog
ui = UI(*sys.argv[1:])
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip()
probe = Path(container) / 'tmp/lody-file-source.json'
def geometry(name):
    value = json.loads(probe.read_text())
    (ui.output / (name + '.probe.json')).write_text(json.dumps(value, indent=2))
    return value

def title(name, timeout=30):
    return ui.wait(lambda items: any(i.get('type') == 'Heading' and i.get('AXLabel') == name for i in items), 'Wrong file opened: ' + name, timeout)

def link(index, row='file-links:answer', icon=False):
    frame = ui.element(row)['frame']
    # Production Markdown paragraphs: 24pt line + 8pt paragraph spacing.
    # Geometry is relative to the current native cell, including inside a sheet.
    ui.axe('tap', '-x', str(frame['x'] + (8 if icon else 55)), '-y', str(frame['y'] + 16 + index * 32), '--post-delay', '.6')

def back(label=None):
    if label:
        ui.axe('tap', '--label', label, '--post-delay', '.5')
        return
    buttons = [i for i in ui.state() if (i.get('AXUniqueId') or '') == 'file-back']
    if buttons:
        assert str(buttons[-1].get('AXLabel') or '').casefold() == catalog.text('native.close').casefold(), buttons[-1]
        frame = buttons[-1]['frame']
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.5')
        return
    ui.axe('tap', '--id', 'BackButton', '--post-delay', '.5')

def dismiss_quicklook():
    frame = ui.element('QLPreviewControllerView')['frame']
    ui.axe(
        'swipe',
        '--start-x', str(frame['x'] + frame['width'] / 2),
        '--start-y', str(max(frame['y'] + 16, 70)),
        '--end-x', str(frame['x'] + frame['width'] / 2),
        '--end-y', str(frame['y'] + min(frame['height'] - 24, 720)),
        '--duration', '.5',
        '--post-delay', '.7',
    )
    if not any((i.get('AXUniqueId') or '') == 'QLPreviewControllerView' for i in ui.state()):
        return
    if any(i.get('AXLabel') == catalog.text('native.close') for i in ui.state()):
        ui.axe('tap', '--label', catalog.text('native.close'), '--post-delay', '.5')
        return
    close = next((i for i in ui.state() if i.get('type') == 'Button' and str(i.get('AXLabel') or '').lower() in ['done', 'close']), None)
    assert close, 'Presented Quick Look must dismiss with a pull-down or Close'
    ui.axe('tap', '--label', close['AXLabel'], '--post-delay', '.5')

assert ui.element('file-links:answer')['custom_actions'] == ['完整报告', '代码', '图片', 'PDF 文档', '不存在的文件', '读取失败']
ui.capture('links')
ui.axe('tap', '--label', 'File Browser', '--post-delay', '.5')
ui.element('entry:report.md')
ui.capture('browser-list')
ui.axe('tap', '--id', 'entry:report.md', '--post-delay', '.2')
title('report.md', timeout=2)
ui.element('file-loading', timeout=2)
ui.capture('browser-loading')
ui.element('file-document')
ui.capture('browser-document')
# A short, slow pull cancels the sheet return.
ui.axe('swipe', '--start-x', '201', '--start-y', '80', '--end-x', '201', '--end-y', '160', '--duration', '.8', '--post-delay', '.6')
title('report.md')
ui.element('file-document')
ui.capture('browser-cancelled-return')
back()
row = ui.element('entry:report.md')
assert 'selected' not in str(row.get('traits') or []).lower(), row
ui.capture('browser-return')
ui.axe('tap', '--id', 'entry:sample.swift', '--post-delay', '.2')
title('sample.swift')
ui.element('file-source')
plain = geometry('browser-code')
shared = ui.element('diff-webview-probe')['AXLabel']
assert plain['line'] == 0 and not plain['highlighted'], plain
ui.axe('swipe', '--start-x', '220', '--start-y', '650', '--end-x', '220', '--end-y', '300', '--duration', '.5', '--post-delay', '.6')
assert geometry('browser-code-scroll')['y'] > plain['y'] + 100
ui.capture('browser-code-scroll')
back()
back()
ui.element('file-links:answer')
link(0, icon=True)
title('report.md')
ui.element('file-document')
ui.wait(lambda items: any('Performance report' in (i.get('AXLabel') or '') for i in items), 'Markdown content missing')
ui.wait(lambda items: any('Ruby: <ruby>Tokyo<rt>toh-kee-oh</rt></ruby>.' in (i.get('AXLabel') or '') for i in items), 'Ruby base text missing from Markdown preview')
ui.capture('markdown')
ui.axe('tap', '--label', catalog.text('file.source'), '--post-delay', '.4')
source = ui.element('file-source')
assert geometry('markdown-source')['sourceMatches']
ui.capture('source')
ui.axe('tap', '--label', catalog.text('file.preview'), '--post-delay', '.4')
ui.element('file-document')
# The document's own relative file link resolves next to docs/report.md.
doc = ui.element('file-document-content')
frame = doc['frame']
ui.axe('tap', '-x', str(frame['x'] + 60), '-y', str(frame['y'] + frame['height'] - 10), '--post-delay', '.5')
title('sample.swift')
ui.element('file-source')
ui.capture('relative-file')
back()
title('report.md')
back()
ui.element('file-links:answer')
ui.wait(lambda items: not any((i.get('AXUniqueId') or '') in ['file-back', 'QLPreviewControllerView'] for i in items), 'File sheet still open after dismiss')
link(1)
title('sample.swift')
source = ui.element('file-source')
ui.wait(lambda _: geometry('code-ready').get('line') == 120, 'Target code did not render')
ui.capture('code')
initial = geometry('code-target')
assert ui.element('diff-webview-probe')['AXLabel'] == shared, 'Source must reuse the parked DOM WebView without navigation'
assert initial['line'] == 120 and initial['highlighted'], initial
assert initial['sourceMatches'] and initial['scriptCount'] == 0, initial
assert initial['coloredTokens'] > 0, initial
assert initial['top'] < initial['targetY'] < initial['bottom'] - initial['targetHeight'], initial
assert initial['contentWidth'] > initial['width'] * 2, initial
assert initial['contentHeight'] > initial['height'] * 2, initial
# Real gestures must move the source in both axes without wrapping it.
ui.axe('swipe', '--start-x', '330', '--start-y', '440', '--end-x', '100', '--end-y', '440', '--duration', '.5', '--post-delay', '.6')
horizontal = geometry('code-horizontal')
assert horizontal['x'] > initial['x'] + 80, horizontal
ui.capture('code-horizontal')
ui.axe('swipe', '--start-x', '220', '--start-y', '650', '--end-x', '220', '--end-y', '300', '--duration', '.5', '--post-delay', '.6')
vertical = geometry('code-vertical')
assert vertical['y'] > initial['y'] + 100, vertical
ui.capture('code-vertical')
for _ in range(8):
    current = geometry('code-bottom')
    if current['y'] + current['bottom'] >= current['contentHeight'] - 2:
        break
    ui.axe('swipe', '--start-x', '220', '--start-y', '700', '--end-x', '220', '--end-y', '240', '--duration', '.25', '--post-delay', '.6')
last = geometry('code-bottom')
assert last['y'] + last['bottom'] >= last['contentHeight'] - 2, last
ui.capture('code-bottom')
# Interactive sheet dismissal must release useOpenFile's in-flight promise.
ui.axe('swipe', '--start-x', '201', '--start-y', '65', '--end-x', '201', '--end-y', '740', '--duration', '.5', '--post-delay', '.7')
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'file-back' for i in items), 'Source sheet did not dismiss')
ui.element('file-links:answer')
link(1)
title('sample.swift', timeout=3)
ui.element('file-source')
ui.wait(lambda _: geometry('code-reopened').get('handle') != initial['handle'], 'Reopened source did not render fresh content')
reopened = geometry('code-reopened')
assert ui.element('diff-webview-probe')['AXLabel'] == shared, 'Reopening source must reuse the same WebView and bundle'
assert reopened['top'] < reopened['targetY'] < reopened['bottom'] - reopened['targetHeight'], reopened
ui.capture('code-reopened')
back()
ui.axe('tap', '--id', 'file-links:process', '--post-delay', '.6')
ui.element('file-links:thought')
time.sleep(.8)
ui.capture('process-links')
link(0, row='file-links:thought')
title('report.md')
ui.element('file-document')
ui.capture('process-document')
ui.axe('tap', '--label', catalog.text('file.source'), '--post-delay', '.4')
ui.element('file-source')
ui.axe('tap', '--label', catalog.text('file.preview'), '--post-delay', '.4')
ui.element('file-document')
back()
ui.element('file-links:thought')
ui.capture('process-return')
link(1, row='file-links:thought')
title('sample.swift')
ui.element('file-source')
nested = geometry('process-code-target')
assert nested['line'] == 120 and nested['highlighted'], nested
assert nested['top'] < nested['targetY'] < nested['bottom'] - nested['targetHeight'], nested
ui.capture('process-code-target')
back()
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('process.title')), '--post-delay', '.5')
ui.element('file-links:answer')
# File and FileDiff must share the same parked renderer, then return to source.
ui.axe('tap', '--label', 'Diff Viewer', '--post-delay', '.5')
ui.element('diff-render-ms')
assert ui.element('diff-webview-probe')['AXLabel'] == shared, 'Diff must reuse the source renderer instance'
ui.capture('shared-diff')
back()
ui.element('file-links:answer')
link(1)
title('sample.swift')
ui.element('file-source')
assert ui.element('diff-webview-probe')['AXLabel'] == shared, 'Source must return without reloading Shiki'
ui.wait(lambda _: geometry('source-after-diff').get('line') == 120, 'Source mode was not restored after diff')
restored = geometry('source-after-diff')
assert restored['highlighted'] and restored['top'] < restored['targetY'] < restored['bottom'] - restored['targetHeight'], restored
ui.capture('source-after-diff')
back()
if os.environ.get('LODY_VERIFY_FILE_SOURCE_ONLY') == '1':
    print('PASS: source preview scrolls in both axes to EOF, highlights and reveals the target line, reopens after swipe dismissal, and works in browser/chat/process hosts')
    sys.exit(0)

for index, name in [(2, 'photo.png'), (3, 'document.pdf')]:
    link(index)
    ui.element('QLPreviewControllerView')
    items = ui.state()
    assert not any((i.get('AXUniqueId') or '') == 'chat-image-preview' for i in items), 'Inline file links must not open ChatImagePreview'
    assert not any(i.get('AXLabel') == catalog.text('native.chat.image.closePreview') for i in items), 'Inline file links must not use the image lightbox'
    ui.capture('quicklook-' + name.split('.')[-1])
    dismiss_quicklook()
    ui.element('file-links:answer')
    assert not any((i.get('AXUniqueId') or '') == 'QLPreviewControllerView' for i in ui.state()), 'Pull-down must dismiss presented Quick Look'
link(4)
ui.wait(lambda items: any(catalog.text('files.error.notFound') in str(i.get('AXLabel') or '') for i in items), 'Missing-file error was swallowed')
ui.capture('missing-file')
ui.axe('tap', '--label', catalog.text('common.retry'), '--post-delay', '.2')
ui.element('file-loading', timeout=2)
ui.wait(lambda items: any(catalog.text('files.error.notFound') in str(i.get('AXLabel') or '') for i in items), 'Retry lost the missing-file error')
back()
# A machine RPC rejection must not claim that the computer is offline.
link(5)
ui.wait(lambda items: any(catalog.text('files.error.read') in str(i.get('AXLabel') or '') for i in items), 'RPC rejection must show a read failure')
assert not any(catalog.text('files.error.offline') in str(i.get('AXLabel') or '') for i in ui.state()), 'RPC rejection was mislabeled as offline'
ui.capture('rpc-read-failure')
back()
# A late image response must not open Quick Look after leaving its loading page.
link(2)
ui.element('file-loading', timeout=2)
ui.axe('tap', '--label', catalog.text('native.close'), '--post-delay', '.5')
time.sleep(5.5)
ui.element('file-links:answer')
assert not any(str(i.get('AXLabel') or '').lower() in ['done', 'close'] for i in ui.state())
assert not any((i.get('AXUniqueId') or '') == 'QLPreviewControllerView' for i in ui.state()), 'Late image read must not host Quick Look after return'
ui.capture('cancelled-loading')
print('PASS: files push before slow reads, deselect on return, and ignore late cancelled reads; Markdown/source, relative links, presented Quick Look, retry and process-sheet navigation work')
