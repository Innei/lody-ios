import { createContext, use, useSyncExternalStore } from 'react';
import {
  addAuthListener,
  cancelAuth,
  loginAuth,
  logoutAuth,
  readAuthInitialCatalogRaw,
  readAuthStateRaw,
  reopenAuthBrowser,
  restoreAuth,
  updateAuthWorkspace,
  updateAuthWorkspaceIcon,
  type PickedWorkspaceIcon,
} from '@lody-ios/kit';
import type { DeviceCode, SavedAccount } from '../../models/auth.ts';
import type { SavedCatalog } from '@lody/cloud-runtime/models/catalog';
import { parseLocal } from '../kv';
import { uiVerify } from '@/lib/uiVerify';

type AuthState = {
  account: SavedAccount | null;
  busy: boolean;
  localReady: boolean;
  initialWorkspace: string;
  initialCatalog: SavedCatalog | null;
  code: DeviceCode | null;
  error: string | null;
};
type NativeAuthState = Omit<AuthState, 'initialCatalog'> & {
  catalogRevision: number;
};
type AuthContextValue = AuthState & {
  login: () => Promise<void>;
  cancel: () => void;
  restore: () => Promise<void>;
  logout: () => Promise<void>;
  reopen: () => Promise<void>;
  updateWorkspace: (workspaceId: string, name: string) => Promise<void>;
  updateWorkspaceIcon: (
    workspaceId: string,
    file: PickedWorkspaceIcon,
  ) => Promise<string>;
};

const fallback: NativeAuthState = {
  account: null,
  busy: true,
  localReady: false,
  initialWorkspace: '',
  catalogRevision: -1,
  code: null,
  error: null,
};

const actions = {
  login: async () => {
    if (uiVerify)
      throw new Error('Login is disabled during offline UI verification');
    await loginAuth();
  },
  cancel: () => void cancelAuth(),
  restore: restoreAuth,
  logout: logoutAuth,
  reopen: reopenAuthBrowser,
  updateWorkspace: updateAuthWorkspace,
  updateWorkspaceIcon: updateAuthWorkspaceIcon,
};

let catalogRevision = -1;
let initialCatalog: SavedCatalog | null = null;
let current = read(readAuthStateRaw(), null);
const listeners = new Set<() => void>();
let subscription: { remove(): void } | null = null;

function read(
  json: string,
  previous: AuthContextValue | null,
): AuthContextValue {
  const parsed = parseLocal<Partial<NativeAuthState>>(json);
  const { catalogRevision: revision, ...state } = { ...fallback, ...parsed };
  if (revision !== catalogRevision) {
    catalogRevision = revision;
    initialCatalog = parseLocal<SavedCatalog>(readAuthInitialCatalogRaw());
  }
  const account =
    previous &&
    JSON.stringify(previous.account) === JSON.stringify(state.account)
      ? previous.account
      : state.account;
  return { ...state, account, initialCatalog, ...actions };
}

function publish(json: string) {
  current = read(json, current);
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  if (!subscription) {
    subscription = addAuthListener(({ json }) => publish(json));
    current = read(readAuthStateRaw(), current);
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size || !subscription) return;
    subscription.remove();
    subscription = null;
  };
}

const snapshot = () => current;

const Context = createContext<AuthContextValue | null>(null);

export function useAuth() {
  const native = useSyncExternalStore(subscribe, snapshot, snapshot);
  return use(Context) ?? native;
}

export { Context as AuthContext };
