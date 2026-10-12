"""MCP files open native previews without credentials or an online machine."""
from pathlib import Path
import json
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / 'verification/ui'))
from driver import UI
import catalog

ui = UI(*sys.argv[1:])
container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', ui.udid, 'app.innei.lody', 'data'], text=True).strip())
movie = container / 'Documents/ui-verify-attachment.mp4'
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i',
                'testsrc2=size=320x180:rate=15', '-t', '8', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(movie)], check=True)


def close(video=False, content_state=None, ready_items=None):
    overlay_close = 'QLOverlayDoneButtonAccessibilityIdentifier'
    items = ui.state() if ready_items is None else ready_items
    record = {'video': video, 'contentState': content_state, 'controlsRevealed': False}
    if content_state:
        key = {
            'unavailable': 'native.attachment.error.unavailable',
            'pending': 'native.attachment.error.pending',
            'loading': 'native.attachment.preview.loading',
        }[content_state]
        marker = catalog.text(key)
        assert any(item.get('AXLabel') == marker for item in items), 'Expected attachment status is not displayed'
        # contentUnavailableConfiguration covers the retained Quick Look chrome.
        # Its own central action is visible; the QL overlay can remain in AX.
        matches = [item for item in items if item.get('type') == 'Button' and item.get('enabled')
                   and item.get('AXLabel') == catalog.text('native.close')
                   and item.get('AXUniqueId') != overlay_close]
        assert len(matches) == 1, 'Attachment status must offer exactly one Close action'
        button = matches[0]
        frame = button['frame']
        record.update({'marker': marker, 'label': button['AXLabel'], 'id': button.get('AXUniqueId'),
                       'enabled': button['enabled'], 'frame': frame})
        # A timed loading observation must not replay after its service completed.
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.5', recover=ready_items is None)
    elif video:
        preview = max((item['frame'] for item in items if item.get('AXUniqueId') == 'QLPreviewControllerView'),
                      key=lambda frame: frame['height'])
        # Reveal playback chrome and press its real Close in one HID session.
        # An enabled AX node alone does not establish that auto-hidden chrome
        # remains visible through another process/connection round trip.
        reveal = f"tap -x {preview['x'] + preview['width'] / 2} -y {preview['y'] + preview['height'] / 2}"
        record.update({'controlsRevealed': True, 'id': overlay_close, 'previewFrame': preview,
                       'gesture': 'reveal-video-chrome-then-close'})
        record['gestureOutput'] = ui.axe('batch', '--tap-style', 'physical', '--ax-cache', 'perStep',
                                        '--step', reveal, '--step', 'sleep .2',
                                        '--step', f'tap --id {overlay_close} --post-delay .5')
    else:
        matches = [item for item in items if item.get('type') == 'Button' and item.get('enabled')
                   and item.get('AXUniqueId') == overlay_close]
        assert len(matches) == 1, 'Loaded Quick Look preview must offer exactly one Close action'
        button = matches[0]
        frame = button['frame']
        record.update({'label': button['AXLabel'], 'id': overlay_close,
                       'enabled': button['enabled'], 'frame': frame})
        ui.axe('tap', '-x', str(frame['x'] + frame['width'] / 2), '-y', str(frame['y'] + frame['height'] / 2), '--post-delay', '.5')
    with (ui.output / 'quick-look-close-probes.jsonl').open('a') as log:
        log.write(json.dumps(record) + '\n')
    ui.wait(lambda current: any(item.get('AXUniqueId') == 'mcp-files:text' for item in current)
            and not any(item.get('AXUniqueId') == 'QLPreviewControllerView' for item in current),
            'Closing the preview did not return to MCP attachments')


def loaded():
    ui.element('QLPreviewControllerView')
    ui.wait(lambda items: not any(item.get('AXLabel') == catalog.text('native.attachment.preview.loading') for item in items), 'File loading never finished')
    time.sleep(.8)
    assert not any(item.get('AXLabel') == catalog.text('native.attachment.preview.retry') for item in ui.state()), 'Preview failed to load'


ui.axe('tap', '--label', 'MCP Attachments', '--post-delay', '.5')
for file in ['text', 'pdf', 'video', 'retry', 'missing', 'pending', 'cancel']:
    assert ui.element('mcp-files:' + file)['type'] == 'Button'
ui.capture('files-inline')
for file in ['text', 'pdf', 'video']:
    ui.axe('tap', '--id', 'mcp-files:' + file, '--post-delay', '.2')
    loaded()
    ui.capture(file + '-preview')
    if file == 'video':
        # Quick Look autoplays. Its remote video controls are not exposed to AXe;
        # compare the moving fixture's central pixels, excluding system chrome.
        time.sleep(.8)
        ui.capture('video-playing')
        def frame_hash(name):
            return subprocess.check_output(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(Path(sys.argv[2]) / name),
                '-vf', 'crop=iw:ih/5:0:ih*0.45', '-f', 'framemd5', '-'], text=True).splitlines()[-1]
        assert frame_hash('video-preview.png') != frame_hash('video-playing.png'), 'Video frames did not advance'
    close(video=file == 'video')

ui.axe('tap', '--id', 'mcp-files:retry', '--post-delay', '.2')
ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('native.attachment.error.download') for item in items), 'Download failure was swallowed')
ui.capture('failed-download')
ui.axe('tap', '--label', catalog.text('native.attachment.preview.retry'), '--post-delay', '.2')
loaded()
ui.capture('retry-loaded')
close()
for file in ['missing', 'pending']:
    ui.axe('tap', '--id', 'mcp-files:' + file, '--post-delay', '.2')
    key = 'unavailable' if file == 'missing' else 'pending'
    ui.wait(lambda items: any(item.get('AXLabel') == catalog.text('native.attachment.error.' + key) for item in items), 'Missing file state: ' + file)
    ui.capture(file)
    close(content_state=key)
ui.axe('tap', '--id', 'user-file:attachment:text', '--post-delay', '.2')
loaded()
ui.capture('user-file-preview')
close()
ui.axe('tap', '--id', 'mcp-files:cancel', '--post-delay', '.2')
loading_items = ui.wait(lambda items: items if any(item.get('AXLabel') == catalog.text('native.attachment.preview.loading') for item in items) else None, 'Loading state missing')
# Capture round trips can outlast the four-second service window; close from this readiness observation.
close(content_state='loading', ready_items=loading_items)
# This is an AX observation, not a screenshot of a later loaded preview.
(ui.output / 'loading-readiness.json').write_text(json.dumps(loading_items))
time.sleep(4.5)
assert not any(item.get('AXUniqueId') == 'QLPreviewControllerView' for item in ui.state()), 'Cancelled download reopened the preview'
ui.capture('cancelled')
movie.unlink()
print('PASS: MCP text/PDF/video previews, playback, retry, unavailable/pending states, user attachments and cancelled download')
