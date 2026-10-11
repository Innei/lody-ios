import { useSyncExternalStore } from 'react';
import type { Connection } from '@lody/cloud-runtime/models/catalog';

export type { Connection } from '@lody/cloud-runtime/models/catalog';

const listeners = new Set<() => void>();
let connection: Connection = { state: 'syncing', machines: 0 };

export function publishConnection(next: Connection) {
  if (
    next.state === connection.state &&
    next.machines === connection.machines &&
    next.syncedAt === connection.syncedAt
  )
    return;
  connection = next;
  for (const listener of listeners) listener();
}

export function getConnection() {
  return connection;
}

export function useConnection() {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    getConnection,
    getConnection,
  );
}
