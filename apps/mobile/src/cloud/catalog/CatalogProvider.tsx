import { createContext, use, useMemo, useSyncExternalStore } from 'react';
import { deleteSession, refreshCatalog, selectWorkspace } from '@lody-ios/kit';
import type { Catalog, Session } from '@lody/cloud-runtime/models/catalog';
import { useAuth } from '@/cloud/auth/AuthProvider';
import type { Workspace } from '../../models/auth.ts';
import {
  emptyCatalog,
  getCatalogStore,
  subscribeCatalogStore,
} from './store.ts';

type CatalogView = {
  catalog: Catalog;
  loading: boolean;
  connected: boolean;
  syncedAt?: number;
  key?: string;
};
type CatalogState = CatalogView & {
  serverSessions: Session[];
  selected: Workspace | undefined;
  setWorkspaceId: (id: string) => void;
  refresh: () => void;
  deleteSessionRequest?: typeof deleteSession;
};

const setWorkspaceId = (id: string) => void selectWorkspace(id);
const refresh = () => void refreshCatalog();

function useNativeCatalog(): CatalogState {
  const state = useSyncExternalStore(
    subscribeCatalogStore,
    getCatalogStore,
    getCatalogStore,
  );
  const { account, initialWorkspace } = useAuth();
  const userId = account?.user.id ?? '';
  const scoped = !!account && state.userId === userId;
  const workspaceId = scoped ? state.workspaceId : initialWorkspace;
  const selected =
    account?.workspaces.find((w) => w.id === workspaceId) ??
    account?.workspaces[0];
  return useMemo(() => {
    let view: CatalogView = {
      catalog: state.catalog,
      loading: state.loading,
      connected: state.connected,
      syncedAt: state.syncedAt,
      key: state.key,
    };
    if (!scoped)
      view = {
        catalog: emptyCatalog,
        loading: !!account,
        connected: !!account,
        key: '',
      };
    const sessions = view.catalog.sessions;
    const extra = scoped ? state.pendingSessions : [];
    return {
      ...view,
      serverSessions: sessions,
      catalog: extra.length
        ? { ...view.catalog, sessions: [...sessions, ...extra] }
        : view.catalog,
      selected,
      setWorkspaceId,
      refresh,
      deleteSessionRequest: deleteSession,
    };
  }, [state, scoped, account, selected]);
}

const Context = createContext<CatalogState | null>(null);

export function useCatalog() {
  const override = use(Context);
  const native = useNativeCatalog();
  return override ?? native;
}

export { Context as CatalogContext };
