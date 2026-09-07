import { useEffect, useState } from 'react';
import { Text } from 'react-native';
import { useTheme } from 'expo-router';
import {
  dataRuntimeStatus,
  debugBackgroundDataRuntime,
  type DataRuntimeEvent,
} from '@lody-ios/kit';
import { definePage } from '@/presentation';
import { Screen } from '@/ui/Screen';
import { Button } from '@/ui/Button';

function BackgroundPreview() {
  const { colors } = useTheme();
  const [status, setStatus] = useState<DataRuntimeEvent>();
  const [error, setError] = useState('');
  useEffect(() => {
    let mounted = true;
    const timer = setInterval(() => {
      void dataRuntimeStatus()
        .then((value) => {
          if (mounted) setStatus(value);
        })
        .catch((error) => {
          if (mounted) setError(String(error));
        });
    }, 500);
    return () => {
      mounted = false;
      clearInterval(timer);
      void debugBackgroundDataRuntime('stop');
    };
  }, []);
  async function action(name: string) {
    try {
      await debugBackgroundDataRuntime(name);
      setStatus(await dataRuntimeStatus());
      setError('');
    } catch (error) {
      setError(String(error));
    }
  }
  return (
    <Screen>
      <Text style={{ color: colors.text }}>
        离线 WebView 与系统后台任务验收
      </Text>
      <Text testID="background-status" style={{ color: colors.text }}>
        {JSON.stringify({
          state: status?.state,
          generation: status?.generation,
          updates: status?.probeUpdates,
          backgroundUpdates: status?.probeBackgroundUpdates,
          task: status?.backgroundTaskState,
          tasks: status?.backgroundTaskCount,
        })}
      </Text>
      <Text testID="background-error" style={{ color: colors.text }}>
        {error}
      </Text>
      <Button testID="background-start" onPress={() => void action('start')}>
        重置离线连接
      </Button>
      <Button testID="background-send" onPress={() => void action('send')}>
        发送验收任务
      </Button>
      <Button
        testID="background-complete"
        onPress={() => void action('complete')}
      >
        完成回复
      </Button>
      <Button testID="background-expire" onPress={() => void action('expire')}>
        触发系统到期回调
      </Button>
      <Button testID="background-stop" onPress={() => void action('stop')}>
        停止连接
      </Button>
    </Screen>
  );
}

export const backgroundPreviewPage = definePage({
  id: 'background-preview',
  title: '后台连接',
  Component: BackgroundPreview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
