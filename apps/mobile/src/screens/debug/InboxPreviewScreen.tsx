import { NativeGroupedList, NativeChat } from '@lody-ios/kit';
import { useState } from 'react';
import { Stack } from 'expo-router';
import { View as RNView } from 'react-native';
import { definePage, present } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { useSessionListCatalog } from '@/features/sessions/useSessionListCatalog';
import { useSessionViewed } from '@/features/sessions/useSessionViewed';
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
  const [scope] = useState(() => `inbox-preview-${Date.now()}`);
  const [source, setSource] = useState(catalog);
  const viewed = useSessionListCatalog(source, scope, scope);
  return (
    <RNView testID="inbox-preview-ready" style={{ flex: 1 }}>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          onPress={() =>
            setSource((old) => ({
              ...old,
              sessions: old.sessions.map((s) =>
                s.id === 'inbox-unread' ? { ...s, lastMessageAt: NOW + 1 } : s,
              ),
            }))
          }
        >
          新消息
        </Stack.Toolbar.Button>
      </Stack.Toolbar>
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        contentStyle
        sections={inboxSections(viewed, { accent: colors.accent, now: NOW })}
        previewUserId="ui-home"
        previewWorkspaceId="ui-home"
        onRowPress={({ nativeEvent: { id } }) => {
          const selected = source.sessions.find((s) => s.id === id);
          if (selected)
            void present(InboxViewedPreviewScreen, {
              scope,
              session: selected,
            });
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (actionId === 'read')
            setSource((old) => ({
              ...old,
              sessions: old.sessions.map((s) =>
                s.id === id ? { ...s, lastReadAt: NOW } : s,
              ),
            }));
        }}
      />
    </RNView>
  );
}

function ViewedPreview() {
  const {
    params: { scope, session },
  } = usePageRuntime<{ scope: string; session: Session }>();
  useSessionViewed(scope, scope, session.id, session.lastMessageAt);
  return (
    <RNView testID="inbox-viewed-detail" style={{ flex: 1 }}>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON="[]"
        composerJSON={JSON.stringify({ editable: false, canSend: false })}
        clearDraftToken={0}
        emptyText="本机已查看，返回后仍保留在未读分组。"
        onSend={() => {}}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </RNView>
  );
}

const InboxViewedPreviewScreen = definePage<{
  scope: string;
  session: Session;
}>({
  id: 'inbox-viewed-preview',
  title: '查看会话',
  Component: ViewedPreview,
  parseRouteParams: () => {
    throw new Error('Open this page from the inbox preview');
  },
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export const InboxPreviewScreen = definePage({
  id: 'inbox-preview',
  title: '动态分组验收',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
