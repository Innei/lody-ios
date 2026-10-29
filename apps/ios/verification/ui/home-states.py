"""The Design states workspace renders every rail row state on the production Home list."""
import subprocess
import sys
from driver import UI
import catalog

ui = UI(sys.argv[1], sys.argv[2])
home_avatar = catalog.workspace_switch('我的超长工作区名称不能折行')
ui.wait(lambda items: any(i.get('AXLabel') == home_avatar for i in items), 'Missing workspace avatar')
ui.axe('tap', '--label', home_avatar, '--post-delay', '.8')
ui.axe('tap', '--label', 'Design states', '--post-delay', '1.2')

rows = ['st-checklist', 'st-review', 'st-ship', 'st-ship-mac', 'st-ship-fix', 'st-unread', 'st-sync']
for row in rows:
    ui.element(row)
review = ui.element('st-review')['frame']
child = ui.element('st-ship-mac')['frame']
assert child['height'] < review['height'], ('Sub-agent rows are one line', child, review)
assert abs(review['x']) <= 0.5, review


def gap_between(above, below):
    upper = ui.element(above)['frame']
    return ui.element(below)['frame']['y'] - (upper['y'] + upper['height'])


group_gap = gap_between('st-checklist', 'toggle:states:lody-cloud')
project_gap = gap_between('st-bump', 'toggle:states:lody-ios')
assert group_gap >= 24, ('Pinned stands apart from the projects', group_gap)
assert 8 <= project_gap <= 18, ('Projects sit a smaller step apart', project_gap)
assert group_gap > project_gap + 8, ('Gaps follow module size', group_gap, project_gap)
ui.capture('states-top')


def toggle_x(identifier):
    row = ui.element(identifier)['frame']
    ui.screenshot('children-probe')
    path = str(ui.output / 'children-probe.png')
    width = round(ui.state()[0]['frame']['width'])
    pixels = subprocess.check_output([
        'ffmpeg', '-v', 'error', '-i', path, '-vf', f'scale={width}:-1', '-f', 'rawvideo', '-pix_fmt', 'gray', '-',
    ], timeout=20)
    line = round(row['y'] + row['height'] - 16)
    ground = pixels[line * width + 30]
    ink = [x for x in range(60, width - 16) if abs(pixels[line * width + x] - ground) > 40]
    assert ink, ('Line two must draw the sub-agent toggle', identifier)
    return max(ink) - 6, line


def tap_at(point):
    ui.axe('tap', '-x', str(point[0]), '-y', str(point[1]), '--post-delay', '.8')


# A folded parent takes its children's state and may show Review, so the open toggle is located once and reused.
fold_point = toggle_x('st-ship')
tap_at(fold_point)
ui.wait(lambda items: not any(i.get('AXUniqueId') == 'st-ship-mac' for i in items), 'The line-two toggle folds the sub-agents')
assert any(i.get('AXUniqueId') == 'st-ship' for i in ui.state()), 'Folding keeps the parent session on screen'
ui.capture('states-folded')
tap_at(fold_point)
ui.element('st-ship-mac')
ui.axe('swipe', '--start-x', '200', '--start-y', '700', '--end-x', '200', '--end-y', '300', '--duration', '.4', '--post-delay', '.6')
for row in ['st-flaky', 'st-streams', 'st-notes']:
    ui.element(row)
chat_gap = gap_between('st-flaky', 'toggle:chat')
assert chat_gap >= 24, ('Chat stands apart from the projects', chat_gap)
ui.capture('states-bottom')

ui.axe('tap', '--id', 'magnifyingglass', '--post-delay', '.8')
ui.axe('type', 'watermark')
hit = ui.element('st-sync')
spoken = ' '.join([hit.get('AXLabel') or ''] + [child.get('AXLabel') or '' for child in hit.get('children') or []])
assert 'watermark' in spoken, ('A message match shows its snippet', spoken)
assert hit['frame']['height'] > 58, ('The snippet takes a second line', hit['frame'])
ui.capture('states-search')
print('PASS: the Design states workspace shows every rail state, folds sub-agents inline and highlights message search hits.')
