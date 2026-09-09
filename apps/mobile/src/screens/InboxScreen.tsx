import { Stack, useRouter } from 'expo-router';
import { useMemo, useRef, useState } from 'react';
import {
  NativeGroupedList,
  NativeMenuButton,
  NativeSymbolButton,
  initialInboxView,
  saveInboxView,
  readInboxExpansion,
  saveInboxExpansion,
} from '@lody-ios/kit';
import { Screen } from '@/ui/Screen';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { usePalette } from '@/lib/theme/palette';
import { listPlaceholder, searchPlaceholder } from '@/ui/listState';
import {
  inboxSections,
  projectSections,
  searchSections,
} from '@/features/sessions/inbox';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { requestNewSession } from '@/features/sessions/sessionNav';
import { listRowAction } from '@/features/sessions/sessionActions';
import { definePage, present } from '@/lib/presentation';
import { showToast } from '@/ui/toast';
import { t } from '../lib/i18n/index.ts';
import { SettingsScreen } from './SettingsScreen';

const inboxViews = [
  { mode: 0, key: 'inbox.settings.view.projects', icon: 'folder' },
  { mode: 1, key: 'inbox.settings.view.activity', icon: 'clock' },
] as const;

function View() {
  const router = useRouter();
  const { account, localReady } = useAuth();
  const colors = usePalette();
  const { catalog, selected, setWorkspaceId, loading, connected, refresh } =
    useCatalog();
  const [mode, setMode] = useState(initialInboxView);
  const [expanded, setExpanded] = useState(readInboxExpansion);
  const [query, setQuery] = useState('');
  const creating = useRef(false);
  const searching = !!query.trim();
  const sections = useMemo(
    () =>
      mode === 0
        ? projectSections(catalog, colors.accent, expanded)
        : inboxSections(catalog, { accent: colors.accent }),
    [mode, catalog, colors.accent, expanded],
  );
  if (!localReady || !account) return <Screen />;
  const workspaceName = selected?.name ?? t('common.workspace');
  return (
    <>
      <Stack.Screen options={{ title: '' }} />
      <Stack.Toolbar placement="left">
        <Stack.Toolbar.View>
          <NativeMenuButton
            testID="workspace-menu"
            accessibilityName={t('inbox.workspaceSwitch.accessibility', {
              name: workspaceName,
            })}
            avatar={{ text: workspaceName.slice(0, 1), color: colors.accent }}
            label={workspaceName}
            items={account.workspaces.map((workspace) => ({
              id: workspace.id,
              title: workspace.name,
              selected: workspace.id === selected?.id,
            }))}
            onSelect={setWorkspaceId}
          />
        </Stack.Toolbar.View>
      </Stack.Toolbar>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Menu
          icon="line.3.horizontal.decrease"
          tintColor={colors.label}
          accessibilityLabel={t('inbox.settings.section.view')}
        >
          {inboxViews.map((view) => (
            <Stack.Toolbar.MenuAction
              key={view.mode}
              icon={view.icon}
              isOn={mode === view.mode}
              onPress={() => {
                setMode(view.mode);
                saveInboxView(view.mode);
              }}
            >
              {t(view.key)}
            </Stack.Toolbar.MenuAction>
          ))}
        </Stack.Toolbar.Menu>
        <Stack.Toolbar.View>
          <NativeSymbolButton
            accessibilityName={t('tabs.settings')}
            symbol="gearshape"
            style={{ width: 44, height: 44 }}
            onPress={() => void present(SettingsScreen)}
            onLongPress={() => router.push('/debug')}
          />
        </Stack.Toolbar.View>
      </Stack.Toolbar>
      <Stack.SearchBar
        placement="integrated"
        placeholder={t('search.field.placeholder')}
        hideWhenScrolling={false}
        onChangeText={({ nativeEvent }) => setQuery(nativeEvent.text)}
        onCancelButtonPress={() => setQuery('')}
      />
      <Stack.Toolbar>
        <Stack.Toolbar.SearchBarSlot />
        <Stack.Toolbar.Spacer width={6} />
        <Stack.Toolbar.Button
          icon="plus"
          separateBackground
          tintColor={colors.accent}
          accessibilityLabel={t('tabs.newSession')}
          onPress={async () => {
            if (creating.current) return;
            if (!selected) {
              showToast(t('tabs.toast.signInFirst'));
              return;
            }
            creating.current = true;
            try {
              await requestNewSession(selected.id, catalog);
            } finally {
              creating.current = false;
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
        previewUserId={account.user.id}
        previewWorkspaceId={selected?.id}
        onRowPress={({ nativeEvent: { id, expanded: next = true } }) => {
          if (id.startsWith('toggle:')) {
            const projectId = id.slice(7);
            saveInboxExpansion(projectId, next);
            setExpanded((previous) => ({ ...previous, [projectId]: next }));
          } else openCatalogRow(id, catalog);
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) => {
          if (selected) listRowAction(selected.id, catalog, id, actionId);
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
