import { useEffect, useRef, useState } from 'react';
import { View } from 'react-native';
import { useAppNavigationState } from '@/lib/presentation/useAppNavigationState';
import type { PropsWithChildren } from 'react';
import { runtimeInfo, writeLocalValue } from '@lody-ios/kit';
import { AuthContext } from '@/cloud/auth/AuthProvider';
import { CatalogContext } from '@/cloud/catalog/CatalogProvider';
import type { Catalog } from '@/models/catalog';
import { uiVerify } from './uiVerify';

export const homeVerify = uiVerify && runtimeInfo.uiVerifyHome;

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
      branchName: 'feature/session-model-with-a-very-long-branch-name',
      lastModel: { modelId: 'gpt-6', name: 'GPT-6' },
      title: '首页交互设计',
      projectId: 'ui:local:lody',
      machineId: 'ui',
      status: 'completed',
      createdAt: '2026-09-07T10:00:00Z',
      archived: false,
      pinned: false,
    },
    {
      id: 'ui-pinned',
      branchName: 'main',
      lastModel: { modelId: 'gpt-6', name: 'GPT-6' },
      title: '置顶的首页会话',
      projectId: 'ui:local:lody',
      machineId: 'ui',
      status: 'completed',
      createdAt: '2026-09-07T09:00:00Z',
      lastMessageAt: Date.parse('2026-09-07T09:30:00Z'),
      lastReadAt: Date.parse('2026-09-07T09:40:00Z'),
      archived: false,
      pinned: true,
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
      lastModel: null,
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
const emptyCatalog: Catalog = { projects: [], sessions: [], machineIds: [] };
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

const searchPreviewCache = JSON.stringify({
  v: 1,
  status: 'live',
  revision: 1,
  entries: [
    {
      id: 'search-user',
      role: 'user',
      status: 'completed',
      finished: true,
      items: [{ itemId: 'text', type: 'text', text: 'needle from user' }],
    },
    {
      id: 'search-answer',
      role: 'assistant',
      status: 'completed',
      finished: true,
      items: [
        { itemId: 'thought', type: 'thought', text: 'hidden-only thought' },
        {
          itemId: 'tool',
          type: 'tool_call',
          title: 'tool-only',
          status: 'completed',
        },
        {
          itemId: 'answer',
          type: 'text',
          text: '![image](https://needle.invalid)\n\nA **needle** beside a [needle link](https://private-marker.invalid).\n\ncross**format**body 跨**格式**正文。\n\n`needle code` and [source.ts](/tmp/secret-needle.ts)\n\n```swift\nlet needle = 1\n```\n\n| Key | Value |\n| --- | --- |\n| result | needle |',
        },
      ],
    },
  ],
});
const olderSearchCache = JSON.stringify({
  v: 1,
  status: 'live',
  revision: 1,
  entries: Array.from({ length: 62 }, (_, index) => ({
    id: `search-history-${index}`,
    role: 'assistant',
    status: 'completed',
    finished: true,
    items: [
      {
        itemId: 'answer',
        type: 'text',
        text: index === 0 ? 'ancient-signal' : `Result ${index}`,
      },
    ],
  })),
});

export function HomePreviewProviders({ children }: PropsWithChildren) {
  const [previewCatalog, setPreviewCatalog] = useState(catalog);
  const archivedDeleteFailed = useRef(false);
  const [cacheReady, setCacheReady] = useState(false);
  const [previewWorkspaces, setPreviewWorkspaces] = useState(workspaces);
  const [selected, setSelected] =
    useState<(typeof workspaces)[number]>(workspace);
  const selectedCatalog =
    selected.id === workspace.id ? previewCatalog : emptyCatalog;
  useEffect(() => {
    void Promise.all([
      writeLocalValue(
        'catalog:ui-home:ui-home',
        JSON.stringify({ catalog, syncedAt: 0 }),
      ),
      writeLocalValue('draft:ui-home:ui-home:ui-design', ''),
      writeLocalValue(
        `session:${JSON.stringify(['ui-home', 'ui-home', 'ui-design'])}`,
        runtimeInfo.uiVerifySessionSearch ? searchPreviewCache : previewCache,
      ),
      writeLocalValue(
        `session:${JSON.stringify(['ui-home', 'ui-home', 'ui-search'])}`,
        runtimeInfo.uiVerifySessionSearch ? olderSearchCache : 'null',
      ),
    ]).then(() => setCacheReady(true));
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
          workspaces: previewWorkspaces,
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
        updateWorkspace: async (id, name) => {
          setPreviewWorkspaces((items) =>
            items.map((item) => (item.id === id ? { ...item, name } : item)),
          );
          setSelected((item) => (item.id === id ? { ...item, name } : item));
        },
        updateWorkspaceIcon: async (id, file) => {
          setPreviewWorkspaces((items) =>
            items.map((item) =>
              item.id === id ? { ...item, image: file.uri } : item,
            ),
          );
          setSelected((item) =>
            item.id === id ? { ...item, image: file.uri } : item,
          );
          return file.uri;
        },
      }}
    >
      <CatalogContext
        value={{
          catalog: selectedCatalog,
          serverSessions: selectedCatalog.sessions,
          selected,
          loading: false,
          connected: true,
          syncedAt: undefined,
          key: selected.id,
          setWorkspaceId: (id) =>
            setSelected(workspaces.find((item) => item.id === id) ?? workspace),
          refresh: noop,
          deleteSessionRequest: async (payload) => {
            const args = JSON.parse(payload) as {
              sessionId: string;
              sessionIds: string[];
            };
            await new Promise((resolve) => setTimeout(resolve, 900));
            // Deterministic service failure on the archived fixture; retry succeeds.
            if (
              args.sessionId === 'ui-search' &&
              !archivedDeleteFailed.current
            ) {
              archivedDeleteFailed.current = true;
              throw new Error('offline_fixture');
            }
            setPreviewCatalog((current) => ({
              ...current,
              sessions: current.sessions.filter(
                (session) => !args.sessionIds.includes(session.id),
              ),
            }));
            return JSON.stringify({ sessionIds: args.sessionIds });
          },
        }}
      >
        <View
          testID={cacheReady ? 'ui-verify-ready' : undefined}
          style={{ flex: 1 }}
        >
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
