import { NativeGroupedList } from '@lody-ios/kit';
import { View as RNView } from 'react-native';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { inboxSections } from '@/features/sessions/inbox';
import type { Catalog, Session } from '@/models/catalog';

const NOW = Date.parse('2026-09-06T15:00:00+08:00');
const start = new Date(NOW);
start.setHours(0, 0, 0, 0);
const today = start.getTime();
const DAY = 86_400_000;

function session(
  id: string,
  title: string,
  status: string,
  extra: Partial<Session> = {},
): Session {
  return {
    id,
    machineId: 'm1',
    title,
    status,
    archived: false,
    pinned: false,
    projectId: 'p1',
    createdAt: new Date(NOW).toISOString(),
    ...extra,
  };
}

const catalog: Catalog = {
  projects: [
    { id: 'p1', machineId: 'm1', name: 'lody-ios', rootPath: '/tmp/lody-ios' },
  ],
  sessions: [
    session('inbox-wait', '权限确认会话', 'waiting'),
    session('inbox-awaiting', '完成后等确认', 'completed', {
      lastMessageAt: NOW - 30_000,
      awaitingUserSince: NOW - 30_000,
    }),
    session('inbox-live', '正在运行的任务', 'running'),
    session('inbox-unread', '刚完成未查看', 'completed', {
      lastMessageAt: NOW - 60_000,
    }),
    session('inbox-today', '今天已读会话', 'completed', {
      lastMessageAt: today + 12 * 60 * 60 * 1000,
      lastReadAt: today + 13 * 60 * 60 * 1000,
    }),
    session('inbox-yesterday', '昨天已读会话', 'completed', {
      lastMessageAt: today - DAY + 12 * 60 * 60 * 1000,
      lastReadAt: today,
    }),
    session('inbox-week', '一周内已读', 'completed', {
      lastMessageAt: today - 4 * DAY,
      lastReadAt: today - 4 * DAY + 1,
    }),
    session('inbox-month', '上个月已读', 'completed', {
      lastMessageAt: today - 18 * DAY,
      lastReadAt: today - 18 * DAY + 1,
    }),
    session('inbox-older', '更早的已读', 'completed', {
      lastMessageAt: today - 40 * DAY,
      lastReadAt: today - 40 * DAY + 1,
    }),
  ],
  machineIds: ['m1'],
};

function View() {
  const colors = usePalette();
  return (
    <RNView testID="inbox-preview-ready" style={{ flex: 1 }}>
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        contentStyle
        sections={inboxSections(catalog, { accent: colors.accent, now: NOW })}
        refreshing={false}
        previewUserId="ui-home"
        previewWorkspaceId="ui-home"
        onRowPress={() => {}}
      />
    </RNView>
  );
}

export const InboxPreviewScreen = definePage({
  id: 'inbox-preview',
  title: '动态分组验收',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
