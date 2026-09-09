import { useEffect } from 'react';
import { View } from 'react-native';
import type { PropsWithChildren } from 'react';
import { writeLocalValue } from '@lody-ios/kit';
import { AuthContext } from '@/cloud/auth/AuthProvider';
import { CatalogContext } from '@/cloud/catalog/CatalogProvider';
import type { Catalog } from '@/models/catalog';

export const homeVerify =
  __DEV__ &&
  process.env.EXPO_PUBLIC_UI_VERIFY === '1' &&
  process.env.EXPO_PUBLIC_UI_VERIFY_HOME === '1';

const workspace = {
  id: 'ui-home',
  name: '我的超长工作区名称不能折行',
  slug: null,
};
// An unassigned project exercises search without requesting machine configuration.
const catalog: Catalog = {
  projects: [
    { id: 'ui:unassigned', name: 'Lody iOS', machineId: 'ui', rootPath: '' },
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
      projectId: 'ui:unassigned',
      machineId: 'ui',
      status: 'completed',
      createdAt: '2026-09-07T10:00:00Z',
      archived: false,
      pinned: false,
    },
    {
      id: 'ui-search',
      title: '搜索历史会话 Search',
      projectId: 'ui:unassigned',
      machineId: 'ui',
      status: 'completed',
      createdAt: '2026-09-07T10:00:00Z',
      archived: true,
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
  useEffect(() => {
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
            image:
              'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAAL0lEQVR42u3OIQEAAAgDMNJQk6J0gRg3E/Or7bmkEhAQEBAQEBAQEBAQEBAQSAceRa0Al+0rSMYAAAAASUVORK5CYII=',
          },
          workspaces: [workspace],
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
          selected: workspace,
          loading: false,
          connected: true,
          syncedAt: undefined,
          key: 'ui-home',
          setWorkspaceId: noop,
          refresh: noop,
        }}
      >
        <View testID="ui-verify-ready" style={{ flex: 1 }}>
          {children}
        </View>
      </CatalogContext>
    </AuthContext>
  );
}
