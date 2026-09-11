import { localGeneration, readLocal, writeLocal } from '../../cloud/kv.ts';
import type { SessionViews } from './sessionViews.ts';

const stores = new Map<string, ReturnType<typeof createSessionViewStore>>();
let storeGeneration = localGeneration();

export function createSessionViewStore(key: string) {
  const generation = localGeneration();
  let snapshot: SessionViews = {};
  let durable: SessionViews = {};
  const listeners = new Set<() => void>();
  const current = () => !!key && generation === localGeneration();
  const publish = (next: SessionViews) => {
    snapshot = next;
    listeners.forEach((listener) => listener());
  };
  const ready = key
    ? readLocal<SessionViews>(key).then((saved) => {
        if (!current()) return;
        const merged = { ...snapshot };
        const restored: Record<string, number> = {};
        if (saved && typeof saved === 'object' && !Array.isArray(saved)) {
          for (const [id, at] of Object.entries(saved)) {
            if (typeof at === 'number' && Number.isFinite(at)) {
              merged[id] = Math.max(merged[id] ?? -Infinity, at);
              restored[id] = at;
            }
          }
        }
        durable = restored;
        publish(merged);
      })
    : Promise.resolve();
  return {
    ready,
    getSnapshot: () => snapshot,
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    async markViewed(sessionId: string, lastMessageAt?: number) {
      if (
        !current() ||
        lastMessageAt === undefined ||
        !Number.isFinite(lastMessageAt)
      )
        return;
      if ((durable[sessionId] ?? -Infinity) >= lastMessageAt) return;
      // Use the message watermark, not the device clock: future messages must
      // regain emphasis even when the device clock is ahead of the server.
      if ((snapshot[sessionId] ?? -Infinity) < lastMessageAt)
        publish({ ...snapshot, [sessionId]: lastMessageAt });
      await ready;
      if (current()) {
        const next = snapshot;
        await writeLocal(key, next, generation);
        if (current()) durable = next;
      }
    },
  };
}

export function getSessionViewStore(userId: string, workspaceId: string) {
  const generation = localGeneration();
  if (storeGeneration !== generation) {
    stores.clear();
    storeGeneration = generation;
  }
  const key =
    userId && workspaceId
      ? `session-views:${JSON.stringify([userId, workspaceId])}`
      : '';
  let store = stores.get(key);
  if (!store) {
    store = createSessionViewStore(key);
    stores.set(key, store);
  }
  return store;
}
