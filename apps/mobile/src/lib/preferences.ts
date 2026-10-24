import { useSyncExternalStore } from 'react';
import { addPreferencesListener, readPreferencesRaw } from '@lody-ios/kit';
import type { QuickReply } from '@lody/cloud-runtime/models/settings';

export type Preferences = {
  accentColor: string;
  darkBackground: string;
  queuedMessageBehavior: string;
  quickReplies: QuickReply[];
};

const fallback: Preferences = {
  accentColor: 'blue',
  darkBackground: 'soft',
  queuedMessageBehavior: 'queue',
  quickReplies: [],
};

function parse(json: string): Preferences {
  try {
    return { ...fallback, ...(JSON.parse(json) as Partial<Preferences>) };
  } catch {
    return fallback;
  }
}

let current = parse(readPreferencesRaw());
const listeners = new Set<() => void>();
let subscription: { remove(): void } | null = null;

function publish(next: Preferences) {
  current = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  if (!subscription) {
    subscription = addPreferencesListener(({ json }) => publish(parse(json)));
    current = parse(readPreferencesRaw());
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size || !subscription) return;
    subscription.remove();
    subscription = null;
  };
}

const snapshot = () => current;

export function usePreferences() {
  return useSyncExternalStore(subscribe, snapshot, snapshot);
}

export function setPreferences(patch: Partial<Preferences>) {
  publish({ ...current, ...patch });
}
