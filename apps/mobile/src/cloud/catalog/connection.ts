import { createContext, use, useSyncExternalStore } from 'react';
import type { Connection } from '@lody/cloud-runtime/models/catalog';
import {
  getCatalogStore,
  readCatalogStore,
  subscribeCatalogStore,
} from './store.ts';

export type { Connection } from '@lody/cloud-runtime/models/catalog';

const Context = createContext<Connection | null>(null);
const snapshot = () => getCatalogStore().connection;

export function getConnection() {
  return readCatalogStore().connection;
}

export function useConnection() {
  const native = useSyncExternalStore(
    subscribeCatalogStore,
    snapshot,
    snapshot,
  );
  return use(Context) ?? native;
}

export { Context as ConnectionContext };
