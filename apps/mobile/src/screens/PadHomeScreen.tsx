import {
  NativeSplit,
  NativeSidebar,
  NativeSplitContent,
  type NativeSplitLayout,
  type NativeSplitFrame,
  NativeMenuButton,
  NativeSymbolButton,
} from '@lody-ios/kit';
import { Stack } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { PlatformColor, StyleSheet, Text, View } from 'react-native';
import {
  ScreenStack,
  ScreenStackHeaderSearchBarView,
  ScreenStackItem,
  SearchBar,
} from 'react-native-screens';
import type { HeaderBarButtonItem } from 'react-native-screens';

import {
  useInboxModel,
  inboxViews,
  inboxSorts,
} from '@/features/sessions/useInboxModel';
import { useProjectModel } from '@/features/sessions/useProjectModel';
import { SettingsScreen } from '@/screens/SettingsScreen';
import { SessionScreen, type SessionParams } from '@/screens/SessionScreen';
import { requestOpenSession } from '@/features/sessions/sessionNav';
import { useBindSessionNav } from '@/hooks/screens/useBindSessionNav';
import { isChatProjectId } from '@/features/sessions/inbox';
import { PageRuntimeProvider, type PageRuntime } from '@/lib/presentation/page';
import { definePage, present } from '@/lib/presentation';
import {
  SheetHeaderContext,
  type SheetHeaderItems,
} from '@/lib/presentation/SheetStack';
import { usePalette } from '@/lib/theme/palette';
import { softScrollEdgeEffects } from '@/ui/Screen';
import type { Catalog } from '@/models/catalog';
import { t } from '@/lib/i18n';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';

const panelScrollEdgeEffects = {
  ...softScrollEdgeEffects,
  left: 'hidden',
  right: 'hidden',
} as const;

function PadHome() {
  const { account } = useAuth();
  const { selected } = useCatalog();
  // Replace both columns together: a workspace must never inherit the old
  // conversation, project stack, search, or an in-flight creation callback.
  return (
    <PadWorkspace key={JSON.stringify([account?.user.id, selected?.id])} />
  );
}

function PadWorkspace() {
  const colors = usePalette();
  const [columns, setColumns] = useState<NativeSplitLayout>();
  const [detailRequest, setDetailRequest] = useState(0);
  const [detail, setDetail] = useState<SessionParams>();
  const [detailHeaderItems, setDetailHeaderItems] =
    useState<SheetHeaderItems>();
  const closeDetail = useCallback(() => setDetail(undefined), []);
  const openDetail = useCallback((value: SessionParams) => {
    setDetail(value);
    setDetailRequest((request) => request + 1);
  }, []);
  useBindSessionNav({ openSession: openDetail });
  const runtime = useMemo<PageRuntime<SessionParams> | null>(() => {
    if (!detail) return null;
    return {
      cancel: closeDetail,
      finish: closeDetail,
      params: detail,
      present,
      push: present,
      source: 'route',
    };
  }, [closeDetail, detail]);

  return (
    <View
      testID="ipad-home"
      style={[styles.root, { backgroundColor: colors.reading }]}
    >
      <Stack.Screen options={{ headerShown: false, title: '' }} />
      <NativeSplit
        style={styles.stack}
        hasDetail={!!detail}
        detailRequest={detailRequest}
        onColumnLayout={({ nativeEvent }) => setColumns(nativeEvent)}
      >
        <PanelStack
          frame={columns?.primary}
          selectedSessionId={detail?.session.id}
        />
        <ScreenStack style={[StyleSheet.absoluteFill, columns?.secondary]}>
          {detail && runtime ? (
            <ScreenStackItem
              screenId={`ipad-session-${detail.session.id}`}
              style={StyleSheet.absoluteFill}
              contentStyle={{ backgroundColor: colors.reading }}
              scrollEdgeEffects={panelScrollEdgeEffects}
              headerConfig={{
                backgroundColor: 'transparent',
                headerLeftBarButtonItems: detailHeaderItems?.left,
                headerRightBarButtonItems: detailHeaderItems?.right,
                hideShadow: true,
                title: '',
                translucent: true,
              }}
            >
              <SheetHeaderContext value={setDetailHeaderItems}>
                <PageRuntimeProvider value={runtime}>
                  <NativeSplitContent edges={{ left: true, right: true }}>
                    {/* Ancestor opacity animations suppress UIKit's composer glass. */}
                    <View key={detail.session.id} style={styles.stack}>
                      <SessionScreen.Component />
                    </View>
                  </NativeSplitContent>
                </PageRuntimeProvider>
              </SheetHeaderContext>
            </ScreenStackItem>
          ) : (
            <ScreenStackItem
              screenId="ipad-detail-placeholder-screen"
              style={StyleSheet.absoluteFill}
              contentStyle={{ backgroundColor: colors.reading }}
              headerConfig={{
                backgroundColor: 'transparent',
                hideShadow: true,
                title: '',
                translucent: true,
              }}
            >
              <NativeSplitContent edges={{ left: true, right: true }}>
                <View
                  testID="ipad-detail-placeholder"
                  style={styles.placeholder}
                >
                  <Text
                    style={[styles.placeholderTitle, { color: colors.label }]}
                  >
                    {t('ipad.detail.title')}
                  </Text>
                  <Text
                    style={[
                      styles.placeholderBody,
                      { color: colors.secondaryLabel },
                    ]}
                  >
                    {t('ipad.detail.message')}
                  </Text>
                </View>
              </NativeSplitContent>
            </ScreenStackItem>
          )}
        </ScreenStack>
      </NativeSplit>
    </View>
  );
}

