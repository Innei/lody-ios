import { parseNotificationRoute, routeFromDeepLink } from './routing.ts';

let nextId = 0;
let pending: { id: string; route: string } | null = null;
const listeners = new Set<() => void>();

export function redirectSystemPath({
  path,
  initial,
}: {
  path: string;
  initial: boolean;
}): string | null {
  const route = routeFromDeepLink(path) ?? path;
  if (!parseNotificationRoute(route)) return path;
  pending = { id: `link:${++nextId}`, route };
  for (const notify of listeners) notify();
  // The coordinator resolves the catalog before opening a page. Never let the
  // same URL also navigate to an unmatched route underneath that page.
  return initial ? '/' : null;
}

export function pendingDeepLink() {
  return pending;
}

export function subscribeDeepLinks(notify: () => void) {
  listeners.add(notify);
  return () => {
    listeners.delete(notify);
  };
}

export function acknowledgeDeepLink(id: string) {
  if (pending?.id !== id) return;
  pending = null;
  for (const notify of listeners) notify();
}
