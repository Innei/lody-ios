import type { Session } from '@lody/cloud-runtime/models/catalog';
import type { PullRequestReference } from '@lody/cloud-runtime/models/pull-request';
import { localGeneration, readLocal, writeLocal } from '../../cloud/kv.ts';

export type AutoArchivePreferences = {
  onPrMerged: boolean;
  onPrClosed: boolean;
};
export const defaultAutoArchivePreferences: AutoArchivePreferences = {
  onPrMerged: false,
  onPrClosed: false,
};
export function parseAutoArchivePreferences(
  value: unknown,
): AutoArchivePreferences {
  const data =
    value && typeof value === 'object'
      ? (value as Record<string, unknown>)
      : {};
  return {
    onPrMerged: data.onPrMerged === true,
    onPrClosed: data.onPrClosed === true,
  };
}

type PrSnapshot = Pick<PullRequestReference, 'url' | 'status'>;
function latestPr(prs: Session['pullRequests']): PrSnapshot | undefined {
  let latest: PullRequestReference | undefined;
  for (const candidate of prs ?? []) {
    if (
      !latest ||
      !(candidate.reportedAt || latest.reportedAt) ||
      (candidate.reportedAt ?? '') > (latest.reportedAt ?? '')
    )
      latest = candidate;
  }
  return latest ? { url: latest.url, status: latest.status } : undefined;
}

export function createAutoArchiveObserver() {
  const previous = new Map<string, PrSnapshot>();
  return {
    observe(
      sessions: Session[],
      userId: string,
      preferences: AutoArchivePreferences,
    ) {
      const archive: Session[] = [];
      const seen = new Set<string>();
      for (const session of sessions) {
        if (!userId || session.userId !== userId) continue;
        seen.add(session.id);
        const current = latestPr(session.pullRequests);
        const before = previous.get(session.id);
        if (current) previous.set(session.id, current);
        else previous.delete(session.id);
        if (
          session.archived ||
          !current ||
          !before ||
          before.url !== current.url ||
          before.status === current.status
        )
          continue;
        if (
          (current.status === 'merged' && preferences.onPrMerged) ||
          (current.status === 'closed' && preferences.onPrClosed)
        )
          archive.push(session);
      }
      for (const id of previous.keys()) if (!seen.has(id)) previous.delete(id);
      return archive;
    },
  };
}

const stores = new Map<
  string,
  ReturnType<typeof createAutoArchivePreferencesStore>
>();
let storeGeneration = localGeneration();
export function createAutoArchivePreferencesStore(userId: string) {
  const generation = localGeneration();
  const key = userId ? `auto-archive:${JSON.stringify(userId)}` : '';
  const current = () => !!key && generation === localGeneration();
  const listeners = new Set<() => void>();
  let snapshot = { ready: !key, preferences: defaultAutoArchivePreferences };
  const publish = (preferences: AutoArchivePreferences) => {
    snapshot = { ready: true, preferences };
    listeners.forEach((listener) => listener());
  };
  const ready = key
    ? readLocal(key).then((saved) => {
        if (current()) publish(parseAutoArchivePreferences(saved));
      })
    : Promise.resolve();
  return {
    ready,
    getSnapshot: () => snapshot,
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    async update(preferences: AutoArchivePreferences) {
      await ready;
      if (!current()) throw new Error('auto_archive_scope_expired');
      const next = parseAutoArchivePreferences(preferences);
      await writeLocal(key, next, generation);
      if (!current()) throw new Error('auto_archive_scope_expired');
      publish(next);
    },
  };
}
export function getAutoArchivePreferencesStore(userId: string) {
  const generation = localGeneration();
  if (storeGeneration !== generation) {
    stores.clear();
    storeGeneration = generation;
  }
  let store = stores.get(userId);
  if (!store) {
    store = createAutoArchivePreferencesStore(userId);
    stores.set(userId, store);
  }
  return store;
}
