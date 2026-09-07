import { useConnection } from '@/cloud/connection';
import { Stack } from 'expo-router';
import { useMemo, useState } from 'react';
import {
  NativeGroupedList,
  NativeTitleMenu,
  initialInboxView,
  saveInboxView,
  readInboxExpansion,
  saveInboxExpansion,
} from '@lody-ios/kit';
import { Screen } from '@/ui/Screen';
import { useAuth } from '@/features/auth/AuthProvider';
import { LoginPanel } from '@/features/auth/LoginPanel';
import { useCatalog } from '@/cloud/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { listPlaceholder, searchPlaceholder } from '@/ui/listState';
import { inboxSections, projectSections, searchSections } from './inbox';
import { openCatalogRow, sessionRowAction } from './navigation';
import { definePage, present, usePageRuntime } from '@/presentation';
import { showToast } from '@/ui/toast';

export default function InboxScreen() {
  const { account, localReady } = useAuth();
  const colors = usePalette();
  const { catalog, selected, setWorkspaceId, loading, connected, refresh } =
    useCatalog();
  const [mode, setMode] = useState(initialInboxView);
  const [expanded, setExpanded] = useState(readInboxExpansion);
  const [query, setQuery] = useState('');
  const searching = !!query.trim();
  const sections = useMemo(
    () =>
      mode === 0
        ? projectSections(catalog, colors.accent, expanded)
        : inboxSections(catalog, { accent: colors.accent }),
    [mode, catalog, colors.accent, expanded],
  );
  if (!localReady) return <Screen />;
  if (!account)
    return (
      <Screen>
        <LoginPanel />
      </Screen>
    );
  return (
    <>
      <Stack.Screen options={{ title: selected?.name ?? '会话' }} />
      <Stack.SearchBar
        placement="stacked"
        placeholder="搜索项目或会话"
        hideWhenScrolling={false}
        onChangeText={({ nativeEvent }) => setQuery(nativeEvent.text)}
        onCancelButtonPress={() => setQuery('')}
      />
      <Stack.Title asChild>
        <NativeTitleMenu
          accessibilityName={`切换工作区，${selected?.name ?? '工作区'}`}
          label={selected?.name ?? '工作区'}
          items={account.workspaces.map((workspace) => ({
            id: workspace.id,
            title: workspace.name,
            selected: workspace.id === selected?.id,
          }))}
          onSelect={setWorkspaceId}
        />
      </Stack.Title>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          accessibilityLabel="首页设置"
          icon="slider.horizontal.3"
          tintColor={colors.accent}
          onPress={async () => {
            try {
              const result = await present(inboxSettingsPage, { mode });
              if (result.status === 'completed') {
                setMode(result.value);
                saveInboxView(result.value);
              }
            } catch {
              showToast('暂时无法打开首页设置，请重试。');
            }
          }}
        />
      </Stack.Toolbar>
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        sections={
          searching ? searchSections(catalog, query, colors.accent) : sections
        }
        refreshing={false}
        placeholder={
          searching
            ? searchPlaceholder({ signedIn: true, query, loading, connected })
            : listPlaceholder({ loading, connected })
        }
        onRefresh={refresh}
        contentStyle
        onRowPress={({ nativeEvent: { id } }) => {
          if (id.startsWith('toggle:')) {
            const projectId = id.slice(7);
            const next = !(expanded[projectId] ?? true);
            saveInboxExpansion(projectId, next);
            setExpanded((previous) => ({ ...previous, [projectId]: next }));
          } else openCatalogRow(id, catalog);
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (selected) sessionRowAction(selected.id, catalog, id, actionId);
        }}
      />
    </>
  );
}

function InboxSettingsScreen() {
  const { params, finish } = usePageRuntime<{ mode: number }, number>();
  const colors = usePalette();
  const connection = useConnection();
  const { refresh } = useCatalog();
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      transparent
      accent={colors.accent}
      sections={[
        {
          id: 'view',
          header: '首页视图',
          rows: ['项目', '动态'].map((title, index) => ({
            id: String(index),
            title,
            image: params.mode === index ? 'checkmark' : undefined,
            action: true,
          })),
        },
        {
          id: 'sync',
          header: '同步',
          rows: [
            {
              id: 'sync',
              title: {
                offline: '离线，点按重试',
                syncing: '正在同步',
                live: '已同步',
              }[connection.state],
              subtitle: connection.syncedAt
                ? `上次同步：${new Date(connection.syncedAt).toLocaleString()}`
                : undefined,
              image: 'arrow.clockwise',
              action: true,
            },
          ],
        },
      ]}
      onRowPress={({ nativeEvent: { id } }) => {
        if (id === 'sync') refresh();
        else if (id === '0' || id === '1') finish(Number(id));
      }}
    />
  );
}

const inboxSettingsPage = definePage<{ mode: number }, number>({
  id: 'inbox-settings',
  title: '首页设置',
  Component: InboxSettingsScreen,
  parseRouteParams: () => {
    throw new Error('请从首页打开');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.5, 1],
    sheetGrabberVisible: true,
  },
});
