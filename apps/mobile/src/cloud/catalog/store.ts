import {
  addCatalogListener,
  readCatalogRaw,
  readCatalogStateRaw,
} from '@lody-ios/kit';
import type {
  Catalog,
  Connection,
  SavedCatalog,
  Session,
} from '@lody/cloud-runtime/models/catalog';
import {
  unknownPresence,
  type MachinePresence,
} from '@lody/cloud-runtime/models/machines';
import { parseLocal } from '../kv.ts';

export type WorkspacePresence = {
  workspaceId: string;
  presence: MachinePresence;
};
type NativeCatalogState = {
  userId: string;
  workspaceId: string;
  key: string;
  loading: boolean;
  connected: boolean;
  syncedAt?: number;
  catalogRevision: number;
  connection: Connection;
  presence: WorkspacePresence;
  pendingSessions: Session[];
};
export type CatalogStoreState = Omit<NativeCatalogState, 'catalogRevision'> & {
  catalog: Catalog;
};

export const emptyCatalog: Catalog = {
  projects: [],
  sessions: [],
  machineIds: [],
};
const fallback: NativeCatalogState = {
  userId: '',
  workspaceId: '',
  key: '',
  loading: false,
  connected: false,
  catalogRevision: -1,
  connection: { state: 'syncing', machines: 0 },
  presence: { workspaceId: '', presence: unknownPresence },
  pendingSessions: [],
};

let catalogRevision = -1;
let catalog = emptyCatalog;
let current = read(readCatalogStateRaw(), null);
const listeners = new Set<() => void>();
let subscription: { remove(): void } | null = null;

function valid(saved: SavedCatalog | null): saved is SavedCatalog {
  return (
    !!saved &&
    Array.isArray(saved.catalog?.projects) &&
    Array.isArray(saved.catalog?.sessions) &&
    Array.isArray(saved.catalog?.machineIds)
  );
}

function read(
  json: string,
  previous: CatalogStoreState | null,
): CatalogStoreState {
  const parsed = parseLocal<Partial<NativeCatalogState>>(json);
  const {
    catalogRevision: revision,
    presence,
    connection,
    pendingSessions,
    ...state
  } = { ...fallback, ...parsed };
  if (revision !== catalogRevision) {
    catalogRevision = revision;
    const saved = parseLocal<SavedCatalog>(readCatalogRaw());
    catalog = valid(saved) ? saved.catalog : emptyCatalog;
  }
  const same = (a: unknown, b: unknown) =>
    JSON.stringify(a) === JSON.stringify(b);
  return {
    ...state,
    catalog,
    connection:
      previous && same(previous.connection, connection)
        ? previous.connection
        : connection,
    presence:
      previous && same(previous.presence, presence)
        ? previous.presence
        : presence,
    pendingSessions:
      previous && same(previous.pendingSessions, pendingSessions)
        ? previous.pendingSessions
        : pendingSessions,
  };
}

export function subscribeCatalogStore(listener: () => void) {
  listeners.add(listener);
  if (!subscription) {
    subscription = addCatalogListener(({ json }) => {
      current = read(json, current);
      for (const item of listeners) item();
    });
    current = read(readCatalogStateRaw(), current);
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size || !subscription) return;
    subscription.remove();
    subscription = null;
  };
}

export const getCatalogStore = () => current;

export function readCatalogStore() {
  if (!subscription) current = read(readCatalogStateRaw(), current);
  return current;
}
