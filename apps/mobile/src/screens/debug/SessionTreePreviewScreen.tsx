import { useState, type ComponentProps } from 'react';
import { Stack } from 'expo-router';
import { useWindowDimensions, View as RNView, Text } from 'react-native';
import { NativeGroupedList, NativeSidebar } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import {
  byActivity,
  projectSections,
  sessionRow,
  sessionTreeRows,
  searchSections,
  matchCatalog,
} from '@/features/sessions/inbox';
import type { Catalog, Session } from '@/models/catalog';

const NOW = Date.parse('2026-09-19T12:00:00Z');
const session = (
  id: string,
  title: string,
  extra: Partial<Session> = {},
): Session => ({
  id,
  title,
  machineId: 'tree-machine',
  projectId: 'tree-project',
  status: 'completed',
  archived: false,
  pinned: false,
  createdAt: new Date(NOW - 3600_000).toISOString(),
  lastMessageAt: NOW - 3600_000,
  lastReadAt: NOW,
  lastModel: { name: 'GPT-6' },
  ...extra,
});
const fixture: Catalog = {
  machineIds: ['tree-machine'],
  projects: [
    {
      id: 'tree-project',
      machineId: 'tree-machine',
      name: 'Session tree',
      rootPath: '/tmp/session-tree',
    },
  ],
  sessions: [
    session('tree-root', 'Implement sign-in'),
    session('tree-check', 'Check authentication', {
      openedBySessionId: 'tree-root',
      status: 'waiting',
      lastMessageAt: NOW - 1000,
    }),
    session('tree-test', 'Write login tests', {
      openedBySessionId: 'tree-root',
      status: 'running',
      lastMessageAt: NOW - 2000,
    }),
    session('tree-grandchild', 'Review test coverage', {
      openedBySessionId: 'tree-test',
      lastMessageAt: NOW - 3000,
    }),
    session('tree-other', 'Improve settings', { lastMessageAt: NOW - 30_000 }),
    session('tree-orphan', 'Independent review', {
      openedBySessionId: 'missing-session',
      lastMessageAt: NOW - 40_000,
    }),
  ],
};

function Detail() {
  const {
    params: { id, title },
  } = usePageRuntime<{ id: string; title: string }>();
  const colors = usePalette();
  return (
    <RNView style={{ flex: 1, padding: 24, justifyContent: 'center' }}>
      <Text testID={`opened:${id}`} style={{ color: colors.label }}>
        {title}
      </Text>
    </RNView>
  );
}
const SessionTreeDetail = definePage<{ id: string; title: string }>({
  parseRouteParams: () => {
    throw new Error('Open from the tree preview');
  },
  id: 'session-tree-detail',
  title: 'Session',
  Component: Detail,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

function Preview() {
  const colors = usePalette();
  const { width } = useWindowDimensions();
  const [catalog, setCatalog] = useState(fixture);
  const [expanded, setExpanded] = useState<Record<string, boolean>>({});
  const [flat, setFlat] = useState(false);
  const [filtered, setFiltered] = useState(false);
  const sections = projectSections(catalog, colors.accent, expanded, NOW);
  let visible = sections;
  if (flat)
    visible = [
      {
        id: 'sessions',
        rows: sessionTreeRows(
          [...catalog.sessions].sort(byActivity),
          catalog.sessions,
          (s) => sessionRow(s, colors.accent, '', NOW),
        ),
      },
    ];
  if (filtered)
    visible = searchSections(
      catalog,
      matchCatalog(catalog, 'authentication'),
      colors.accent,
    );
  const onRowPress: ComponentProps<typeof NativeGroupedList>['onRowPress'] = ({
    nativeEvent: { id, expanded: open },
  }) => {
    if (open !== undefined) {
      setExpanded((old) => ({ ...old, [id.slice(7)]: open }));
      return;
    }
    const selected = catalog.sessions.find((s) => s.id === id);
    if (selected)
      void present(SessionTreeDetail, { id, title: selected.title });
  };
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          accessibilityLabel="Update tree"
          onPress={() =>
            setCatalog((old) => ({
              ...old,
              sessions: old.sessions.map((s) =>
                s.id === 'tree-root'
                  ? { ...s, title: 'Implement sign-in updated' }
                  : s,
              ),
            }))
          }
        >
          Update
        </Stack.Toolbar.Button>
        <Stack.Toolbar.Button
          accessibilityLabel="Toggle flat list"
          onPress={() => setFlat((old) => !old)}
        >
          List
        </Stack.Toolbar.Button>
        <Stack.Toolbar.Button
          accessibilityLabel="Filter tree"
          onPress={() => setFiltered((old) => !old)}
        >
          Filter
        </Stack.Toolbar.Button>
      </Stack.Toolbar>
      {width >= 768 ? (
        <NativeSidebar
          style={{ flex: 1, width: 320 }}
          sections={visible}
          accent={colors.accent}
          onRowPress={onRowPress}
          onRowAction={() => {}}
        />
      ) : (
        <NativeGroupedList
          style={{ flex: 1 }}
          contentStyle
          sections={visible}
          accent={colors.accent}
          onRowPress={onRowPress}
        />
      )}
    </>
  );
}

export const SessionTreePreviewScreen = definePage({
  id: 'session-tree-preview',
  title: 'Session tree',
  Component: Preview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
