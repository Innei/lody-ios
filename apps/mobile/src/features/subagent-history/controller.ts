import {
  type SubagentHistoryFragment,
  type SubagentHistoryPage,
  type SubagentIdentity,
} from '@lody/cloud-runtime/models/subagent-history';
import type { SubagentHistoryService } from '../../cloud/subagent-history.ts';

export type SubagentHistorySnapshot = {
  identity?: SubagentIdentity;
  page?: SubagentHistoryPage;
  fragments: SubagentHistoryFragment[];
  status: 'loading' | 'ready' | 'unsupported' | 'failed';
  loadingMore: boolean;
  error: boolean;
  paused?: boolean;
};

let nextSubscription = 0;

function joinFragments(fragments: SubagentHistoryFragment[]) {
  const byPosition = new Map<string, SubagentHistoryFragment>();
  for (const fragment of fragments)
    byPosition.set(`${fragment.index}:${fragment.offset ?? 0}`, fragment);
  return [...byPosition.values()].sort(
    (a, b) => a.index - b.index || (a.offset ?? 0) - (b.offset ?? 0),
  );
}

function containsStart(
  page: SubagentHistoryPage,
  start: SubagentHistoryFragment | undefined,
) {
  if (!start || !page.nextCursor) return true;
  const first = page.fragments[0];
  return (
    !!first &&
    (first.index < start.index ||
      (first.index === start.index &&
        (first.offset ?? 0) <= (start.offset ?? 0)))
  );
}

