import { FilePreviewScreen } from './FilePreviewScreen';
import { CreateSessionScreen } from '../CreateSessionScreen';
import { writeLocal } from '@/cloud/kv';
import { createPrefsKey } from '@/features/sessions/createPrefs';
import { openSendPreview } from './SendPreviewScreen';
import { BackgroundPreviewScreen } from './BackgroundPreviewScreen';
import { pushStatus, verifyPushSubscription } from '@lody-ios/kit';
import { NotificationPreviewScreen } from './NotificationPreviewScreen';
import { uiVerify } from './uiVerify';
import { ComposerPreviewScreen } from './ComposerPreviewScreen';
import { ChatPreviewScreen } from './ChatPreviewScreen';
import { ChatPerformanceScreen } from './ChatPerformanceScreen';
import { ChatStreamPerformanceScreen } from './ChatStreamPerformanceScreen';
import { BannerPreviewScreen } from './BannerPreviewScreen';
import { ScrollPreviewScreen } from './ScrollPreviewScreen';
import { ShinePreviewScreen } from './ShinePreviewScreen';
import { InboxPreviewScreen } from './InboxPreviewScreen';
import { SettingsPreviewScreen } from './SettingsPreviewScreen';
import { OnboardingPreviewScreen } from './OnboardingPreviewScreen';
import { useRouter, useTheme } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View as RNView } from 'react-native';
import {
  NativeCloseButton,
  NativeGroupedList,
  dataRuntimeStatus,
  addDataRuntimeListener,
  debugHangDataRuntime,
  debugProbeSchema,
  debugRestartDataRuntime,
  type NativeListRow,
  type NativeListSection,
} from '@lody-ios/kit';
import { EnvironmentScreen } from '@/screens/EnvironmentScreen';
import {
  definePage,
  present,
  type PagePresentationOptions,
} from '@/lib/presentation';
import { Button } from '@/ui/Button';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';

function openRow(id: string, title: string, image: string): NativeListRow {
  return { id, title, image, action: true, disclosure: true, navigates: true };
}

