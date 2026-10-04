import { useSyncExternalStore } from 'react';
import {
  unknownPresence,
  type MachinePresence,
} from '../../models/machines.ts';

let current = { workspaceId: '', presence: unknownPresence };
const listeners = new Set<() => void>();

export function publishMachinePresence(
  workspaceId: string,
  presence: MachinePresence = unknownPresence,
) {
  if (
    workspaceId === current.workspaceId &&
    JSON.stringify(presence) === JSON.stringify(current.presence)
  )
    return;
  current = { workspaceId, presence };
  for (const listener of listeners) listener();
}

export function useMachinePresence(workspaceId: string | undefined) {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    () =>
      current.workspaceId === workspaceId ? current.presence : unknownPresence,
    () => unknownPresence,
  );
}
