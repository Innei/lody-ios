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
      if (alive.current) showToast('暂时无法读取通知设置');
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
      showToast('暂时无法修改通知设置');
    } finally {
      pending.current = false;
      if (alive.current) setBusy(false);
    }
  }
  async function toggleLive(enabled: boolean) {
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
  let subtitle = '开启后接收会话完成和授权提醒';
  if (!signedIn) subtitle = '登录后可开启会话提醒';
  else if (!status) subtitle = '正在读取';
  else if (!status.configured) subtitle = '当前版本暂不支持通知';
  else if (status.permission === 'authorized') subtitle = '已允许通知';
  else if (status.permission === 'denied')
    subtitle = '通知已关闭，请在系统设置中开启';
  let title = status?.permission === 'notDetermined' ? '开启通知' : '通知设置';
  if (busy) title = '请稍候';
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
          header: '会话提醒',
          footer: '通知展示、声音和锁屏预览由系统设置管理。',
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
  title: '通知',
  Component: NotificationSettings,
  parseRouteParams: () => ({}),
  presentation: { style: 'push' },
});
