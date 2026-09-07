import { useConnection } from '@/cloud/catalog/connection';
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
import { useAuth } from '@/cloud/auth/AuthProvider';
import { LoginPanel } from '@/features/auth/LoginPanel';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/theme/palette';
import { listPlaceholder, searchPlaceholder } from '@/ui/listState';
import { inboxSections, projectSections, searchSections } from './inbox';
import { openCatalogRow, sessionRowAction } from './navigation';
import { definePage, present, usePageRuntime } from '@/presentation';
import { showToast } from '@/ui/toast';
import { currentLocale, t } from '../../i18n/index.ts';

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
      <Stack.Screen options={{ title: selected?.name ?? t('tabs.sessions') }} />
      <Stack.SearchBar
        placement="stacked"
        placeholder={t('search.field.placeholder')}
        hideWhenScrolling={false}
        onChangeText={({ nativeEvent }) => setQuery(nativeEvent.text)}
        onCancelButtonPress={() => setQuery('')}
      />
      <Stack.Title asChild>
        <NativeTitleMenu
          accessibilityName={t('inbox.workspaceSwitch.accessibility', {
            name: selected?.name ?? t('common.workspace'),
          })}
          label={selected?.name ?? t('common.workspace')}
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
          accessibilityLabel={t('inbox.settings.accessibility')}
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
              showToast(t('inbox.toast.settingsFailed'));
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
          header: t('inbox.settings.section.view'),
          rows: (
            [
              'inbox.settings.view.projects',
              'inbox.settings.view.activity',
            ] as const
          ).map((key, index) => ({
            id: String(index),
            title: t(key),
            image: params.mode === index ? 'checkmark' : undefined,
            action: true,
          })),
        },
        {
          id: 'sync',
          header: t('inbox.settings.section.sync'),
          rows: [
            {
              id: 'sync',
              title: t(
                (
                  {
                    offline: 'inbox.settings.sync.offline',
                    syncing: 'inbox.settings.sync.syncing',
                    live: 'inbox.settings.sync.live',
                  } as const
                )[connection.state],
              ),
              subtitle: connection.syncedAt
                ? t('inbox.settings.sync.lastSynced', {
                    time: new Date(connection.syncedAt).toLocaleString(
                      currentLocale(),
                    ),
                  })
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
  title: t('inbox.settings.title'),
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
