import { Stack, useRouter } from 'expo-router';
import { useMemo, useRef, useState } from 'react';
import {
  NativeGroupedList,
  NativeMenuButton,
  NativeSymbolButton,
  initialInboxView,
  saveInboxView,
  initialInboxProjectSort,
  saveInboxProjectSort,
  projectSorts,
  readInboxExpansion,
  saveInboxExpansion,
} from '@lody-ios/kit';
import { Screen } from '@/ui/Screen';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
import { useSessionListCatalog } from '@/features/sessions/useSessionListCatalog';
import { usePalette } from '@/lib/theme/palette';
import { listPlaceholder, searchPlaceholder } from '@/ui/listState';
import {
  inboxSections,
  isChatSectionRow,
  projectSections,
  searchSections,
  type ProjectSort,
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
  { mode: 2, key: 'inbox.settings.view.chat', icon: 'bubble.left' },
] as const;

const inboxSorts = [
  { id: 'name' as const, key: 'inbox.settings.sort.name', icon: 'textformat' },
  {
    id: 'activity' as const,
    key: 'inbox.settings.sort.activity',
    icon: 'clock',
  },
  {
    id: 'urgency' as const,
    key: 'inbox.settings.sort.urgency',
    icon: 'exclamationmark.circle',
  },
] as const;

function View() {
  const router = useRouter();
  const { account, localReady } = useAuth();
  const colors = usePalette();
  const {
    catalog: sourceCatalog,
    selected,
    setWorkspaceId,
    loading,
    connected,
  } = useCatalog();
  const catalog = useSessionListCatalog(
    sourceCatalog,
    account?.user.id ?? '',
    selected?.id ?? '',
  );
  const [mode, setMode] = useState(initialInboxView);
  const [sort, setSort] = useState<ProjectSort>(initialInboxProjectSort);
  const [expanded, setExpanded] = useState(readInboxExpansion);
  const [query, setQuery] = useState('');
  const creating = useRef(false);
  const searching = !!query.trim();
  const sections = useMemo(() => {
    if (mode === 0)
      return projectSections(catalog, colors.accent, expanded, undefined, sort);
    return inboxSections(catalog, {
      accent: colors.accent,
      chatOnly: mode === 2,
    });
  }, [mode, sort, catalog, colors.accent, expanded]);
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
            avatar={{
              text: workspaceName.slice(0, 1),
              color: colors.accent,
              image: selected?.image,
            }}
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
          <Stack.Toolbar.Menu inline>
            {inboxSorts.map((item) => (
              <Stack.Toolbar.MenuAction
                key={item.id}
                icon={item.icon}
                isOn={sort === item.id}
                onPress={() => {
                  setSort(item.id);
                  saveInboxProjectSort(projectSorts.indexOf(item.id));
                }}
              >
                {t(item.key)}
              </Stack.Toolbar.MenuAction>
            ))}
          </Stack.Toolbar.Menu>
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
              await requestNewSession(
                selected.id,
                catalog,
                undefined,
                mode === 2 ? 'chat' : undefined,
              );
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
        placeholder={
          searching
            ? searchPlaceholder({ signedIn: true, query, loading, connected })
            : listPlaceholder({ loading, connected })
        }
        contentStyle
        previewUserId={account.user.id}
        previewWorkspaceId={selected?.id}
        onRowPress={({ nativeEvent: { id, expanded: next = true } }) => {
          if (id === 'view:chat') {
            setMode(2);
            saveInboxView(2);
            return;
          }
          if (id.startsWith('toggle:')) {
            const projectId = id.slice(7);
            saveInboxExpansion(projectId, next);
            setExpanded((previous) => ({ ...previous, [projectId]: next }));
            return;
          }
          if (isChatSectionRow(id)) return;
          openCatalogRow(id, catalog);
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
