import {
  NativeMenuButton,
  NativeNavigationHeader,
  NativeSidebar,
  type NativeSplitFrame,
  panelScrollEdgeEffects,
} from '@lody-ios/kit';
import { useCallback, useState } from 'react';
import { PlatformColor, StyleSheet } from 'react-native';
import {
  ScreenStack,
  ScreenStackHeaderSearchBarView,
  ScreenStackHeaderLeftView,
  ScreenStackItem,
  SearchBar,
} from 'react-native-screens';
import type { HeaderBarButtonItem } from 'react-native-screens';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
import { useDevices } from '@/hooks/screens/useDevices';
import {
  useInboxModel,
  type InboxModel,
} from '@/features/sessions/useInboxModel';
import { inboxFilterMenu } from '@/features/sessions/inboxFilterMenu';
import { useProjectModel } from '@/features/sessions/useProjectModel';
import { requestOpenSession } from '@/features/sessions/sessionNav';
import { isChatProjectId } from '@/features/sessions/inbox';
import { present } from '@/lib/presentation';
import { t } from '@/lib/i18n';
import { SettingsScreen } from '@/screens/SettingsScreen';
import {
  WorkspaceEditorScreen,
  workspaceEditActionId,
} from '@/screens/WorkspaceEditorScreen';

export function PadSidebar({
  frame,
  selectedSessionId,
}: {
  frame?: NativeSplitFrame;
  selectedSessionId?: string;
}) {
  const [projectId, setProjectId] = useState<string>();
  const openRow = useCallback(
    (id: string, catalog: Catalog, findQuery?: string) => {
      if (id.startsWith('project:')) {
        setProjectId(id.slice(8));
        return;
      }
      const session = catalog.sessions.find((entry) => entry.id === id);
      if (session) void requestOpenSession(session, findQuery);
    },
    [],
  );
  return (
    <ScreenStack style={[StyleSheet.absoluteFill, frame]}>
      <InboxPanelItem
        width={frame?.width}
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

function InboxPanelItem({
  width,
  selectedSessionId,
  onOpenRow,
}: {
  width?: number;
  selectedSessionId?: string;
  onOpenRow: (id: string, catalog: Catalog, findQuery?: string) => void;
}) {
  const devices = useDevices();
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
        hideShadow: true,
        title: '',
        translucent: true,
        children: (
          <>
            {account ? (
              <ScreenStackHeaderLeftView>
                <NativeMenuButton
                  testID="workspace-menu"
                  // Reserve space for UIKit’s sidebar toggle and bar margins.
                  style={{ maxWidth: Math.max(44, (width ?? 320) - 112) }}
                  label={workspaceName}
                  status={devices.status}
                  accessibilityName={`${t(
                    'inbox.workspaceSwitch.accessibility',
                    {
                      name: workspaceName,
                    },
                  )}, ${devices.summary}`}
                  avatar={{
                    text: workspaceName.slice(0, 1),
                    color: model.colors.accent,
                    image: selected?.image,
                  }}
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
                        color: model.colors.accent,
                      });
                      return;
                    }
                    model.setWorkspaceId(id);
                  }}
                />
              </ScreenStackHeaderLeftView>
            ) : null}
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
            onOpenRow(id, model.catalog, model.query.trim() || undefined);
        }}
        onRowAction={({ nativeEvent: { id, actionId } }) =>
          model.rowAction(id, actionId)
        }
      />
      <PanelToolbar model={model} />
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

function PanelToolbar({ model }: { model: InboxModel }) {
  return (
    <NativeNavigationHeader
      toolbarItems={[
        inboxFilterMenu(model),
        {
          type: 'button',
          icon: { type: 'sfSymbol', name: 'gearshape' },
          accessibilityLabel: t('tabs.settings'),
          onPress: () => void present(SettingsScreen),
        },
        { type: 'flexibleSpacing' },
        {
          type: 'button',
          icon: { type: 'sfSymbol', name: 'plus' },
          sharesBackground: false,
          tintColor: model.colors.accent,
          accessibilityLabel: t('tabs.newSession'),
          onPress: () => void model.newSession(),
        },
      ]}
    />
  );
}

const styles = StyleSheet.create({ stack: { flex: 1 } });
