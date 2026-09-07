"""Dynamic inbox groups keep confirmation, live, unread-completed and dated history apart."""
import sys
from driver import UI

HEADERS = (
    '需要你确认',
    '进行中',
    '已完成 · 待查看',
    '今天',
    '昨天',
    '一周内',
    '上个月',
    '更早',
)
ORDER = (
    ('header', '需要你确认'),
    ('row', 'inbox-wait'),
    ('row', 'inbox-awaiting'),
    ('header', '进行中'),
    ('row', 'inbox-live'),
    ('header', '已完成 · 待查看'),
    ('row', 'inbox-unread'),
    ('header', '今天'),
    ('row', 'inbox-today'),
    ('header', '昨天'),
    ('row', 'inbox-yesterday'),
    ('header', '一周内'),
    ('row', 'inbox-week'),
    ('header', '上个月'),
    ('row', 'inbox-month'),
    ('header', '更早'),
    ('row', 'inbox-older'),
)
TITLES = {
    'inbox-wait': '权限确认会话',
    'inbox-awaiting': '完成后等确认',
    'inbox-live': '正在运行的任务',
    'inbox-unread': '刚完成未查看',
    'inbox-today': '今天已读会话',
    'inbox-yesterday': '昨天已读会话',
    'inbox-week': '一周内已读',
    'inbox-month': '上个月已读',
    'inbox-older': '更早的已读',
}
# Conversation rows: title, optional pill, project, time. No status sentence, no chevron.
LABELS = {
    'inbox-wait': ('权限确认会话', '等你确认', 'lody-ios', '刚刚'),
    'inbox-awaiting': ('完成后等确认', '等你确认', 'lody-ios', '刚刚'),
    'inbox-live': ('正在运行的任务', 'lody-ios', '刚刚'),
    'inbox-unread': ('刚完成未查看', 'lody-ios', '1 分钟前'),
}

ui = UI(sys.argv[1], sys.argv[2])


def spoken(item):
    parts = [item.get('AXLabel') or '']
    for child in item.get('children') or []:
        parts.append(child.get('AXLabel') or '')
        for grandchild in child.get('children') or []:
            parts.append(grandchild.get('AXLabel') or '')
    return ' '.join(part for part in parts if part)


def token(item):
    uid = item.get('AXUniqueId') or ''
    if uid in TITLES:
        return ('row', uid)
    label = item.get('AXLabel') or ''
    if item.get('type') == 'Heading' and label in HEADERS:
        return ('header', label)
    return None


seen = []
for _ in range(12):
    visible = []
    for item in ui.state():
        found = token(item)
        if not found:
            continue
        visible.append((found, item))
        if found not in seen:
            seen.append(found)
    visible.sort(key=lambda pair: (pair[1]['frame']['y'], pair[1]['frame']['x']))
    onscreen = [found for found, _ in visible]
    expected = [found for found in ORDER if found in onscreen]
    assert onscreen == expected, (onscreen, expected)
    for found, item in visible:
        if found[0] != 'row':
            continue
        label = spoken(item)
        assert item['frame']['height'] >= 44, (found[1], item['frame'])
        assert TITLES[found[1]] in label, (found[1], label)
        if found[1] in LABELS:
            for part in LABELS[found[1]]:
                assert part in label, (found[1], label)
            assert '进行中' not in label
            assert '等待确认' not in label
    if all(found in seen for found in ORDER):
        break
    ui.axe(
        'swipe',
        '--start-x',
        '200',
        '--start-y',
        '700',
        '--end-x',
        '200',
        '--end-y',
        '240',
        '--duration',
        '.4',
        '--post-delay',
        '.3',
    )
else:
    raise AssertionError(f'Inbox groups were incomplete: {seen}')

assert seen == list(ORDER), seen
assert seen.index(('row', 'inbox-unread')) < seen.index(('header', '今天'))
assert seen.index(('row', 'inbox-awaiting')) < seen.index(('header', '进行中'))
ui.capture('groups')
print('Inbox confirmation, unread-completed and dated history groups passed')
