import { StreamsClient } from '@loro-dev/streams-client';
import {
  addAppActiveListener,
  runtimeInfo,
  selectionFeedback,
  type RuntimeInfo,
} from '@lody-ios/kit';
import { useTheme } from 'expo-router';
import { useEffect, useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { definePage } from '@/lib/presentation';
import { Button } from '@/ui/Button';
import { Screen } from '@/ui/Screen';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

type EnvironmentParams = { message: string };

function View() {
  const { colors } = useTheme();
  const { params, source, finish, cancel, present } = usePageRuntime<
    EnvironmentParams,
    RuntimeInfo
  >();
  const [status, setStatus] = useState('等待原生调用');
  useEffect(() => {
    const subscription = addAppActiveListener(() =>
      setStatus('已收到 Swift 前台事件'),
    );
    return () => subscription.remove();
  }, []);
  async function feedback() {
    try {
      await selectionFeedback();
      setStatus('Swift 异步调用完成');
    } catch (error) {
      setStatus(String(error));
    }
  }
  async function nested() {
    try {
      const result = await present(
        EnvironmentScreen,
        { message: '来自上一层 Sheet' },
        { style: 'formSheet' },
      );
      setStatus(
        result.status === 'completed' ? '嵌套页面已完成' : '嵌套页面已取消',
      );
    } catch (error) {
      setStatus(String(error));
    }
  }
  return (
    <Screen>
      <Text style={[styles.heading, { color: colors.text }]}>
        LodyKit 已连接
      </Text>
      <Text style={[styles.detail, { color: colors.text }]}>
        入口：{source}
        {'\n'}参数：{params.message}
      </Text>
      <Text selectable style={[styles.detail, { color: colors.text }]}>
        iOS {runtimeInfo.systemVersion}
        {'\n'}原生模块：{runtimeInfo.moduleName}
        {'\n'}Streams 客户端：{StreamsClient.name}
      </Text>
      <Button testID="native-feedback" onPress={() => void feedback()}>
        调用 Swift 触感反馈
      </Button>
      <Button testID="present-nested" onPress={() => void nested()}>
        打开下一层 Sheet
      </Button>
      <Button testID="present-finish" onPress={() => finish(runtimeInfo)}>
        完成并返回
      </Button>
      <Button testID="present-cancel" onPress={cancel}>
        取消
      </Button>
      <Text
        accessibilityLiveRegion="polite"
        style={[styles.detail, { color: colors.text }]}
      >
        {status}
      </Text>
    </Screen>
  );
}

export const EnvironmentScreen = definePage<EnvironmentParams, RuntimeInfo>({
  id: 'environment',
  title: '运行环境',
  Component: View,
  parseRouteParams: ({ message }) => ({
    message: (Array.isArray(message) ? message[0] : message) ?? '直接路由入口',
  }),
  presentation: { style: 'pageSheet', headerVariant: 'transparent' },
});
const styles = StyleSheet.create({
  heading: { fontSize: 24, fontWeight: '600', paddingTop: 20 },
  detail: { fontSize: 16, lineHeight: 26 },
});
