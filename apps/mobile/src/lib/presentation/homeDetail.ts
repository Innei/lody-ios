import { useSyncExternalStore } from 'react';

import { getLayoutMode } from './layoutMode.ts';
import { closePanel } from './panelStore.ts';

export type HomeDetail<T> = { value: T; request: number; scope: string };

let detail: HomeDetail<unknown> | undefined;
let request = 0;
const listeners = new Set<() => void>();

export function homeScope(accountId?: string, workspaceId?: string) {
  return JSON.stringify([accountId, workspaceId]);
}

export function setHomeDetail(value: unknown, scope = '') {
  detail =
    value === undefined ? undefined : { value, request: ++request, scope };
  for (const listener of listeners) listener();
}

// Readers render the new scope before the old detail can be cleared, so a
// detail from another account or workspace must already read as empty.
export function getHomeDetail<T>(scope: string): HomeDetail<T> | undefined {
  return detail?.scope === scope ? (detail as HomeDetail<T>) : undefined;
}

export function showHomeSession<T extends { session: { id: string } }>(
  value: T,
  scope: string,
  presentCompact: (value: T) => Promise<unknown>,
): Promise<unknown> {
  if (getLayoutMode() === 'compact') return presentCompact(value);
  if (getHomeDetail<T>(scope)?.value.session.id !== value.session.id)
    closePanel();
  setHomeDetail(value, scope);
  return Promise.resolve();
}

export function subscribeHomeDetail(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useHomeDetail<T>(scope: string): HomeDetail<T> | undefined {
  return useSyncExternalStore(subscribeHomeDetail, () =>
    getHomeDetail<T>(scope),
  );
}