export function createSubagentHistoryController(
  service: SubagentHistoryService,
) {
  let snapshot: SubagentHistorySnapshot = {
    fragments: [],
    status: 'loading',
    loadingMore: false,
    error: false,
  };
  const listeners = new Set<() => void>();
  let epoch = 0;
  let disposed = false;
  let subscriptionId = '';
  let generation: number | undefined;
  let refreshing = false;
  let watching = false;
  let refreshAgain = false;
  let disconnect: (() => void) | undefined;
  const publish = (next: SubagentHistorySnapshot) => {
    if (disposed) return;
    snapshot = next;
    listeners.forEach((listener) => listener());
  };
  const release = (id: string) => {
    if (id) void service.unwatch(id).catch(() => {});
  };
  const accept = (page: SubagentHistoryPage, identity: SubagentIdentity) => {
    if (
      page.v !== 1 ||
      !Array.isArray(page.fragments) ||
      !Array.isArray(page.runs) ||
      page.identity.sessionId !== identity.sessionId ||
      page.identity.parentTurnId !== identity.parentTurnId ||
      page.identity.entryId !== identity.entryId ||
      page.identity.itemId !== identity.itemId ||
      page.identity.taskId !== identity.taskId ||
      (identity.runSessionId != null &&
        page.identity.runSessionId !== identity.runSessionId)
    )
      throw new Error('invalid_subagent_history');
  };

  const refresh = async () => {
    if (disposed || !snapshot.identity || !subscriptionId) return;
    if (refreshing || watching || snapshot.loadingMore) {
      refreshAgain = true;
      return;
    }
    refreshing = true;
    const at = epoch;
    const identity = snapshot.identity;
    const earliest = snapshot.fragments[0];
    try {
      let page = await service.page(identity);
      accept(page, identity);
      if (at !== epoch || disposed) return;
      let fragments = page.fragments;
      while (!containsStart(page, earliest) && page.nextCursor) {
        page = await service.page(page.identity, page.nextCursor);
        accept(page, identity);
        if (at !== epoch || disposed) return;
        fragments = [...page.fragments, ...fragments];
      }
      publish({
        identity: page.identity,
        page,
        fragments: joinFragments(fragments),
        status: page.status,
        loadingMore: false,
        error: false,
      });
    } catch {
      if (at === epoch) publish({ ...snapshot, status: 'failed', error: true });
    } finally {
      if (at === epoch) {
        refreshing = false;
        if (refreshAgain) {
          refreshAgain = false;
          void refresh();
        }
      }
    }
  };

  const select = async (identity: SubagentIdentity, keepHistory = false) => {
    if (disposed) return;
    release(subscriptionId);
    const at = ++epoch;
    const id = `subagent-${Date.now()}-${++nextSubscription}`;
    subscriptionId = id;
    refreshing = false;
    refreshAgain = false;
    watching = true;
    const retained = keepHistory ? snapshot.fragments : [];
    if (keepHistory)
      publish({
        ...snapshot,
        status: 'loading',
        loadingMore: false,
        error: false,
      });
    else
      publish({
        identity,
        fragments: [],
        status: 'loading',
        loadingMore: false,
        error: false,
      });
    try {
      const page = await service.watch(id, identity);
      accept(page, identity);
      if (at !== epoch || disposed) {
        release(id);
        return;
      }
      publish({
        identity: page.identity,
        page,
        fragments: keepHistory
          ? joinFragments([...retained, ...page.fragments])
          : page.fragments,
        status: page.status,
        loadingMore: false,
        error: false,
      });
      if (keepHistory && retained.length) refreshAgain = true;
    } catch {
      if (at === epoch && !disposed)
        publish({ ...snapshot, status: 'failed', error: true });
    } finally {
      if (at === epoch) {
        watching = false;
        if (refreshAgain) {
          refreshAgain = false;
          void refresh();
        }
      }
    }
  };

  return {
    getSnapshot: () => snapshot,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    start(identity: SubagentIdentity) {
      disconnect ??= service.subscribe((event) => {
        if (disposed) return;
        if (
          event.generation != null &&
          generation != null &&
          event.generation < generation
        )
          return;
        if (['stopped', 'failed'].includes(event.state ?? '')) {
          generation = event.generation ?? generation;
          release(subscriptionId);
          subscriptionId = '';
          epoch++;
          refreshing = false;
          publish({
            ...snapshot,
            page: undefined,
            fragments: [],
            status: 'failed',
            error: true,
            paused: true,
          });
          return;
        }
        if (
          event.subscriptionId === subscriptionId &&
          event.sessionId === snapshot.identity?.sessionId &&
          event.subagentHistory === 'changed'
        ) {
          void refresh();
          return;
        }
        if (event.sessionId !== snapshot.identity?.sessionId || !event.session)
          return;
        let status: string | undefined;
        try {
          status = JSON.parse(event.session).status;
        } catch {
          return;
        }
        const replaced =
          generation != null &&
          event.generation != null &&
          event.generation !== generation;
        generation = event.generation ?? generation;
        if (
          ['syncing', 'offline', 'failed', 'stopped'].includes(status ?? '')
        ) {
          if (snapshot.paused && !subscriptionId) return;
          release(subscriptionId);
          subscriptionId = '';
          epoch++;
          refreshing = false;
          publish({
            ...snapshot,
            status: 'failed',
            loadingMore: false,
            error: true,
            paused: true,
          });
          return;
        }
        if (
          status === 'live' &&
          snapshot.identity &&
          (replaced || !subscriptionId || snapshot.status === 'failed')
        )
          void select(snapshot.identity, !!snapshot.page);
      });
      return select(identity);
    },
    select: (identity: SubagentIdentity) => select(identity),
    retry: () =>
      snapshot.identity
        ? select(snapshot.identity, !!snapshot.page)
        : Promise.resolve(),
    async loadMore() {
      const cursor = snapshot.page?.nextCursor;
      const identity = snapshot.identity;
      if (
        !cursor ||
        !identity ||
        snapshot.loadingMore ||
        refreshing ||
        disposed
      )
        return;
      const at = epoch;
      publish({ ...snapshot, loadingMore: true, error: false });
      try {
        const page = await service.page(identity, cursor);
        accept(page, identity);
        if (at !== epoch || disposed) return;
        publish({
          ...snapshot,
          page: { ...snapshot.page!, nextCursor: page.nextCursor },
          fragments: joinFragments([...page.fragments, ...snapshot.fragments]),
          loadingMore: false,
          error: false,
        });
      } catch {
        if (at === epoch)
          publish({ ...snapshot, loadingMore: false, error: true });
      } finally {
        if (at === epoch && refreshAgain) {
          refreshAgain = false;
          void refresh();
        }
      }
    },
    dispose() {
      disposed = true;
      epoch++;
      disconnect?.();
      release(subscriptionId);
      listeners.clear();
    },
  };
}
