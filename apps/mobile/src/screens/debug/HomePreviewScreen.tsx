import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { useAppNavigationState } from '@/lib/presentation/useAppNavigationState';
import type { PropsWithChildren } from 'react';
import { runtimeInfo, writeLocalValue } from '@lody-ios/kit';
import { AuthContext } from '@/cloud/auth/AuthProvider';
import { CatalogContext } from '@/cloud/catalog/CatalogProvider';
import type { Catalog } from '@/models/catalog';

export const homeVerify =
  __DEV__ &&
  process.env.EXPO_PUBLIC_UI_VERIFY === '1' &&
  runtimeInfo.uiVerifyHome;

const previewPhoto =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAL0lEQVR42u3OIQEAAAgDMNJQk6J0gRg3E/Or7bmkEhAQEBAQEBAQEBAQEBAQSAceRa0Al+0rSMYAAAAASUVORK5CYII=';
const workspace = {
  id: 'ui-home',
  name: '我的超长工作区名称不能折行',
  slug: null,
  image: previewPhoto,
};
const workspaces = [
  workspace,
  { id: 'ui-other', name: '另一个工作区', slug: 'other' },
];
const catalog: Catalog = {
  projects: [
    {
      id: 'ui:local:lody',
      name: 'Lody iOS',
      machineId: 'ui',
      rootPath: '/tmp/lody-ios',
    },
    {
      id: 'ui:empty',
      name: '空盒子',
      machineId: 'ui',
      rootPath: '/tmp/empty-box',
    },
  ],
  sessions: [
    {
      id: 'ui-design',
      title: '首页交互设计',
      projectId: 'ui:local:lody',
      machineId: 'ui',
      status: 'completed',
      createdAt: '2026-09-07T10:00:00Z',
      archived: false,
      pinned: false,
    },
    {
      id: 'ui-search',
      title: '搜索历史会话 Search',
      projectId: 'ui:local:lody',
      machineId: 'ui',
      status: 'completed',
      createdAt: '2026-09-07T10:00:00Z',
      archived: true,
      pinned: false,
    },
    {
      id: 'ui-chat',
      title: '纯对话草稿',
      projectId: 'ui:unassigned',
      machineId: 'ui',
      status: 'idle',
      createdAt: '2026-09-07T11:00:00Z',
      archived: false,
      pinned: false,
    },
  ],
  machineIds: [],
};
const noop = async () => {};
const previewCache = JSON.stringify({
  v: 1,
  status: 'live',
  revision: 1,
  entries: [
    {
      id: 'u1',
      role: 'user',
      status: 'completed',
      finished: true,
      items: [{ itemId: 't', type: 'text', text: '设计首页' }],
    },
    {
      id: 'a1',
      role: 'assistant',
      status: 'completed',
      finished: true,
      items: [
        { itemId: 'think', type: 'thought', text: '先看列表' },
        {
          itemId: 'read',
          type: 'tool_call',
          kind: 'read',
          status: 'completed',
          title: '读取',
        },
        { itemId: 'answer', type: 'text', text: '用项目分组。' },
      ],
    },
  ],
});

export function HomePreviewProviders({ children }: PropsWithChildren) {
  const [selected, setSelected] =
    useState<(typeof workspaces)[number]>(workspace);
  useEffect(() => {
    void writeLocalValue('draft:ui-home:ui-home:ui-design', '');
    void writeLocalValue(
      `session:${JSON.stringify(['ui-home', 'ui-home', 'ui-design'])}`,
      previewCache,
    );
  }, []);
  return (
    <AuthContext
      value={{
        account: {
          token: '',
          user: {
            id: 'ui-home',
            name: 'UI Preview',
            email: '',
            image: previewPhoto,
          },
          workspaces,
        },
        busy: false,
        localReady: true,
        initialWorkspace: workspace.id,
        initialCatalog: null,
        code: null,
        error: null,
        login: noop,
        cancel: noop,
        restore: noop,
        logout: noop,
        reopen: noop,
      }}
    >
      <CatalogContext
        value={{
          catalog,
          serverSessions: catalog.sessions,
          selected,
          loading: false,
          connected: true,
          syncedAt: undefined,
          key: selected.id,
          setWorkspaceId: (id) =>
            setSelected(workspaces.find((item) => item.id === id) ?? workspace),
          refresh: noop,
        }}
      >
        <View testID="ui-verify-ready" style={{ flex: 1 }}>
          {children}
          <NavigationProbe />
        </View>
      </CatalogContext>
    </AuthContext>
  );
}

function NavigationProbe() {
  const navigation = useAppNavigationState();
  return (
    <View
      accessible
      testID="ui-navigation-state"
      accessibilityLabel="Navigation state"
      accessibilityValue={{
        text: JSON.stringify(
          navigation?.routes.map((route) => route.name) ?? [],
        ),
      }}
      pointerEvents="none"
      style={{ position: 'absolute', bottom: 0, width: 1, height: 1 }}
    />
  );
}
