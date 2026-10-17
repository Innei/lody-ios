import { useSyncExternalStore } from 'react';

export type LayoutMode = 'compact' | 'tall' | 'wide';

export type LayoutTraits = {
  horizontal: 'compact' | 'regular';
  width: number;
  height: number;
};

export function layoutModeFor(traits: LayoutTraits): LayoutMode {
  if (traits.horizontal === 'compact') return 'compact';
  return traits.width >= traits.height ? 'wide' : 'tall';
}

// Only covers the first frame; the native size class replaces it immediately.
const regularGuessWidth = 600;

export function guessLayoutTraits(width: number, height: number): LayoutTraits {
  return {
    horizontal: width >= regularGuessWidth ? 'regular' : 'compact',
    width,
    height,
  };
}

let mode: LayoutMode = 'compact';
const listeners = new Set<() => void>();

export function setLayoutTraits(traits: LayoutTraits) {
  const next = layoutModeFor(traits);
  if (next === mode) return;
  mode = next;
  for (const listener of listeners) listener();
}

export function getLayoutMode(): LayoutMode {
  return mode;
}

export function subscribeLayoutMode(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function useLayoutMode(): LayoutMode {
  return useSyncExternalStore(subscribeLayoutMode, getLayoutMode);
}
