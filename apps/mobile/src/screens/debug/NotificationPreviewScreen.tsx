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
  const service = useMemo<NotificationService>(() => {
    let permission: PushStatus['permission'] = 'notDetermined';
    return {
      status: async () => ({ configured: true, registered: true, permission }),
      request: async () => {
        permission = 'denied';
        return false;
      },
      settings: async () => {
        permission = 'authorized';
        setSettingsOpened(true);
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
        {settingsOpened && (
          <Text
            style={{ color: colors.label }}
            testID="notification-settings-opened"
          >
            已返回系统设置
          </Text>
        )}
        <Button
          testID="notification-reset"
          onPress={() => {
            setSettingsOpened(false);
            setRevision((n) => n + 1);
          }}
        >
          重置
        </Button>
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
  presentation: { style: 'push' },
});
