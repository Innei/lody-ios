import type { PageDefinitionBase, PagePresentationOptions } from './page';
import {
  present,
  type PresentationResult,
  type PresentPage,
} from './presentationStore.ts';

export type PanelMode = 'push' | 'replace';

export interface PanelEntry {
  key: number;
  page: PageDefinitionBase;
  params: unknown;
  presentation: PagePresentationOptions;
  settle: (result: PresentationResult<unknown>) => void;
}

let nextKey = 1;
let entries: readonly PanelEntry[] = [];
const listeners = new Set<() => void>();

function commit(next: readonly PanelEntry[]) {
  entries = next;
  for (const listener of listeners) listener();
}

function sameParams(a: unknown, b: unknown) {
  if (a === b) return true;
  if (!a || !b || typeof a !== 'object' || typeof b !== 'object') return false;
  const left = a as Record<string, unknown>;
  const right = b as Record<string, unknown>;
  const keys = Object.keys(left);
  return (
    keys.length === Object.keys(right).length &&
    keys.every((key) => left[key] === right[key])
  );
}

const cancelled: PresentationResult<never> = { status: 'cancelled' };

export function openPanel<TResult = unknown>(
  page: PageDefinitionBase,
  params: unknown,
  mode: PanelMode,
  options?: Partial<PagePresentationOptions>,
): Promise<PresentationResult<TResult>> {
  const root = entries[0];
  if (
    mode === 'replace' &&
    entries.length === 1 &&
    root.page.id === page.id &&
    sameParams(root.params, params)
  )
    return Promise.resolve(cancelled);

  return new Promise((resolve) => {
    const entry: PanelEntry = {
      key: nextKey++,
      page,
      params,
      presentation: { ...page.presentation, ...options },
      settle: resolve as (result: PresentationResult<unknown>) => void,
    };
    if (mode === 'push') {
      commit([...entries, entry]);
      return;
    }
    const replaced = entries;
    commit([entry]);
    for (const old of replaced) old.settle(cancelled);
  });
}

export function popPanel(key: number, result: PresentationResult<unknown>) {
  const index = entries.findIndex((entry) => entry.key === key);
  if (index < 0) return;
  const removed = entries.slice(index);
  commit(entries.slice(0, index));
  removed[0].settle(result);
  for (const entry of removed.slice(1)) entry.settle(cancelled);
}

export function closePanel() {
  if (!entries.length) return;
  const removed = entries;
  commit([]);
  for (const entry of removed) entry.settle(cancelled);
}

export function getPanelEntries(): readonly PanelEntry[] {
  return entries;
}

export function subscribePanel(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function panelPresent(mode: PanelMode): PresentPage {
  return ((page: PageDefinitionBase, ...args: unknown[]) => {
    const [params, options] = args as [
      unknown,
      Partial<PagePresentationOptions> | undefined,
    ];
    if (page.panel) return openPanel(page, params, mode, options);
    return (present as (...values: unknown[]) => unknown)(page, ...args);
  }) as PresentPage;
}
