import { uiVerify } from '@/features/debug/uiVerify';
import {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
  type PropsWithChildren,
} from 'react';
import { showToast } from '@/ui/toast';
import {
  runtimeInfo,
  readAuthToken,
  readLocalStartup,
  saveAuthToken,
  clearAuthToken,
  openAuthBrowser,
  closeAuthBrowser,
} from '@lody-ios/kit';
import {
  AuthError,
  authRequest,
  getAccount,
  requestDeviceCode,
  pollDeviceToken,
  type DeviceCode,
  type User,
  type Workspace,
} from '@/cloud/auth';

import {
  writeLocal,
  parseLocal,
  clearLocal,
  type SavedAccount,
  type SavedCatalog,
} from '@/cloud/local';

type Account = { token: string; user: User; workspaces: Workspace[] };
type AuthState = {
  account: Account | null;
  busy: boolean;
  localReady: boolean;
  initialWorkspace: string;
  initialCatalog: SavedCatalog | null;
  code: DeviceCode | null;
  error: string | null;
};
type AuthContextValue = AuthState & {
  login: () => Promise<void>;
  cancel: () => void;
  restore: () => Promise<void>;
  logout: () => Promise<void>;
  reopen: () => Promise<void>;
};
const Context = createContext<AuthContextValue | null>(null);
export function AuthProvider({ children }: PropsWithChildren) {
  const [state, setState] = useState<AuthState>({
    account: null,
    busy: true,
    localReady: false,
    initialWorkspace: '',
    initialCatalog: null,
    code: null,
    error: null,
  });
  const pending = useRef<AbortController | null>(null);
  const alive = useRef(true);
  const begin = () => {
    pending.current?.abort();
    const controller = new AbortController();
    pending.current = controller;
    return controller.signal;
  };
  const update = (signal: AbortSignal, next: Partial<AuthState>) => {
    if (alive.current && !signal.aborted) setState((s) => ({ ...s, ...next }));
  };
  async function restore() {
    const signal = begin();
    if (uiVerify) {
      update(signal, { busy: false, localReady: true });
      return;
    }
    update(signal, { busy: true, error: null });
    try {
      const localStarted = performance.now();
      const [token, boot] = await Promise.all([
        readAuthToken(),
        readLocalStartup().catch(
          () =>
            ({}) as { account?: string; workspace?: string; catalog?: string },
        ),
      ]);
      if (signal.aborted) return;
      const saved = parseLocal<SavedAccount>(boot.account);
      if (token && saved?.user?.id && Array.isArray(saved.workspaces)) {
        const initialCatalog = parseLocal<SavedCatalog>(boot.catalog);
        if (__DEV__)
          console.info(
            `LodyLocal hydrate_ms=${(performance.now() - localStarted).toFixed(2)}`,
          );
        update(signal, {
          account: { token, ...saved },
          localReady: true,
          initialWorkspace: boot.workspace ?? '',
          initialCatalog,
        });
      } else update(signal, { localReady: true });
      if (!token) {
        update(signal, { account: null });
        return;
      }
      // Match the native grant failure probe without changing product endpoints.
      if (__DEV__ && runtimeInfo.offlineProbe) throw new Error('网络不可用');
      const account = await getAccount(token, signal);
      if (signal.aborted) return;
      if (saved && saved.user.id !== account.user.id) {
        await clearLocal();
        update(signal, { initialCatalog: null, initialWorkspace: '' });
      }
      await writeLocal('account', account).catch(() =>
        showToast('本地账号保存失败，下次启动可能需要联网恢复'),
      );
      update(signal, { account: { token, ...account } });
    } catch (error) {
      if (error instanceof AuthError && !signal.aborted) {
        update(signal, { account: null, initialCatalog: null });
        await Promise.all([clearLocal(), clearAuthToken()]).catch(() =>
          showToast('无法完全清除本地登录信息，请重试'),
        );
      }
      update(signal, {
        error: error instanceof Error ? error.message : '登录恢复失败',
      });
    } finally {
      update(signal, { busy: false, localReady: true });
    }
  }
  async function login() {
    if (uiVerify)
      throw new Error('Login is disabled during offline UI verification');
    const signal = begin();
    update(signal, { busy: true, code: null, error: null });
    try {
      const code = await requestDeviceCode(signal);
      update(signal, { code });
      if (signal.aborted) throw new Error('已取消');
      await openAuthBrowser(code.verification_uri_complete);
      const token = await pollDeviceToken(code, signal);
      const account = await getAccount(token, signal);
      if (signal.aborted) throw new Error('已取消');
      await clearLocal();
      await saveAuthToken(token);
      await writeLocal('account', account).catch(() =>
        showToast('本地账号保存失败，下次启动可能需要联网恢复'),
      );
      if (signal.aborted) throw new Error('已取消');
      update(signal, { account: { token, ...account }, code: null });
    } catch (error) {
      update(signal, {
        error: error instanceof Error ? error.message : '登录失败',
        code: null,
      });
    } finally {
      if (!signal.aborted) {
        await closeAuthBrowser();
        update(signal, { busy: false, localReady: true });
      }
    }
  }
  function cancel() {
    pending.current?.abort();
    void closeAuthBrowser();
    setState((s) => ({ ...s, busy: false, code: null }));
  }
  async function logout() {
    const token = state.account?.token,
      signal = begin();
    update(signal, { busy: true, error: null });
    try {
      update(signal, { account: null, code: null, initialCatalog: null });
      await Promise.all([clearLocal(), clearAuthToken()]);
      if (token) await authRequest('/sign-out', { token, body: {}, signal });
    } catch {
      update(signal, {
        error: '退出未完全完成，请重试；本机凭据是否清除以当前登录状态为准',
      });
    } finally {
      update(signal, { busy: false, localReady: true });
    }
  }
  async function reopen() {
    if (!state.code) return;
    try {
      await openAuthBrowser(state.code.verification_uri_complete);
    } catch {
      setState((s) => ({ ...s, error: '无法打开授权页，请取消后重试' }));
    }
  }
  useEffect(() => {
    alive.current = true;
    void restore();
    return () => {
      alive.current = false;
      pending.current?.abort();
      void closeAuthBrowser();
    };
  }, []);
  return (
    <Context value={{ ...state, login, cancel, restore, logout, reopen }}>
      {children}
    </Context>
  );
}
export function useAuth() {
  const value = useContext(Context);
  if (!value) throw new Error('Missing AuthProvider');
  return value;
}

export { Context as AuthContext };
