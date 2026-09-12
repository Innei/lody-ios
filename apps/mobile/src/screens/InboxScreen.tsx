import { Stack, useRouter } from 'expo-router';
import {
  NativeGroupedList,
  NativeMenuButton,
  NativeSymbolButton,
} from '@lody-ios/kit';
import { Screen } from '@/ui/Screen';
import {
  useInboxModel,
  inboxViews,
  inboxSorts,
  type InboxModel,
} from '@/features/sessions/useInboxModel';
import { openCatalogRow } from '@/hooks/screens/openCatalogRow';
import { definePage, present } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import { SettingsScreen } from './SettingsScreen';

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
          openCatalogRow(id, model.catalog);
      }}
      onRowAction={({ nativeEvent: { id, actionId } }) =>
        model.rowAction(id, actionId)
      }
    />
  );
}

function RouterChrome({ model }: { model: InboxModel }) {
  const router = useRouter();
  const { account, colors, mode, selected, sort } = model;
  if (!model.ready || !account) return null;
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
            onSelect={model.setWorkspaceId}
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
            onLongPress={() => router.push('/debug')}
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

function View() {
  const model = useInboxModel();
  return (
    <>
      <RouterChrome model={model} />
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
