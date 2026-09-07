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
import {
  inboxSections,
  projectSections,
  searchSections,
} from '@/features/sessions/inbox';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { sessionRowAction } from '@/features/sessions/sessionActions';
import { definePage, present } from '@/presentation';
import { showToast } from '@/ui/toast';
import { t } from '../i18n/index.ts';
import { InboxSettingsScreen } from './InboxSettingsScreen';

function View() {
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
              const result = await present(InboxSettingsScreen, { mode });
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

export const InboxScreen = definePage({
  id: 'inbox',
  title: t('tabs.sessions'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
