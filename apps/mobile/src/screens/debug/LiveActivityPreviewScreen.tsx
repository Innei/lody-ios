import { useEffect, useMemo, useState } from 'react';
import { Text, View } from 'react-native';
import {
  debugLiveActivity,
  liveActivityStatus,
  type LiveActivityDebugAction,
  type LiveActivityStatus,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { Button } from '@/ui/Button';
import {
  NotificationSettingsContent,
  type NotificationService,
} from '@/screens/NotificationSettingsScreen';

function LiveActivityPreview() {
  const colors = usePalette();
  const [active, setActive] = useState(0);
  const service = useMemo<NotificationService>(() => {
    let enabled = true;
    return {
      status: async () => ({
        configured: true,
        registered: true,
        permission: 'authorized',
      }),
      request: async () => true,
      settings: async () => {},
      liveActivity: {
        status: async () => ({ enabled, supported: true, active: 0 }),
        setEnabled: async (next: boolean) => {
          enabled = next;
        },
      },
    };
  }, []);
  useEffect(() => {
    let alive = true;
    const refresh = () =>
      liveActivityStatus()
        .then((status: LiveActivityStatus) => {
          if (alive) setActive(status.active);
        })
        .catch(() => {});
    void refresh();
    const timer = setInterval(refresh, 1000);
    return () => {
      alive = false;
      clearInterval(timer);
    };
  }, []);
  const run = (action: LiveActivityDebugAction) => () => {
    void debugLiveActivity(action);
  };
  return (
    <View style={{ flex: 1 }}>
      <View style={{ paddingTop: 110, paddingHorizontal: 20, gap: 8 }}>
        <Text
          style={{ color: colors.label }}
          testID="live-activity-preview-ready"
        >
          Live Activity 演示
        </Text>
        <Text style={{ color: colors.label }} testID="live-activity-status">
          {`${active} 个活动`}
        </Text>
        <Button testID="live-activity-start" onPress={run('start-running')}>
          开始（运行中）
        </Button>
        <Button
          testID="live-activity-permission"
          onPress={run('update-permission')}
        >
          切换为需要授权
        </Button>
        <Button testID="live-activity-end" onPress={run('end')}>
          结束
        </Button>
        <Button
          testID="live-activity-complete-one"
          onPress={run('complete-one')}
        >
          完成一个任务
        </Button>
        <Button
          testID="live-activity-complete-all"
          onPress={run('complete-all')}
        >
          全部完成
        </Button>
      </View>
      <NotificationSettingsContent service={service} signedIn />
    </View>
  );
}

export const LiveActivityPreviewScreen = definePage<Record<string, never>>({
  id: 'live-activity-preview',
  title: 'Live Activity 演示',
  Component: LiveActivityPreview,
  parseRouteParams: () => ({}),
  presentation: { style: 'push' },
});
