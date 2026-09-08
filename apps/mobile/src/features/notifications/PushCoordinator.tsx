import { useEffect, useRef, useState } from 'react';
import { router, useRootNavigationState } from 'expo-router';
import {
  acknowledgePushClick,
  addPushClickListener,
  pendingPushClick,
  setPushUser,
  type PushClick,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { useCatalog } from '@/cloud/catalog/CatalogProvider';
const uiVerify = __DEV__ && process.env.EXPO_PUBLIC_UI_VERIFY === '1';
import { requestOpenSession } from '@/features/sessions/sessionNav';
import { showToast } from '@/ui/toast';
import { resolveNotificationClick } from './routing';

export function PushCoordinator() {
  const auth = useAuth();
  const catalog = useCatalog();
  const navigation = useRootNavigationState();
  const [click, setClick] = useState<PushClick | null>(null);
  const handled = useRef('');
  useEffect(() => {
    if (uiVerify) return;
    let active = true;
    const read = () => {
      void pendingPushClick()
        .then((value) => {
          if (active) setClick(value);
        })
        .catch(() => {});
    };
    const listener = addPushClickListener(read);
    read();
    return () => {
      active = false;
      listener.remove();
    };
  }, []);
  useEffect(() => {
    if (uiVerify || !auth.localReady || auth.busy) return;
    void setPushUser(auth.account?.user.id ?? null).catch(() =>
      showToast('通知账号同步失败，请重新打开 App'),
    );
  }, [auth.localReady, auth.busy, auth.account?.user.id]);
  useEffect(() => {
    if (!click || handled.current === click.id) return;
    const destination = resolveNotificationClick(click, {
      ready: !!navigation?.key && auth.localReady && !auth.busy,
      userId: auth.account?.user.id,
      workspaces: auth.account?.workspaces ?? [],
      selectedId: catalog.selected?.id,
      loading: catalog.loading,
      connected: catalog.connected,
      sessions: catalog.catalog.sessions,
    });
    if (destination.kind === 'wait') return;
    if (destination.kind === 'workspace') {
      router.dismissAll();
      router.replace('/');
      catalog.setWorkspaceId(destination.id);
      return;
    }
    handled.current = click.id;
    void acknowledgePushClick(click.id).catch(() => {});
    if (destination.kind === 'discard') showToast(destination.reason);
    else void requestOpenSession(destination.session);
    setClick(null);
  }, [
    click,
    auth.localReady,
    auth.busy,
    auth.account,
    navigation?.key,
    catalog,
  ]);
  return null;
}
