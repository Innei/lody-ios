import { createContext, use, useSyncExternalStore } from 'react';
import {
  unknownPresence,
  type MachinePresence,
} from '@lody/cloud-runtime/models/machines';
import {
  getCatalogStore,
  subscribeCatalogStore,
  type WorkspacePresence,
} from './store.ts';

const Context = createContext<WorkspacePresence | null>(null);
const snapshot = () => getCatalogStore().presence;

export function useMachinePresence(
  workspaceId: string | undefined,
): MachinePresence {
  const native = useSyncExternalStore(
    subscribeCatalogStore,
    snapshot,
    snapshot,
  );
  const current = use(Context) ?? native;
  return current.workspaceId === workspaceId
    ? current.presence
    : unknownPresence;
}

export { Context as MachinePresenceContext };
