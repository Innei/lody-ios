import {
  createContext,
  useContext,
  useEffect,
  useState,
  type PropsWithChildren,
} from 'react';
import { showToast } from '@/ui/toast';
import { useAuth } from '@/features/auth/AuthProvider';
import { subscribeCatalog } from './runtime';
import { usePendingSends } from './pendingSends';
import { publishConnection } from './connection';
import {
  catalogKey,
  localGeneration,
  selectionKey,
  readLocal,
  writeLocal,
  type SavedCatalog,
} from './local';
import type { Catalog } from './model';

const empty: Catalog = { projects: [], sessions: [], machineIds: [] };
function valid(saved: SavedCatalog | null): saved is SavedCatalog {
  return (
    !!saved &&
    Array.isArray(saved.catalog?.projects) &&
    Array.isArray(saved.catalog?.sessions) &&
    Array.isArray(saved.catalog?.machineIds)
  );
}
function useCatalogState() {
  const { account, localReady, initialWorkspace, initialCatalog } = useAuth();
  const [choice, setChoice] = useState({ user: '', workspace: '' });
  const workspaceId =
    choice.user === account?.user.id ? choice.workspace : initialWorkspace;
  const selected =
    account?.workspaces.find((w) => w.id === workspaceId) ??
    account?.workspaces[0];
  const pending = usePendingSends(account?.user.id ?? '', selected?.id ?? '');
  const key =
    account && selected ? catalogKey(account.user.id, selected.id) : '';
  const [snapshot, setSnapshot] = useState({
    key: '',
    catalog: empty,
    loading: true,
    connected: true,
    syncedAt: undefined as number | undefined,
  });
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    if (!key || !account || !selected) {
      setSnapshot({
        key: '',
        catalog: empty,
        loading: false,
        connected: false,
        syncedAt: undefined,
      });
      if (localReady) publishConnection({ state: 'offline', machines: 0 });
      return;
    }
    const localVersion = localGeneration();
    let active = true;
    let received = false;
    let saveErrorShown = false;
    let syncedAt: number | undefined;
    let machines = 0;
    let state: 'syncing' | 'live' | 'offline' = 'syncing';
    const seed =
      selected.id === initialWorkspace && valid(initialCatalog)
        ? initialCatalog
        : null;
    syncedAt = seed?.syncedAt;
    machines = seed?.catalog.machineIds.length ?? 0;
    setSnapshot((old) => ({
      key,
      catalog: old.key === key ? old.catalog : (seed?.catalog ?? empty),
      syncedAt: old.key === key ? old.syncedAt : syncedAt,
      connected: true,
      loading: true,
    }));
    publishConnection({ state, machines, syncedAt });
    void readLocal<SavedCatalog>(key).then((saved) => {
      if (!active || received || !valid(saved)) return;
      syncedAt = saved.syncedAt;
      machines = saved.catalog.machineIds.length;
      setSnapshot((old) =>
        old.key === key && (old.syncedAt ?? 0) > saved.syncedAt
          ? old
          : {
              key,
              ...saved,
              loading: state === 'syncing',
              connected: state !== 'offline',
            },
      );
      publishConnection({ state, machines, syncedAt });
    });
    const stop = subscribeCatalog(
      selected.id,
      account.user.id,
      (event, data) => {
        if (data) {
          received = true;
          syncedAt = Date.now();
          machines = data.machineIds.length;
          void writeLocal(key, { catalog: data, syncedAt }, localVersion).catch(
            () => {
              if (active && !saveErrorShown) {
                saveErrorShown = true;
                showToast('本地数据保存失败，下次启动可能需要重新同步');
              }
            },
          );
        }
        const loading = ['starting', 'syncing', 'background'].includes(
          event.state,
        );
        const connected = !['offline', 'failed', 'stopped'].includes(
          event.state,
        );
        if (!connected) state = 'offline';
        else if (loading) state = 'syncing';
        else state = 'live';
        setSnapshot((old) => ({
          key,
          catalog: data ?? (old.key === key ? old.catalog : empty),
          loading,
          connected,
          syncedAt: syncedAt ?? old.syncedAt,
        }));
        publishConnection({ state, machines, syncedAt });
      },
    );
    return () => {
      active = false;
      stop();
    };
  }, [key, revision, localReady]);
  const cached =
    selected?.id === initialWorkspace && valid(initialCatalog)
      ? initialCatalog.catalog
      : empty;
  const current =
    snapshot.key === key
      ? snapshot
      : { catalog: cached, loading: true, connected: true };
  function setWorkspaceId(id: string) {
    if (!account) return;
    setChoice({ user: account.user.id, workspace: id });
    void writeLocal(selectionKey(account.user.id), id).catch(() =>
      showToast('未能保存工作区选择'),
    );
  }
  return {
    ...current,
    serverSessions: current.catalog.sessions,
    catalog: {
      ...current.catalog,
      sessions: [
        ...current.catalog.sessions,
        ...pending.records
          .filter(
            (record) =>
              !current.catalog.sessions.some(
                (session) => session.id === record.session.id,
              ),
          )
          .map((record) => record.session),
      ],
    },
    selected,
    setWorkspaceId,
    refresh: () => setRevision((n) => n + 1),
  };
}
const Context = createContext<ReturnType<typeof useCatalogState> | null>(null);
export function CatalogProvider({ children }: PropsWithChildren) {
  const value = useCatalogState();
  return <Context value={value}>{children}</Context>;
}
export function useCatalog() {
  const value = useContext(Context);
  if (!value) throw new Error('Missing CatalogProvider');
  return value;
}

export { Context as CatalogContext };
