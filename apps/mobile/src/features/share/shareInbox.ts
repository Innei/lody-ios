const listeners = new Set<() => void>();

// `lody://share/…` only wakes the drain; the App Group inbox is the source of truth.
export function isShareLink(path: string) {
  return /^(lody:\/\/)?\/?share(\/[^?#]*)?$/i.test(path);
}

export function wakeShareInbox() {
  for (const notify of listeners) notify();
}

export function subscribeShareInbox(notify: () => void) {
  listeners.add(notify);
  return () => {
    listeners.delete(notify);
  };
}
