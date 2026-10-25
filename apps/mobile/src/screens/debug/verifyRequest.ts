import { useSyncExternalStore } from 'react';

export type VerifyRequest = { verifyCase?: string; request?: string };

let current: VerifyRequest = {};
const listeners = new Set<() => void>();

export function setVerifyRequest(next: VerifyRequest) {
  current = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useVerifyRequest() {
  return useSyncExternalStore(subscribe, () => current);
}
