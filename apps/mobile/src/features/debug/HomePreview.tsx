import { View } from 'react-native';
import type { PropsWithChildren } from 'react';
import { AuthContext } from '@/features/auth/AuthProvider';
import { CatalogContext } from '@/cloud/CatalogProvider';
import type { Catalog } from '@/cloud/model';

export const homeVerify =
  __DEV__ &&
  process.env.EXPO_PUBLIC_UI_VERIFY === '1' &&
  process.env.EXPO_PUBLIC_UI_VERIFY_HOME === '1';

const workspace = { id: 'ui-home', name: '我的工作区', slug: null };
// An unassigned project exercises search without requesting machine configuration.
const catalog: Catalog = {
  projects: [
    { id: 'ui:unassigned', name: 'Lody iOS', machineId: 'ui', rootPath: '' },
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

export function HomePreviewProviders({ children }: PropsWithChildren) {
  return (
    <AuthContext
      value={{
        account: {
          token: '',
          user: { id: 'ui-home', name: 'UI Preview', email: '' },
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