function PanelStack({
  frame,
  selectedSessionId,
}: {
  frame?: NativeSplitFrame;
  selectedSessionId?: string;
}) {
  const [projectId, setProjectId] = useState<string>();
  const openRow = useCallback((id: string, catalog: Catalog) => {
    if (id.startsWith('project:')) {
      setProjectId(id.slice(8));
      return;
    }
    const session = catalog.sessions.find((entry) => entry.id === id);
    if (session) void requestOpenSession(session);
  }, []);
  return (
    <ScreenStack style={[StyleSheet.absoluteFill, frame]}>
      <InboxPanelItem
        selectedSessionId={selectedSessionId}
        onOpenRow={openRow}
      />
      {projectId ? (
        <ProjectPanelItem
          selectedSessionId={selectedSessionId}
          projectId={projectId}
          onDismiss={() => setProjectId(undefined)}
          onOpenRow={openRow}
        />
      ) : null}
    </ScreenStack>
  );
}

function sidebarHeaderItems(
  model: ReturnType<typeof useInboxModel>,
  openSettings: () => void,
): HeaderBarButtonItem[] {
  return [
    {
      type: 'menu',
      accessibilityLabel: t('inbox.settings.section.view'),
      icon: { type: 'sfSymbol', name: 'line.3.horizontal.decrease' },
      tintColor: model.colors.label,
      menu: {
        items: [
          ...inboxViews.map((view) => ({
            type: 'action' as const,
            title: t(view.key),
            icon: { type: 'sfSymbol' as const, name: view.icon },
            state:
              model.mode === view.mode ? ('on' as const) : ('off' as const),
            onPress: () => model.setView(view.mode),
          })),
          {
            type: 'submenu',
            displayInline: true,
            items: inboxSorts.map((item) => ({
              type: 'action' as const,
              title: t(item.key),
              icon: { type: 'sfSymbol' as const, name: item.icon },
              state:
                model.sort === item.id ? ('on' as const) : ('off' as const),
              onPress: () => model.setProjectSort(item.id),
            })),
          },
        ],
      },
    },
    {
      type: 'button',
      accessibilityLabel: t('tabs.settings'),
      icon: { type: 'sfSymbol', name: 'gearshape' },
      onPress: openSettings,
    },
  ];
}

