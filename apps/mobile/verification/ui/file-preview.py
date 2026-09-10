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
    ui.axe('tap', '--label' if label else '--id', label or 'BackButton', '--post-delay', '.5')

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
# A short, slow edge swipe cancels the native interactive return.
ui.axe('swipe', '--start-x', '2', '--start-y', '430', '--end-x', '75', '--end-y', '430', '--duration', '.8', '--post-delay', '.6')
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
link(1)
title('sample.swift')
source = ui.element('file-source')
assert 'let answer = 42' in (source.get('AXValue') or source.get('AXLabel') or '')
ui.capture('code')
back()
for index, name in [(2, 'photo.png'), (3, 'document.pdf')]:
    link(index)
    ui.element('QLPreviewControllerView')
    time.sleep(.6)
    if not any(str(i.get('AXLabel') or '').lower() in ['done', 'close'] for i in ui.state()):
        ui.axe('tap', '-x', '201', '-y', '430', '--post-delay', '.5')
    ui.capture('quicklook-' + name.split('.')[-1])
    close = ui.wait(lambda items: next((i for i in items if i.get('type') == 'Button' and str(i.get('AXLabel') or '').lower() in ['done', 'close']), None), 'Quick Look has no dismiss action')
    ui.axe('tap', '--label', close['AXLabel'], '--post-delay', '.5')
    title(name)
    back()
    ui.element('file-links:answer')
link(4)
ui.wait(lambda items: any(catalog.text('files.error.notFound') in str(i.get('AXLabel') or '') for i in items), 'Missing-file error was swallowed')
ui.capture('missing-file')
ui.axe('tap', '--label', catalog.text('common.retry'), '--post-delay', '.2')
ui.element('file-loading', timeout=2)
ui.wait(lambda items: any(catalog.text('files.error.notFound') in str(i.get('AXLabel') or '') for i in items), 'Retry lost the missing-file error')
back()
# A late image response must not open Quick Look after leaving its loading page.
link(2)
title('photo.png', timeout=2)
ui.element('file-loading', timeout=2)
back()
time.sleep(5.5)
ui.element('file-links:answer')
assert not any(str(i.get('AXLabel') or '').lower() in ['done', 'close'] for i in ui.state())
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
back(catalog.text('process.title'))
ui.element('file-links:thought')
ui.capture('process-return')
ui.axe('tap', '--label', catalog.text('accessibility.closeSheet', title=catalog.text('process.title')), '--post-delay', '.5')
ui.element('file-links:answer')
print('PASS: files push before slow reads, deselect on return, and ignore late cancelled reads; Markdown/source, relative links, Quick Look, retry and process-sheet navigation work')
