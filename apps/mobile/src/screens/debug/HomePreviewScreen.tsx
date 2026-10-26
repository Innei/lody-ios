import { useEffect, useSyncExternalStore } from 'react';
import { View } from 'react-native';
import {
  registerShellPreviewHandler,
  useShellNavigationState,
} from '@/lib/presentation/shellNavigation';
import type { PropsWithChildren } from 'react';
import {
  runtimeInfo,
  readLocalValue,
  setSettingsPreview,
  writeLocalValue,
} from '@lody-ios/kit';
import { MachinePresenceContext } from '@/cloud/catalog/machines';
import type { WorkspacePresence } from '@/cloud/catalog/store';
import { AuthContext } from '@/cloud/auth/AuthProvider';
import { CatalogContext } from '@/cloud/catalog/CatalogProvider';
import type { Catalog } from '@lody/cloud-runtime/models/catalog';
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
  machineIds: ['ui', 'mini', 'studio'],
  machineNames: { ui: 'Fixture Mac', mini: 'Mac mini', studio: 'Studio' },
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

type PreviewWorkspace = {
  id: string;
  name: string;
  slug: string | null;
  image?: string;
};
type PreviewState = {
  catalog: Catalog;
  cacheReady: boolean;
  workspaces: PreviewWorkspace[];
  selected: PreviewWorkspace;
  presence: WorkspacePresence | null;
};

// Every shell page is its own React root; one store keeps the fixture shared.
let preview: PreviewState = {
  catalog,
  cacheReady: false,
  workspaces,
  selected: workspace,
  presence: null,
};
let archivedDeleteFailed = false;
const previewListeners = new Set<() => void>();

function updatePreview(next: Partial<PreviewState>) {
  preview = { ...preview, ...next };
  for (const listener of previewListeners) listener();
}

function subscribePreview(listener: () => void) {
  previewListeners.add(listener);
  return () => {
    previewListeners.delete(listener);
  };
}

function renameWorkspace(id: string, change: Partial<PreviewWorkspace>) {
  updatePreview({
    workspaces: preview.workspaces.map((item) =>
      item.id === id ? { ...item, ...change } : item,
    ),
    selected:
      preview.selected.id === id
        ? { ...preview.selected, ...change }
        : preview.selected,
  });
}

function usePreviewOwner() {
  const selectedId = useSyncExternalStore(
    subscribePreview,
    () => preview.selected.id,
  );
  useEffect(() => {
    let active = true;
    const update = async () => {
      const raw = await readLocalValue('ui-device-presence');
      if (!active) return;
      const next = {
        workspaceId: selectedId,
        presence: raw
          ? JSON.parse(raw)
          : { state: 'unknown', onlineMachineIds: [] },
      };
      if (JSON.stringify(preview.presence) !== JSON.stringify(next))
        updatePreview({ presence: next });
    };
    void update();
    const timer = setInterval(() => void update(), 500);
    return () => {
      active = false;
      clearInterval(timer);
      updatePreview({ presence: null });
    };
  }, [selectedId]);
  useEffect(() => {
    void Promise.all([
      writeLocalValue(
        'ui-device-presence',
        JSON.stringify({ state: 'live', onlineMachineIds: ['ui', 'mini'] }),
      ),
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
    ]).then(() => updatePreview({ cacheReady: true }));
  }, []);
}

function PreviewOwner() {
  usePreviewOwner();
  return null;
}

type DeleteArgs = { sessionId: string; sessionIds: string[] };

function selectWorkspace(id: string) {
  updatePreview({
    selected: workspaces.find((item) => item.id === id) ?? workspace,
  });
}

async function deleteSessions(args: DeleteArgs) {
  await new Promise((resolve) => setTimeout(resolve, 900));
  // Deterministic service failure on the archived fixture; retry succeeds.
  if (args.sessionId === 'ui-search' && !archivedDeleteFailed) {
    archivedDeleteFailed = true;
    throw new Error('offline_fixture');
  }
  updatePreview({
    catalog: {
      ...preview.catalog,
      sessions: preview.catalog.sessions.filter(
        (session) => !args.sessionIds.includes(session.id),
      ),
    },
  });
}

async function applyNativeChange(
  action: string,
  fields: Record<string, unknown>,
) {
  const workspaceId = String(fields.workspaceId ?? '');
  if (action === 'deleteSessions')
    return deleteSessions(fields as unknown as DeleteArgs);
  if (action === 'selectWorkspace') return selectWorkspace(workspaceId);
  if (action === 'updateWorkspace')
    return renameWorkspace(workspaceId, { name: String(fields.name ?? '') });
  if (action === 'updateWorkspaceIcon')
    return renameWorkspace(workspaceId, { image: String(fields.uri ?? '') });
  throw new Error(`unsupported_preview_action:${action}`);
}

const previewUser = {
  id: 'ui-home',
  name: 'UI Preview',
  email: '',
  image: previewPhoto,
};

export function HomePreviewProviders({
  children,
  owner = true,
}: PropsWithChildren<{ owner?: boolean }>) {
  const state = useSyncExternalStore(subscribePreview, () => preview);
  const { selected } = state;
  const selectedCatalog =
    selected.id === workspace.id ? state.catalog : emptyCatalog;
  useEffect(() => {
    if (!owner) return;
    setSettingsPreview(
      JSON.stringify({
        account: { user: previewUser, workspaces: state.workspaces },
        workspaceId: selected.id,
        catalog: selectedCatalog,
      }),
    );
  }, [owner, state.workspaces, selected.id, selectedCatalog]);
  useEffect(() => {
    if (!owner) return;
    const unregister = registerShellPreviewHandler(applyNativeChange);
    return () => {
      unregister();
      setSettingsPreview('');
    };
  }, [owner]);
  return (
    <AuthContext
      value={{
        account: {
          user: previewUser,
          workspaces: state.workspaces,
        },
        busy: false,
        localReady: true,
        initialWorkspace: workspace.id,
        code: null,
        error: null,
        login: noop,
        cancel: noop,
        restore: noop,
        logout: noop,
        reopen: noop,
        updateWorkspace: async (id, name) => renameWorkspace(id, { name }),
        updateWorkspaceIcon: async (id, file) => {
          renameWorkspace(id, { image: file.uri });
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
          setWorkspaceId: selectWorkspace,
          refresh: noop,
          deleteSessionRequest: async (payload) => {
            const args = JSON.parse(payload) as DeleteArgs;
            await deleteSessions(args);
            return JSON.stringify({ sessionIds: args.sessionIds });
          },
        }}
      >
        <MachinePresenceContext value={state.presence}>
          {owner ? (
            <View
              testID={state.cacheReady ? 'ui-verify-ready' : undefined}
              style={{ flex: 1 }}
            >
              <PreviewOwner />
              {children}
              <NavigationProbe />
            </View>
          ) : (
            children
          )}
        </MachinePresenceContext>
      </CatalogContext>
    </AuthContext>
  );
}

function NavigationProbe() {
  const navigation = useShellNavigationState();
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
