import { useEffect, useRef, useState } from 'react';
import { Linking } from 'react-native';
import {
  addAppActiveListener,
  NativeGroupedList,
  pushStatus,
  requestPushPermission,
  type PushStatus,
} from '@lody-ios/kit';
import { useAuth } from '@/cloud/auth/AuthProvider';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { showToast } from '@/ui/toast';

export type NotificationService = {
  status: () => Promise<PushStatus>;
  request: () => Promise<boolean>;
  settings: () => Promise<unknown>;
};
const service: NotificationService = {
  status: pushStatus,
  request: requestPushPermission,
  settings: Linking.openSettings,
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
  const [busy, setBusy] = useState(false);
  const pending = useRef(false);
  const alive = useRef(true);
  async function refresh() {
    try {
      const next = await service.status();
      if (alive.current) setStatus(next);
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
  let subtitle = '开启后接收会话完成和授权提醒';
  if (!signedIn) subtitle = '登录后可开启会话提醒';
  else if (!status) subtitle = '正在读取';
  else if (!status.configured) subtitle = '当前版本暂不支持通知';
  else if (status.permission === 'authorized') subtitle = '已允许通知';
  else if (status.permission === 'denied')
    subtitle = '通知已关闭，请在系统设置中开启';
  let title = status?.permission === 'notDetermined' ? '开启通知' : '通知设置';
  if (busy) title = '请稍候';
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
          ],
        },
      ]}
      onRowPress={() => void press()}
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