function InboxPanelItem({
  selectedSessionId,
  onOpenRow,
}: {
  selectedSessionId?: string;
  onOpenRow: (id: string, catalog: Catalog) => void;
}) {
  const model = useInboxModel();
  const account = model.account;
  const selected = model.selected;
  const workspaceName = selected?.name ?? t('common.workspace');
  return (
    <ScreenStackItem
      screenId="ipad-inbox"
      style={StyleSheet.absoluteFill}
      contentStyle={{
        backgroundColor: PlatformColor('secondarySystemBackground'),
      }}
      scrollEdgeEffects={panelScrollEdgeEffects}
      headerConfig={{
        backButtonDisplayMode: 'minimal',
        backgroundColor: 'transparent',
        headerLeftBarButtonItems: sidebarHeaderItems(
          model,
          () => void present(SettingsScreen),
        ),
        hideShadow: true,
        title: '',
        translucent: true,
        children: (
          <>
            <ScreenStackHeaderSearchBarView>
              <SearchBar
                placement="stacked"
                placeholder={t('search.field.placeholder')}
                hideWhenScrolling={false}
                hideNavigationBar={false}
                obscureBackground={false}
                onChangeText={({ nativeEvent }) =>
                  model.setQuery(nativeEvent.text)
                }
                onCancelButtonPress={() => model.setQuery('')}
              />
            </ScreenStackHeaderSearchBarView>
          </>
        ),
      }}
    >
      <NativeSidebar
        testID="ipad-inbox-list"
        style={styles.stack}
        sections={model.ready ? model.sections : []}
        placeholder={model.placeholder}
        selectedRowId={selectedSessionId}
        accent={model.colors.accent}
        previewUserId={account?.user.id}
        previewWorkspaceId={selected?.id}
        onRowPress={({ nativeEvent: { id, expanded } }) => {
          if (!model.consumeRowPress(id, expanded))
            onOpenRow(id, model.catalog);
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) =>
          model.rowAction(id, actionId)
        }
      />
      <Stack.Toolbar>
        {account ? (
          <Stack.Toolbar.View>
            <NativeMenuButton
              label={workspaceName}
              accessibilityName={t('inbox.workspaceSwitch.accessibility', {
                name: workspaceName,
              })}
              avatar={{
                text: workspaceName.slice(0, 1),
                color: model.colors.accent,
                image: selected?.image,
              }}
              items={account.workspaces.map((workspace) => ({
                id: workspace.id,
                title: workspace.name,
                selected: workspace.id === selected?.id,
              }))}
              onSelect={model.setWorkspaceId}
            />
          </Stack.Toolbar.View>
        ) : null}
        <Stack.Toolbar.Spacer />
        <Stack.Toolbar.View separateBackground>
          <NativeSymbolButton
            accessibilityName={t('tabs.newSession')}
            symbol="plus"
            tint={model.colors.accent}
            style={styles.addButton}
            onPress={() => void model.newSession()}
          />
        </Stack.Toolbar.View>
      </Stack.Toolbar>
    </ScreenStackItem>
  );
}

function ProjectPanelItem({
  selectedSessionId,
  projectId,
  onDismiss,
  onOpenRow,
}: {
  selectedSessionId?: string;
  projectId: string;
  onDismiss: () => void;
  onOpenRow: (id: string, catalog: Catalog) => void;
}) {
  const model = useProjectModel(projectId);
  const rightItems: HeaderBarButtonItem[] = [];
  if (model.project && !isChatProjectId(model.project.id)) {
    rightItems.unshift({
      type: 'button',
      accessibilityLabel: t('project.newSession.accessibility'),
      icon: { type: 'sfSymbol', name: 'plus' },
      onPress: model.newSession,
    });
  }
  return (
    <ScreenStackItem
      screenId={`ipad-project-${projectId}`}
      stackPresentation="push"
      style={StyleSheet.absoluteFill}
      contentStyle={{
        backgroundColor: PlatformColor('secondarySystemBackground'),
      }}
      scrollEdgeEffects={panelScrollEdgeEffects}
      headerConfig={{
        backButtonDisplayMode: 'minimal',
        backgroundColor: 'transparent',
        headerRightBarButtonItems: rightItems,
        hideShadow: true,
        title: model.project?.name ?? t('project.title'),
        translucent: true,
      }}
      onDismissed={onDismiss}
    >
      <NativeSidebar
        testID="ipad-project-list"
        style={styles.stack}
        sections={model.sections}
        placeholder={model.placeholder}
        selectedRowId={selectedSessionId}
        accent={model.colors.accent}
        previewUserId={model.account?.user.id}
        previewWorkspaceId={model.selected?.id}
        onRowPress={({ nativeEvent: { id } }) => onOpenRow(id, model.catalog)}
        onRowAction={({ nativeEvent: { id, actionId } }) =>
          model.rowAction(id, actionId)
        }
      />
    </ScreenStackItem>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  stack: { flex: 1 },
  addButton: { width: 44, height: 44 },
  placeholder: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 48,
  },
  placeholderTitle: { fontSize: 24, fontWeight: '600' },
  placeholderBody: {
    fontSize: 16,
    lineHeight: 22,
    marginTop: 8,
    maxWidth: 360,
    textAlign: 'center',
  },
});

export const PadHomeScreen = definePage({
  id: 'pad-home',
  title: t('tabs.sessions'),
  Component: PadHome,
  presentation: { style: 'push', headerShown: false },
});
