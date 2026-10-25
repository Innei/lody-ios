import { useSyncExternalStore } from 'react';
import {
  addOutboxListener,
  outboxPut,
  outboxRemove,
  readOutboxRaw,
} from '@lody-ios/kit';
import type { PendingSession } from '../../models/send.ts';
import { localGeneration, parseLocal } from '../kv.ts';

export type { PendingSend, PendingSession } from '../../models/send.ts';
type Snapshot = { records: readonly PendingSession[]; ready: boolean };
const stores = new Map<string, ReturnType<typeof createStore>>();
let storeGeneration = localGeneration();
const expired = () => Promise.reject(new Error('pending_send_scope_expired'));

function createStore(userId: string, workspaceId: string, generation: number) {
  const key =
    userId && workspaceId ? `pending-sends:${userId}:${workspaceId}` : '';
  let raw = '';
  let native: Snapshot = { records: [], ready: !key };
  let snapshot = native;
  let tokens = 0;
  const overlay = new Map<string, { record?: PendingSession; token: number }>();
  const listeners = new Set<() => void>();
  let subscription: { remove(): void } | null = null;
  const refresh = () => {
    if (!key) return false;
    const next = readOutboxRaw(userId, workspaceId);
    if (next === raw) return false;
    raw = next;
    const parsed = parseLocal<Snapshot>(next);
    native = {
      records: Array.isArray(parsed?.records) ? parsed.records : [],
      ready: parsed?.ready === true,
    };
    return true;
  };
  const compose = () => {
    let records = native.records;
    for (const [sessionId, { record }] of overlay) {
      records = records.filter((item) => item.session.id !== sessionId);
      if (record) records = [...records, record];
    }
    snapshot = overlay.size ? { records, ready: native.ready } : native;
  };
  const notify = () => {
    compose();
    listeners.forEach((listener) => listener());
  };
  refresh();
  compose();
  function change(
    sessionId: string,
    record: PendingSession | undefined,
    request: () => Promise<void>,
  ) {
    if (!key || generation !== localGeneration()) return expired();
    const token = ++tokens;
    overlay.delete(sessionId);
    overlay.set(sessionId, { record, token });
    notify();
    const settle = () => {
      if (overlay.get(sessionId)?.token === token) overlay.delete(sessionId);
      refresh();
      notify();
    };
    return request().then(settle, (error: unknown) => {
      settle();
      throw error;
    });
  }
  return {
    getSnapshot: () => {
      if (!subscription && refresh()) compose();
      return snapshot;
    },
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      if (key && !subscription) {
        subscription = addOutboxListener((event) => {
          if (event.key === key && refresh()) notify();
        });
        if (refresh()) compose();
      }
      return () => {
        listeners.delete(listener);
        if (listeners.size || !subscription) return;
        subscription.remove();
        subscription = null;
      };
    },
    put: (record: PendingSession) => {
      const json = JSON.stringify(record);
      return change(record.session.id, JSON.parse(json) as PendingSession, () =>
        outboxPut(userId, workspaceId, json),
      );
    },
    remove: (sessionId: string) =>
      change(sessionId, undefined, () =>
        outboxRemove(userId, workspaceId, sessionId),
      ),
  };
}

export function getPendingSendStore(userId: string, workspaceId: string) {
  const generation = localGeneration();
  if (storeGeneration !== generation) {
    stores.clear();
    storeGeneration = generation;
  }
  const key = userId && workspaceId ? `${userId}:${workspaceId}` : '';
  let store = stores.get(key);
  if (!store) {
    store = createStore(userId, workspaceId, generation);
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
