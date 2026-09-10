import { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { router } from 'expo-router';
import { useAppNavigationState } from '@/lib/presentation/useAppNavigationState';
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
import { resolveNotificationClick } from './routing';
import {
  acknowledgeDeepLink,
  pendingDeepLink,
  subscribeDeepLinks,
} from './deepLinks';

export function PushCoordinator() {
  const auth = useAuth();
  const catalog = useCatalog();
  const navigation = useAppNavigationState();
  const [click, setClick] = useState<PushClick | null>(null);
  const link = useSyncExternalStore(subscribeDeepLinks, pendingDeepLink);
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
    if (destination.kind === 'wait' || !navigation) return;
    if (
      destination.kind !== 'discard' &&
      (navigation.routes.length !== 1 || navigation.routes[0]?.name !== 'index')
    ) {
      router.dismissTo('/');
      return;
    }
    if (destination.kind === 'workspace') {
      catalog.setWorkspaceId(destination.id);
      return;
    }
    handled.current = pending.id;
    if (!link) void acknowledgePushClick(pending.id).catch(() => {});
    if (destination.kind === 'discard') showToast(destination.reason);
    else void requestOpenSession(destination.session);
    if (link) acknowledgeDeepLink(pending.id);
    else setClick(null);
  }, [
    click,
    link,
    auth.localReady,
    auth.busy,
    auth.account,
    navigation,
    catalog,
  ]);
  return null;
}
