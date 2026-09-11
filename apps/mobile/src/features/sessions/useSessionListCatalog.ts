import { useMemo, useSyncExternalStore } from 'react';
import type { Catalog } from '../../models/catalog.ts';
import { getSessionViewStore } from './sessionViewStore.ts';
import { withSessionViews } from './sessionViews.ts';

export function useSessionListCatalog(
  catalog: Catalog,
  userId: string,
  workspaceId: string,
) {
  const store = getSessionViewStore(userId, workspaceId);
  const views = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot,
  );
  return useMemo(() => withSessionViews(catalog, views), [catalog, views]);
}
