import { usePalette } from '@/lib/theme/palette';
import { useMemo, useState } from 'react';
import { Text, View } from 'react-native';
import { type PushStatus } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { Button } from '@/ui/Button';
import {
  NotificationSettingsContent,
  type NotificationService,
} from '@/screens/NotificationSettingsScreen';

function NotificationPreview() {
  const colors = usePalette();
  const [revision, setRevision] = useState(0);
  const [settingsOpened, setSettingsOpened] = useState(false);
  const [liveWrites, setLiveWrites] = useState(0);
  const service = useMemo<NotificationService>(() => {
    let permission: PushStatus['permission'] = 'notDetermined';
    let enabled = false;
    let requests = 0;
    let settingsAttempts = 0;
    return {
      status: async () => ({ configured: true, registered: true, permission }),
      request: async () => {
        if (++requests === 1) throw new Error('offline_notification_fixture');
        permission = 'denied';
        return false;
      },
      settings: async () => {
        if (permission === 'denied' && ++settingsAttempts === 1)
          throw new Error('offline_notification_fixture');
        permission = 'authorized';
        setSettingsOpened(true);
      },
      liveActivity: {
        status: async () => ({
          enabled,
          supported: permission === 'authorized',
          active: 0,
        }),
        setEnabled: async (next: boolean) => {
          setLiveWrites((count) => count + 1);
          if (!next) throw new Error('offline_notification_fixture');
          enabled = next;
        },
      },
    };
  }, [revision]);
  return (
    <View style={{ flex: 1 }}>
      <View style={{ paddingTop: 110, paddingHorizontal: 20 }}>
        <Text
          style={{ color: colors.label }}
          testID="notification-preview-ready"
        >
          通知权限验收
        </Text>
        <Text
          style={{ color: colors.label }}
          testID={settingsOpened ? 'notification-settings-opened' : undefined}
        >
          {settingsOpened ? '已返回系统设置' : '尚未打开系统设置'}
        </Text>
        <Button
          testID="notification-reset"
          onPress={() => {
            setLiveWrites(0);
            setSettingsOpened(false);
            setRevision((n) => n + 1);
          }}
        >
          重置
        </Button>
        <Text style={{ color: colors.label }} testID="notification-live-writes">
          Live changes: {liveWrites}
        </Text>
      </View>
      <NotificationSettingsContent key={revision} service={service} signedIn />
    </View>
  );
}
export const NotificationPreviewScreen = definePage<Record<string, never>>({
  id: 'notification-preview',
  title: '通知验收',
  Component: NotificationPreview,
  parseRouteParams: () => ({}),
  presentation: { style: 'push', headerVariant: 'transparent' },
});
