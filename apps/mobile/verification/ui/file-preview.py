"""File links open documents, code and Quick Look, and return to their owning chat."""
import sys
import time
from driver import UI
import catalog
ui = UI(*sys.argv[1:])

def title(name, timeout=30):
    return ui.wait(lambda items: any(i.get('type') == 'Heading' and i.get('AXLabel') == name for i in items), 'Wrong file opened: ' + name, timeout)

def link(index, row='file-links:answer', icon=False):
    frame = ui.element(row)['frame']
    # Five production Markdown paragraphs: 24pt line + 8pt paragraph spacing.
    # Geometry is relative to the current native cell, including inside a sheet.
    ui.axe('tap', '-x', str(frame['x'] + (8 if icon else 55)), '-y', str(frame['y'] + 16 + index * 32), '--post-delay', '.6')

def back(label=None):
    if label:
        ui.axe('tap', '--label', label, '--post-delay', '.5')
        return
    buttons = [i for i in ui.state() if (i.get('AXUniqueId') or '') == 'file-back']
    if buttons:
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

assert ui.element('file-links:answer')['custom_actions'] == ['完整报告', '代码', '图片', 'PDF 文档', '不存在的文件']
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
back()
ui.element('file-links:answer')
link(0, icon=True)
title('report.md')
ui.element('file-document')
ui.wait(lambda items: any('Performance report' in (i.get('AXLabel') or '') for i in items), 'Markdown content missing')
ui.capture('markdown')
ui.axe('tap', '--label', catalog.text('file.source'), '--post-delay', '.4')
source = ui.element('file-source')
assert '# Performance report' in (source.get('AXValue') or source.get('AXLabel') or '')
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
assert 'let answer = 42' in (source.get('AXValue') or source.get('AXLabel') or '')
ui.capture('code')
back()
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
# A late image response must not open Quick Look after leaving its loading page.
link(2)
ui.element('file-loading', timeout=2)
ui.axe('tap', '--label', catalog.text('native.close'), '--post-delay', '.5')
time.sleep(5.5)
ui.element('file-links:answer')
assert not any(str(i.get('AXLabel') or '').lower() in ['done', 'close'] for i in ui.state())
assert not any((i.get('AXUniqueId') or '') == 'QLPreviewControllerView' for i in ui.state()), 'Late image read must not host Quick Look after return'
ui.capture('cancelled-loading')
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
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('process.title')), '--post-delay', '.5')
ui.element('file-links:answer')
print('PASS: files push before slow reads, deselect on return, and ignore late cancelled reads; Markdown/source, relative links, presented Quick Look, retry and process-sheet navigation work')
