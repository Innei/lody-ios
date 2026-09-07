import { openSendPreview } from './SendPreview';
import { backgroundPreviewPage } from './BackgroundPreview';
import { uiVerify } from './uiVerify';
import { composerPreviewPage } from './ComposerPreview';
import { chatPreviewPage } from './ChatPreview';
import { shinePreviewPage } from './ShinePreview';
import { inboxPreviewPage } from './InboxPreview';
import { Link, useTheme } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View } from 'react-native';
import {
  NativeCloseButton,
  dataRuntimeStatus,
  addDataRuntimeListener,
  debugHangDataRuntime,
  debugProbeSchema,
  debugRestartDataRuntime,
} from '@lody-ios/kit';
import { environmentPage } from '@/features/environment/EnvironmentScreen';
import {
  definePage,
  usePageRuntime,
  present,
  type PagePresentationOptions,
} from '@/presentation';
import { Screen } from '@/ui/Screen';
import { Button } from '@/ui/Button';

export default function DebugScreen() {
  const [runtime, setRuntime] = useState('正在读取');
  useEffect(() => {
    if (uiVerify) return;
    const update = (event: Awaited<ReturnType<typeof dataRuntimeStatus>>) =>
      setRuntime(
        JSON.stringify(
          {
            state: event.state,
            generation: event.generation,
            reason: event.reason,
            lastStartReason: event.lastStartReason,
            acknowledgements: event.acknowledgements,
          },
          null,
          2,
        ),
      );
    const subscription = addDataRuntimeListener(update);
    void dataRuntimeStatus()
      .then(update)
      .catch(() => setRuntime('无法读取运行时状态'));
    return () => subscription.remove();
  }, []);
  const { colors } = useTheme();
  const [result, setResult] = useState('等待打开页面');
  async function open(style: PagePresentationOptions['style']) {
    try {
      const result = await present(
        environmentPage,
        { message: '从 Debug 传入的参数' },
        { style },
      );
      setResult(
        result.status === 'completed'
          ? `已完成：${result.value.moduleName} / iOS ${result.value.systemVersion}`
          : '已取消',
      );
    } catch (error) {
      setResult(String(error));
    }
  }
  if (!__DEV__)
    return (
      <Screen>
        <Text>仅开发构建可用</Text>
      </Screen>
    );
  return (
    <Screen>
      {uiVerify && (
        <Text testID="ui-verify-ready">Offline UI verification</Text>
      )}
      <Button testID="send-preview" onPress={() => void openSendPreview(false)}>
        离线发送验收
      </Button>
      <Button testID="send-handoff" onPress={() => void openSendPreview(true)}>
        新建发送交接
      </Button>
      <Button
        testID="inbox-preview"
        onPress={() => void present(inboxPreviewPage, {})}
      >
        动态分组验收
      </Button>
      {uiVerify && (
        <Button
          testID="background-preview"
          onPress={() => void present(backgroundPreviewPage, {})}
        >
          后台连接验收
        </Button>
      )}
      <Button
        testID="composer-preview"
        onPress={() =>
          void present(composerPreviewPage, {
            host: 'sheet',
            outcome: 'failure',
          })
        }
      >
        输入框验收
      </Button>
      <Button
        testID="composer-success"
        onPress={() =>
          void present(
            composerPreviewPage,
            { host: 'chat', outcome: 'success' },
            { style: 'push' },
          )
        }
      >
        聊天输入成功
      </Button>
      <Button
        testID="composer-failure"
        onPress={() =>
          void present(
            composerPreviewPage,
            { host: 'chat', outcome: 'failure' },
            { style: 'push' },
          )
        }
      >
        聊天输入恢复
      </Button>
      <Button
        testID="chat-preview"
        onPress={() => void present(chatPreviewPage, {})}
      >
        原生聊天预览
      </Button>
      <Button
        testID="chat-shine-preview"
        onPress={() => void present(shinePreviewPage, {})}
      >
        过程高光
      </Button>
      <Text style={{ color: colors.text, fontSize: 22, fontWeight: '600' }}>
        数据运行时
      </Text>
      <Text
        testID="runtime-state"
        selectable
        style={{ color: colors.text, fontFamily: 'Menlo', lineHeight: 22 }}
      >
        {runtime}
      </Text>
      <Button
        testID="runtime-probe"
        onPress={() =>
          void debugProbeSchema()
            .then((report) => {
              console.log('PROBE_BEGIN', report, 'PROBE_END');
              setRuntime(report.slice(0, 400));
            })
            .catch((error) => setRuntime(String(error)))
        }
      >
        探测机器数据结构（只报字段名）
      </Button>
      <Button testID="runtime-hang" onPress={() => void debugHangDataRuntime()}>
        卡死 WebView JS
      </Button>
      <Button
        testID="runtime-restart"
        onPress={() => void debugRestartDataRuntime()}
      >
        模拟 WebContent 进程丢失
      </Button>
      <Text style={{ color: colors.text, opacity: 0.6 }}>
        故障注入会暂时中断同步。看门狗应自动重建；连续故障达到上限后，请返回项目页下拉重新同步。
      </Text>
      <Text style={{ color: colors.text, fontSize: 22, fontWeight: '600' }}>
        Router 与原生模块
      </Text>
      <Link
        href="/environment"
        style={{ color: colors.primary, fontSize: 17, paddingVertical: 14 }}
      >
        通过 Router 打开
      </Link>
      <Button testID="present-pageSheet" onPress={() => void open('pageSheet')}>
        打开 Page Sheet
      </Button>
      <Button testID="present-formSheet" onPress={() => void open('formSheet')}>
        打开 Form Sheet
      </Button>
      <Button
        testID="present-fullScreen"
        onPress={() => void open('fullScreen')}
      >
        打开 Full Screen
      </Button>
      <Button
        testID="present-overFullScreen"
        onPress={() => {
          void present(overlayPage)
            .then((result) =>
              setResult(
                result.status === 'completed' ? '覆盖层已完成' : '覆盖层已取消',
              ),
            )
            .catch((error) => setResult(String(error)));
        }}
      >
        打开透明覆盖层
      </Button>
      <Text accessibilityLiveRegion="polite" style={{ color: colors.text }}>
        {result}
      </Text>
    </Screen>
  );
}

function OverlayScreen() {
  const { colors } = useTheme();
  const { cancel, finish } = usePageRuntime();
  return (
    <View
      style={{
        flex: 1,
        justifyContent: 'center',
        padding: 24,
        backgroundColor: 'rgba(0,0,0,0.35)',
      }}
    >
      <View
        style={{
          backgroundColor: colors.card,
          padding: 24,
          borderRadius: 24,
          borderCurve: 'continuous',
          gap: 16,
        }}
      >
        <NativeCloseButton
          label="关闭覆盖层"
          onPress={cancel}
          style={{ width: 44, height: 44, alignSelf: 'flex-end' }}
        />
        <Text style={{ color: colors.text, fontSize: 20 }}>原生透明覆盖层</Text>
        <Button testID="overlay-finish" onPress={() => finish()}>
          完成并返回
        </Button>
      </View>
    </View>
  );
}
const overlayPage = definePage({
  id: 'overlay',
  title: '透明覆盖层',
  Component: OverlayScreen,
  presentation: {
    style: 'overFullScreen',
    headerShown: false,
    animationType: 'fade',
  },
});
