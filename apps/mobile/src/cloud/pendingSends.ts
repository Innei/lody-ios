import { useSyncExternalStore } from 'react';
import type { ChatDraftAttachment } from '@lody-ios/kit';
import type { Session } from './model';
import { localGeneration, readLocal, writeLocal } from './local';

export type PendingSend = {
  id: string;
  text: string;
  attachments: ChatDraftAttachment[];
  phase:
    | 'waiting'
    | 'creating'
    | 'sending'
    | 'accepted'
    | 'uploaded'
    | 'unknown'
    | 'failed';
  reason?: string;
  creation?: string;
  choice: {
    modelId?: string | null;
    effort?: string | null;
    modeId?: string;
    reasoningEffortConfigId?: string;
  };
};
export type PendingSession = { session: Session; send: PendingSend };
type Snapshot = { records: readonly PendingSession[]; ready: boolean };
const stores = new Map<string, ReturnType<typeof createStore>>();
let storeGeneration = localGeneration();

function createStore(key: string, generation: number) {
  let snapshot: Snapshot = { records: [], ready: !key };
  let durable: readonly PendingSession[] = [];
  const touched = new Set<string>();
  const listeners = new Set<() => void>();
  const publish = (
    records: readonly PendingSession[],
    ready = snapshot.ready,
  ) => {
    snapshot = { records, ready };
    listeners.forEach((listener) => listener());
  };
  const current = () => {
    if (!key || generation !== localGeneration())
      throw new Error('pending_send_scope_expired');
  };
  let writes = key
    ? readLocal<PendingSession[]>(key).then((saved) => {
        if (generation !== localGeneration()) return;
        durable = (Array.isArray(saved) ? saved : [])
          .filter(
            (record) =>
              record?.session?.id &&
              record.send?.id &&
              typeof record.send.text === 'string' &&
              Array.isArray(record.send.attachments) &&
              record.send.choice,
          )
          .map((record) => {
            if (
              record.send.phase !== 'creating' &&
              record.send.phase !== 'sending'
            )
              return record;
            return {
              ...record,
              send: {
                ...record.send,
                phase: 'unknown' as const,
                reason: '操作结果待确认，请等待同步，不要重复发送。',
              },
            };
          });
        publish(
          [
            ...durable.filter((record) => !touched.has(record.session.id)),
            ...snapshot.records,
          ],
          true,
        );
      })
    : Promise.resolve();
  function change(sessionId: string, record?: PendingSession) {
    try {
      current();
    } catch (error) {
      return Promise.reject(error);
    }
    const replace = (records: readonly PendingSession[]) => {
      const next = records.filter((item) => item.session.id !== sessionId);
      if (record) next.push(record);
      return next;
    };
    touched.add(sessionId);
    publish(replace(snapshot.records));
    const write = writes.then(async () => {
      current();
      const next = replace(durable);
      await writeLocal(key, next, generation);
      current();
      durable = next;
    });
    writes = write.catch(() => {});
    return write;
  }
  return {
    getSnapshot: () => snapshot,
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    put: (record: PendingSession) => {
      const copy: PendingSession = {
        session: { ...record.session },
        send: {
          ...record.send,
          choice: { ...record.send.choice },
          attachments: record.send.attachments.map((attachment) => ({
            ...attachment,
          })),
        },
      };
      return change(copy.session.id, copy);
    },
    remove: (sessionId: string) => change(sessionId),
  };
}

export function getPendingSendStore(userId: string, workspaceId: string) {
  const generation = localGeneration();
  if (storeGeneration !== generation) {
    stores.clear();
    storeGeneration = generation;
  }
  const key =
    userId && workspaceId ? `pending-sends:${userId}:${workspaceId}` : '';
  let store = stores.get(key);
  if (!store) {
    store = createStore(key, generation);
    stores.set(key, store);
  }
  return store;
}

export function usePendingSends(userId: string, workspaceId: string) {
  const store = getPendingSendStore(userId, workspaceId);
  const snapshot = useSyncExternalStore(
    store.subscribe,
    store.getSnapshot,
    store.getSnapshot,
  );
  return {
    ...snapshot,
    put: store.put,
    remove: store.remove,
    getSnapshot: store.getSnapshot,
  };
}
