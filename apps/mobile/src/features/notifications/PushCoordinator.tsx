import { useEffect, useRef, useState } from 'react';
import { Linking } from 'react-native';
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
import { t } from '@/lib/i18n';
import { showToast } from '@/ui/toast';
import { resolveNotificationClick, routeFromDeepLink } from './routing';

export function PushCoordinator() {
  const auth = useAuth();
  const catalog = useCatalog();
  const navigation = useRootNavigationState();
  const [click, setClick] = useState<PushClick | null>(null);
  const [link, setLink] = useState<{ id: string; route: string } | null>(null);
  const links = useRef(0);
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
    if (uiVerify) return;
    const open = (url: string | null) => {
      const route = url && routeFromDeepLink(url);
      if (route) setLink({ id: `link:${++links.current}`, route });
    };
    void Linking.getInitialURL()
      .then(open)
      .catch(() => {});
    const subscription = Linking.addEventListener('url', (event) =>
      open(event.url),
    );
    return () => subscription.remove();
  }, []);
  useEffect(() => {
    if (uiVerify || !auth.localReady || auth.busy) return;
    void setPushUser(auth.account?.user.id ?? null).catch(() =>
      showToast(t('notifications.accountSyncFailed')),
    );
  }, [auth.localReady, auth.busy, auth.account?.user.id]);
  useEffect(() => {
    const userId = auth.account?.user.id;
    const pending: PushClick | null = link
      ? { ...link, userId: userId ?? '' }
      : click;
    if (!pending || handled.current === pending.id) return;
    const destination = resolveNotificationClick(pending, {
      ready: !!navigation?.key && auth.localReady && !auth.busy,
      userId,
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
    handled.current = pending.id;
    if (!link) void acknowledgePushClick(pending.id).catch(() => {});
    if (destination.kind === 'discard') showToast(destination.reason);
    else void requestOpenSession(destination.session);
    if (link) setLink(null);
    else setClick(null);
  }, [
    click,
    link,
    auth.localReady,
    auth.busy,
    auth.account,
    navigation?.key,
    catalog,
  ]);
  return null;
}
