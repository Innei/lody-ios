import { useEffect, useRef, useState } from 'react';
import { Linking } from 'react-native';
import {
  addAppActiveListener,
  liveActivityStatus,
  NativeGroupedList,
  pushStatus,
  requestPushPermission,
  setLiveActivitiesEnabled,
  type LiveActivityStatus,
  type PushStatus,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { t } from '@/lib/i18n';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { showToast } from '@/ui/toast';

export type NotificationService = {
  status: () => Promise<PushStatus>;
  request: () => Promise<boolean>;
  settings: () => Promise<unknown>;
  liveActivity: {
    status: () => Promise<LiveActivityStatus>;
    setEnabled: (enabled: boolean) => Promise<void>;
  };
};
const service: NotificationService = {
  status: pushStatus,
  request: requestPushPermission,
  settings: Linking.openSettings,
  liveActivity: {
    status: liveActivityStatus,
    setEnabled: setLiveActivitiesEnabled,
  },
};

export function NotificationSettingsContent({
  service,
  signedIn,
}: {
  service: NotificationService;
  signedIn: boolean;
}) {
  const colors = usePalette();
  const [status, setStatus] = useState<PushStatus | null>(null);
  const [live, setLive] = useState<LiveActivityStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [liveBusy, setLiveBusy] = useState(false);
  const pending = useRef(false);
  const alive = useRef(true);
  async function refresh() {
    try {
      const [next, nextLive] = await Promise.all([
        service.status(),
        service.liveActivity.status(),
      ]);
      if (!alive.current) return;
      setStatus(next);
      setLive(nextLive);
    } catch {
      if (alive.current) showToast(t('notifications.readFailed'));
    }
  }
  useEffect(() => {
    alive.current = true;
    void refresh();
    const listener = addAppActiveListener(() => void refresh());
    return () => {
      alive.current = false;
      listener.remove();
    };
  }, [service]);
  async function press() {
    if (pending.current || !status?.configured || !signedIn) return;
    pending.current = true;
    setBusy(true);
    try {
      if (status.permission === 'notDetermined') await service.request();
      else await service.settings();
      await refresh();
    } catch {
      showToast(t('notifications.changeFailed'));
    } finally {
      pending.current = false;
      if (alive.current) setBusy(false);
    }
  }
  async function toggleLive(enabled: boolean) {
    setLive((current) => (current ? { ...current, enabled } : current));
    setLiveBusy(true);
    try {
      await service.liveActivity.setEnabled(enabled);
    } catch {
      showToast(t('settings.liveActivity.toggleFailed'));
    } finally {
      await refresh();
      if (alive.current) setLiveBusy(false);
    }
  }
  let subtitle = t('notifications.hint.default');
  if (!signedIn) subtitle = t('notifications.hint.signedOut');
  else if (!status) subtitle = t('notifications.hint.loading');
  else if (!status.configured) subtitle = t('notifications.hint.unsupported');
  else if (status.permission === 'authorized')
    subtitle = t('notifications.hint.authorized');
  else if (status.permission === 'denied')
    subtitle = t('notifications.hint.denied');
  let title =
    status?.permission === 'notDetermined'
      ? t('notifications.permission.turnOn')
      : t('notifications.permission.settings');
  if (busy) title = t('notifications.permission.busy');
  const liveSupported = !!live?.supported;
  let liveSubtitle = t('settings.liveActivity.hint');
  if (live && !liveSupported)
    liveSubtitle = t('settings.liveActivity.unsupported');
  return (
    <NativeGroupedList
      testID="notification-settings"
      style={{ flex: 1 }}
      accent={colors.accent}
      sections={[
        {
          id: 'notifications',
          header: t('notifications.section.header'),
          footer: t('notifications.section.footer'),
          rows: [
            {
              id: 'notification-permission',
              title,
              subtitle,
              image: 'bell',
              action: signedIn && !!status?.configured && !busy,
              disclosure: signedIn && !!status?.configured,
            },
            {
              id: 'live-activity',
              title: t('settings.liveActivity.title'),
              subtitle: liveSubtitle,
              image: 'clock',
              toggle: !!live?.enabled,
              action: signedIn && liveSupported && !liveBusy,
            },
          ],
        },
      ]}
      onRowPress={() => void press()}
      onRowToggle={(event) => void toggleLive(event.nativeEvent.value)}
    />
  );
}
function NotificationSettings() {
  const { account } = useAuth();
  return <NotificationSettingsContent service={service} signedIn={!!account} />;
}
export const NotificationSettingsScreen = definePage<Record<string, never>>({
  id: 'notification-settings',
  title: t('settings.notifications.title'),
  Component: NotificationSettings,
  parseRouteParams: () => ({}),
  presentation: { style: 'push' },
});
