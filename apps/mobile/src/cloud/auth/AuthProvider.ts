import { createContext, use, useSyncExternalStore } from 'react';
import {
  addAuthListener,
  cancelAuth,
  loginAuth,
  logoutAuth,
  readAuthStateRaw,
  reopenAuthBrowser,
  restoreAuth,
  updateAuthWorkspace,
  updateAuthWorkspaceIcon,
  type PickedWorkspaceIcon,
} from '@lody-ios/kit';
import type { DeviceCode, SavedAccount } from '../../models/auth.ts';
import { parseLocal } from '../kv';
import { uiVerify } from '@/lib/uiVerify';

type AuthState = {
  account: SavedAccount | null;
  busy: boolean;
  localReady: boolean;
  initialWorkspace: string;
  code: DeviceCode | null;
  error: string | null;
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

const fallback: AuthState = {
  account: null,
  busy: true,
  localReady: false,
  initialWorkspace: '',
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

let current = read(readAuthStateRaw(), null);
const listeners = new Set<() => void>();
let subscription: { remove(): void } | null = null;

function read(
  json: string,
  previous: AuthContextValue | null,
): AuthContextValue {
  const state = { ...fallback, ...parseLocal<Partial<AuthState>>(json) };
  const account =
    previous &&
    JSON.stringify(previous.account) === JSON.stringify(state.account)
      ? previous.account
      : state.account;
  return { ...state, account, ...actions };
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