function View() {
  const router = useRouter();
  const colors = usePalette();
  const [runtime, setRuntime] = useState<{
    title: string;
    subtitle?: string;
  }>({ title: '正在读取' });
  useEffect(() => {
    if (uiVerify) return;
    const update = (event: Awaited<ReturnType<typeof dataRuntimeStatus>>) =>
      setRuntime({
        title: event.state,
        subtitle: [
          event.generation != null ? `#${event.generation}` : '',
          event.reason,
          event.lastStartReason,
        ]
          .filter(Boolean)
          .join(' · '),
      });
    const subscription = addDataRuntimeListener(update);
    void dataRuntimeStatus()
      .then(update)
      .catch(() => setRuntime({ title: '无法读取运行时状态' }));
    return () => subscription.remove();
  }, []);
  const [result, setResult] = useState('等待打开页面');
  async function open(style: PagePresentationOptions['style']) {
    try {
      const result = await present(
        EnvironmentScreen,
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
  const sections: NativeListSection[] = [];
  if (uiVerify)
    sections.push({
      id: 'verify',
      rows: [{ id: 'ui-verify-ready', title: 'Offline UI verification' }],
    });
  sections.push(
    {
      id: 'ui',
      header: '界面验收',
      rows: [
        openRow('notification-preview', '通知权限验收', 'bell'),
        {
          id: 'push-subscription-verify',
          title: '验证 OneSignal 订阅',
          image: 'bell.badge',
          action: true,
        },
        openRow('permission-preview', '权限验收', 'hand.raised'),
        openRow('file-preview', '文件预览验收', 'doc'),
        openRow('onboarding-preview', '登录引导验收', 'hand.wave'),
        openRow('settings-preview', '远程设置验收', 'gear'),
        openRow('inbox-preview', '动态分组验收', 'tray'),
        ...(uiVerify
          ? [openRow('background-preview', '后台连接验收', 'moon.zzz')]
          : []),
        openRow('scroll-preview', '滚动连续性验收', 'arrow.up.and.down'),
        openRow('chat-performance', '10,000 条消息性能测试', 'gauge.medium'),
        openRow(
          'chat-stream-performance',
          '300 TPS 流式性能测试',
          'waveform.path',
        ),
        ...(uiVerify
          ? [openRow('model-memory', 'Model memory verification', 'brain')]
          : []),
      ],
    },
    {
      id: 'chat',
      header: '聊天与输入',
      rows: [
        openRow('composer-preview', '输入框验收', 'square.and.pencil'),
        openRow('composer-success', '聊天输入成功', 'checkmark.circle'),
        openRow('composer-failure', '聊天输入恢复', 'arrow.uturn.backward'),
        openRow('chat-preview', '原生聊天预览', 'bubble.left.and.bubble.right'),
        openRow('chat-shine-preview', '过程高光', 'sparkle'),
        openRow('banner-preview', '会话横幅', 'bell.badge'),
      ],
    },
    {
      id: 'send',
      header: '发送',
      rows: [
        openRow('send-preview', '离线发送验收', 'paperplane'),
        openRow('send-queue', 'Queue 验收', 'list.bullet'),
        openRow('send-interrupt', 'Queue 中断验收', 'stop.circle'),
        openRow('send-handoff', '新建发送交接', 'arrow.triangle.swap'),
      ],
    },
    {
      id: 'runtime',
      header: '数据运行时',
      footer:
        '故障注入会暂时中断同步。看门狗应自动重建；连续故障达到上限后，请返回项目页下拉重新同步。',
      rows: [
        {
          id: 'runtime-state',
          title: runtime.title,
          subtitle: runtime.subtitle,
          subtitleMono: true,
          image: 'cpu',
        },
        {
          id: 'runtime-probe',
          title: '探测机器数据结构（只报字段名）',
          image: 'antenna.radiowaves.left.and.right',
          action: true,
        },
        {
          id: 'runtime-hang',
          title: '卡死 WebView JS',
          image: 'exclamationmark.triangle',
          action: true,
          destructive: true,
        },
        {
          id: 'runtime-restart',
          title: '模拟 WebContent 进程丢失',
          image: 'arrow.clockwise',
          action: true,
        },
      ],
    },
    {
      id: 'router',
      header: 'Router 与原生模块',
      footer: result,
      rows: [
        openRow('router-environment', '通过 Router 打开', 'link'),
        openRow('present-pageSheet', '打开 Page Sheet', 'rectangle.portrait'),
        openRow(
          'present-formSheet',
          '打开 Form Sheet',
          'rectangle.bottomhalf.inset.filled',
        ),
        openRow('present-fullScreen', '打开 Full Screen', 'rectangle'),
        openRow('present-overFullScreen', '打开透明覆盖层', 'square.on.square'),
      ],
    },
  );

  const actions: Record<string, () => void> = {
    'notification-preview': () => {
      void present(NotificationPreviewScreen, {});
    },
    'push-subscription-verify': () => {
      void pushStatus().then(async (status) => {
        await verifyPushSubscription();
        if (!status.registered)
          setResult(
            status.configured
              ? 'OneSignal 尚未完成服务端订阅注册'
              : '当前构建未初始化 OneSignal',
          );
      });
    },
    'permission-preview': () => void present(ChatPreviewScreen, {}),
    'file-preview': () => void present(FilePreviewScreen, {}),
    'onboarding-preview': () => void present(OnboardingPreviewScreen, {}),
    'settings-preview': () => void present(SettingsPreviewScreen, {}),
    'inbox-preview': () => void present(InboxPreviewScreen, {}),
    'background-preview': () => void present(BackgroundPreviewScreen, {}),
    'scroll-preview': () => void present(ScrollPreviewScreen, {}),
    'chat-performance': () => void present(ChatPerformanceScreen, {}),
    'chat-stream-performance': () =>
      void present(ChatStreamPerformanceScreen, {}),
    'model-memory': () => void openModelMemory(),
    'composer-preview': () =>
      void present(ComposerPreviewScreen, {
        host: 'sheet',
        outcome: 'failure',
      }),
    'composer-success': () =>
      void present(
        ComposerPreviewScreen,
        { host: 'chat', outcome: 'success' },
        { style: 'push' },
      ),
    'composer-failure': () =>
      void present(
        ComposerPreviewScreen,
        { host: 'chat', outcome: 'failure' },
        { style: 'push' },
      ),
    'chat-preview': () => void present(ChatPreviewScreen, {}),
    'chat-shine-preview': () => void present(ShinePreviewScreen, {}),
    'banner-preview': () => void present(BannerPreviewScreen, {}),
    'send-preview': () => void openSendPreview(false),
    'send-queue': () => void openSendPreview(false, true),
    'send-interrupt': () => void openSendPreview(false, true, false),
    'send-handoff': () => void openSendPreview(true),
    'runtime-probe': () =>
      void debugProbeSchema()
        .then((report) => {
          console.log('PROBE_BEGIN', report, 'PROBE_END');
          setRuntime({
            title: '探测结果',
            subtitle: report.slice(0, 120),
          });
        })
        .catch((error) => setRuntime({ title: String(error) })),
    'runtime-hang': () => void debugHangDataRuntime(),
    'runtime-restart': () => void debugRestartDataRuntime(),
    'router-environment': () => router.push('/environment'),
    'present-pageSheet': () => void open('pageSheet'),
    'present-formSheet': () => void open('formSheet'),
    'present-fullScreen': () => void open('fullScreen'),
    'present-overFullScreen': () => {
      void present(overlayPage)
        .then((result) =>
          setResult(
            result.status === 'completed' ? '覆盖层已完成' : '覆盖层已取消',
          ),
        )
        .catch((error) => setResult(String(error)));
    },
  };

  return (
    <NativeGroupedList
      style={{ flex: 1 }}
      accent={colors.accent}
      placeholder=""
      sections={sections}
      onRowPress={({ nativeEvent }) => actions[nativeEvent.id]?.()}
    />
  );
}

function OverlayScreen() {
  const { colors } = useTheme();
  const { cancel, finish } = usePageRuntime();
  return (
    <RNView
      style={{
        flex: 1,
        justifyContent: 'center',
        padding: 24,
        backgroundColor: 'rgba(0,0,0,0.35)',
      }}
    >
      <RNView
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
      </RNView>
    </RNView>
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

export const DebugScreen = definePage({
  id: 'debug',
  title: 'Debug',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

async function openModelMemory() {
  const workspaceId = 'ui-model-memory';
  await writeLocal(createPrefsKey('', workspaceId), null);
  const project = {
    id: 'ui:local:models',
    name: 'Model Memory',
    machineId: 'ui',
    rootPath: '/fixture',
  };
  await present(CreateSessionScreen, {
    workspaceId,
    projects: [project],
    projectId: project.id,
    loadOptions: async () => ({
      sessionId: 'ui-model-memory',
      project,
      agents: [
        {
          id: 'agent',
          name: 'Fixture Agent',
          machineId: 'ui',
          machineName: 'Fixture Mac',
          cliType: 'builtin',
          agentType: 'codex',
        },
      ],
      capabilities: [
        {
          machineId: 'ui',
          cliType: 'builtin',
          agentType: 'codex',
          models: [
            { id: 'a', name: 'Model A' },
            { id: 'b', name: 'Model B' },
          ],
          modes: [
            { id: 'read-only', name: 'Read Only' },
            { id: 'agent-full-access', name: 'Full Access' },
          ],
          reasoningEfforts: { a: ['low', 'high'], b: ['low', 'high'] },
          steer: true,
        },
      ],
    }),
  });
}
