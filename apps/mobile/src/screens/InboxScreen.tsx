import { Stack } from 'expo-router';
import { useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  NativeGroupedList,
  NativeMenuButton,
  NativeNavigationHeader,
  NativeSymbolButton,
  shellEnabled,
} from '@lody-ios/kit';
import { Screen } from '@/ui/Screen';
import {
  useInboxModel,
  inboxViews,
  inboxSorts,
  type InboxModel,
} from '@/features/sessions/useInboxModel';
import { inboxFilterMenu } from '@/features/sessions/inboxFilterMenu';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { definePage, present } from '@/lib/presentation';
import { openRoute } from '@/lib/presentation/appNavigation';
import { t } from '@/lib/i18n';
import { useDevices } from '@/hooks/screens/useDevices';
import { SettingsScreen } from './SettingsScreen';
import {
  WorkspaceEditorScreen,
  workspaceEditActionId,
} from './WorkspaceEditorScreen';

function InboxList({ model }: { model: InboxModel }) {
  if (!model.ready || !model.account) return <Screen />;
  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={model.colors.accent}
      sections={model.sections}
      placeholder={model.placeholder}
      contentStyle
      previewUserId={model.account.user.id}
      previewWorkspaceId={model.selected?.id}
      onRowPress={({ nativeEvent: { id, expanded } }) => {
        if (!model.consumeRowPress(id, expanded))
          openCatalogRow(id, model.catalog, model.query.trim() || undefined);
      }}
      onRowAction={({ nativeEvent: { id, actionId } }) =>
        model.rowAction(id, actionId)
      }
    />
  );
}

function openDebug() {
  openRoute('/debug');
}

function ShellChrome({ model }: { model: InboxModel }) {
  const devices = useDevices();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const { account, colors, selected } = model;
  if (!model.ready || !account) return null;
  const workspaceName = selected?.name ?? t('common.workspace');
  const workspaceMenu = (
    <NativeMenuButton
      testID="workspace-menu"
      style={{
        // Leave room for both trailing actions and UIKit's glass group margins.
        maxWidth: Math.max(44, width - insets.left - insets.right - 192),
      }}
      accessibilityName={`${t('inbox.workspaceSwitch.accessibility', {
        name: workspaceName,
      })}, ${devices.summary}`}
      avatar={{
        text: workspaceName.slice(0, 1),
        color: colors.accent,
        image: selected?.image,
      }}
      label={workspaceName}
      status={devices.status}
      items={[
        devices.menuItem,
        ...account.workspaces.map((workspace) => ({
          id: workspace.id,
          title: workspace.name,
          selected: workspace.id === selected?.id,
        })),
        ...(selected
          ? [{ id: workspaceEditActionId, title: t('workspace.edit.action') }]
          : []),
      ]}
      onSelect={(id) => {
        if (id === workspaceEditActionId && selected) {
          void present(WorkspaceEditorScreen, {
            workspaceId: selected.id,
            name: selected.name,
            image: selected.image,
            color: colors.accent,
          });
          return;
        }
        model.setWorkspaceId(id);
      }}
    />
  );
  return (
    <>
      <NativeNavigationHeader
        leftItems={[{ type: 'view', element: workspaceMenu }]}
        items={[
          inboxFilterMenu(model),
          {
            type: 'view',
            element: (
              <NativeSymbolButton
                accessibilityName={t('tabs.settings')}
                symbol="gearshape"
                style={{ width: 44, height: 44 }}
                onPress={() => void present(SettingsScreen)}
                onLongPress={openDebug}
              />
            ),
          },
        ]}
        search={{
          placement: 'integrated',
          placeholder: t('search.field.placeholder'),
          hideWhenScrolling: false,
          onChangeText: model.setQuery,
          onCancel: () => model.setQuery(''),
        }}
        toolbarItems={[
          { type: 'searchSlot' },
          { type: 'spacing', spacing: 6 },
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'plus' },
            sharesBackground: false,
            tintColor: colors.accent,
            accessibilityLabel: t('tabs.newSession'),
            onPress: () => void model.newSession(),
          },
        ]}
      />
    </>
  );
}

function RouterChrome({ model }: { model: InboxModel }) {
  const devices = useDevices();
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const { account, colors, mode, selected, sort } = model;
  if (!model.ready || !account) return null;
  const workspaceName = selected?.name ?? t('common.workspace');
  return (
    <>
      <Stack.Screen options={{ headerShown: true, title: '' }} />
      <Stack.Toolbar placement="left">
        <Stack.Toolbar.View>
          <NativeMenuButton
            testID="workspace-menu"
            style={{
              // Leave room for both trailing actions and UIKit's glass group margins.
              maxWidth: Math.max(44, width - insets.left - insets.right - 192),
            }}
            accessibilityName={`${t('inbox.workspaceSwitch.accessibility', {
              name: workspaceName,
            })}, ${devices.summary}`}
            avatar={{
              text: workspaceName.slice(0, 1),
              color: colors.accent,
              image: selected?.image,
            }}
            label={workspaceName}
            status={devices.status}
            items={[
              devices.menuItem,
              ...account.workspaces.map((workspace) => ({
                id: workspace.id,
                title: workspace.name,
                selected: workspace.id === selected?.id,
              })),
              ...(selected
                ? [
                    {
                      id: workspaceEditActionId,
                      title: t('workspace.edit.action'),
                    },
                  ]
                : []),
            ]}
            onSelect={(id) => {
              if (id === workspaceEditActionId && selected) {
                void present(WorkspaceEditorScreen, {
                  workspaceId: selected.id,
                  name: selected.name,
                  image: selected.image,
                  color: colors.accent,
                });
                return;
              }
              model.setWorkspaceId(id);
            }}
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
              onPress={() => model.setView(view.mode)}
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
                onPress={() => model.setProjectSort(item.id)}
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
            onLongPress={openDebug}
          />
        </Stack.Toolbar.View>
      </Stack.Toolbar>
      <Stack.SearchBar
        placement="integrated"
        placeholder={t('search.field.placeholder')}
        hideWhenScrolling={false}
        onChangeText={({ nativeEvent }) => model.setQuery(nativeEvent.text)}
        onCancelButtonPress={() => model.setQuery('')}
      />
      <Stack.Toolbar>
        <Stack.Toolbar.SearchBarSlot />
        <Stack.Toolbar.Spacer width={6} />
        <Stack.Toolbar.Button
          icon="plus"
          separateBackground
          tintColor={colors.accent}
          accessibilityLabel={t('tabs.newSession')}
          onPress={() => void model.newSession()}
        />
      </Stack.Toolbar>
    </>
  );
}

const InboxChrome = shellEnabled ? ShellChrome : RouterChrome;

function View() {
  const model = useInboxModel();
  return (
    <>
      <InboxChrome model={model} />
      <InboxList model={model} />
    </>
  );
}

export const InboxScreen = definePage({
  id: 'inbox',
  title: t('tabs.sessions'),
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
