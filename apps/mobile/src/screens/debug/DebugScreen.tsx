import { AppIconFailurePreviewScreen } from './AppIconFailurePreviewScreen';
import { MessageSharePreviewScreen } from './MessageSharePreviewScreen';
import { SessionSharePreviewScreen } from './SessionSharePreviewScreen';
import { DiffScrollEdgePreviewScreen } from './DiffScrollEdgePreviewScreen';
import { SteerPreviewScreen } from './SteerPreviewScreen';
import { AgentErrorPreviewScreen } from './AgentErrorPreviewScreen';
import { ProjectHistoryPreviewScreen } from './ProjectHistoryPreviewScreen';
import { PullRequestPreviewScreen } from './PullRequestPreviewScreen';
import { FilePreviewScreen } from './FilePreviewScreen';
import { CreateSessionScreen } from '../CreateSessionScreen';
import { ProjectPickerScreen } from '../ProjectPickerScreen';
import type { CreationOptions } from '@/models/send';
import { writeLocal } from '@/cloud/kv';
import { showCommunityNotice } from '@/features/community/notice';
import { createPrefsKey } from '@/features/sessions/createPrefs';
import { openSendPreview } from './SendPreviewScreen';
import { openOutboxPreview } from './OutboxPreviewScreen';
import { BackgroundPreviewScreen } from './BackgroundPreviewScreen';
import { pushStatus, verifyPushSubscription } from '@lody-ios/kit';
import { NotificationPreviewScreen } from './NotificationPreviewScreen';
import { LiveActivityPreviewScreen } from './LiveActivityPreviewScreen';
import { ReplyHapticsPreviewScreen } from './ReplyHapticsPreviewScreen';
import { uiVerify } from './uiVerify';
import { ComposerPreviewScreen } from './ComposerPreviewScreen';
import { ComposerHandoffPreviewScreen } from './ComposerHandoffPreviewScreen';
import { ChatPreviewScreen } from './ChatPreviewScreen';
import { ChatPerformanceScreen } from './ChatPerformanceScreen';
import { ChatStreamPerformanceScreen } from './ChatStreamPerformanceScreen';
import { BannerPreviewScreen } from './BannerPreviewScreen';
import { ScrollPreviewScreen } from './ScrollPreviewScreen';
import {
  NativeCollectionPreviewScreen,
  NativeShellPreviewScreen,
} from './NativeShellPreviewScreen';
import { ShinePreviewScreen } from './ShinePreviewScreen';
import { SessionTreePreviewScreen } from './SessionTreePreviewScreen';
import { InboxPreviewScreen } from './InboxPreviewScreen';
import { SettingsPreviewScreen } from './SettingsPreviewScreen';
import { SettingsScreen } from '../SettingsScreen';
import { QuickRepliesPreviewScreen } from './QuickRepliesPreviewScreen';
import { OnboardingPreviewScreen } from './OnboardingPreviewScreen';
import { useNavigation, useRouter, useTheme } from 'expo-router';
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
import { EnvironmentScreen } from '@/screens/debug/EnvironmentScreen';
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
  const navigation = useNavigation();
  useEffect(() => {
    if (!uiVerify) return;
    globalThis.__lodyUiVerifyReset = () =>
      navigation.reset({
        index: 0,
        routes: [{ name: 'debug' as never, key: `verify-${Date.now()}` }],
      });
    return () => {
      delete globalThis.__lodyUiVerifyReset;
    };
  }, [navigation]);
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
        openRow('reply-haptics-preview', '回复触感试验', 'waveform'),
        openRow(
          'pull-request-preview',
          'GitHub PR / CI 预览',
          'arrow.triangle.pull',
        ),
        openRow('project-picker-preview', '选择项目验收', 'folder'),
        openRow('notification-preview', '通知权限验收', 'bell'),
        openRow('live-activity-preview', 'Live Activity 演示', 'sparkles'),
        {
          id: 'push-subscription-verify',
          title: '验证 OneSignal 订阅',
          image: 'bell.badge',
          action: true,
        },
        openRow('permission-preview', '权限验收', 'hand.raised'),
        openRow('file-preview', '文件预览验收', 'doc'),
        openRow('onboarding-preview', '登录引导验收', 'hand.wave'),
        {
          id: 'community-notice',
          title: '社区声明验收',
          image: 'star',
          action: true,
        },
        openRow(
          'project-history-preview',
          '项目会话同步验收',
          'arrow.triangle.2.circlepath',
        ),
        openRow('settings-preview', '远程设置验收', 'gear'),
        openRow('app-icon-failure-preview', 'Icon failure', 'app.dashed'),
        openRow('appearance-preview', '外观验收', 'circle.lefthalf.filled'),
        openRow(
          'queued-message-behavior-preview',
          '排队消息行为验收',
          'arrow.uturn.forward',
        ),
        openRow('session-tree-preview', 'Session tree', 'list.bullet.indent'),
        openRow('inbox-preview', '动态分组验收', 'tray'),
        openRow('background-preview', '后台连接验收', 'moon.zzz'),
        openRow('native-shell-poc', 'Native Shell POC', 'sidebar.left'),
        openRow(
          'native-collection-poc',
          'Native Collection POC',
          'list.bullet',
        ),
        openRow('scroll-preview', '滚动连续性验收', 'arrow.up.and.down'),
        openRow('chat-performance', '10,000 条消息性能测试', 'gauge.medium'),
        openRow(
          'chat-stream-performance',
          '300 TPS 流式性能测试',
          'waveform.path',
        ),
        openRow('model-memory', 'Model memory verification', 'brain'),
      ],
    },
    {
      id: 'chat',
      header: '聊天与输入',
      rows: [
        openRow('mention-chat', '@ 引用交互 · 聊天', 'at'),
        openRow('mention-sheet', '@ 引用交互 · 新会话', 'at'),
        openRow('composer-preview', '输入框验收', 'square.and.pencil'),
        openRow('scroll-edge-pages', '分页表单滚动边缘', 'rectangle.split.2x1'),
        openRow('scroll-edge-diff', 'Diff 滚动边缘', 'doc.text'),
        openRow('composer-success', '聊天输入成功', 'checkmark.circle'),
        openRow('composer-failure', '聊天输入恢复', 'arrow.uturn.backward'),
        openRow(
          'agent-error-preview',
          'Agent 错误预览',
          'exclamationmark.circle',
        ),
        openRow('chat-preview', '原生聊天预览', 'bubble.left.and.bubble.right'),
        openRow('chat-shine-preview', '过程高光', 'sparkle'),
        openRow('banner-preview', '会话横幅', 'bell.badge'),
      ],
    },
    {
      id: 'send',
      header: '发送',
      rows: [
        openRow('quick-replies-preview', 'Quick Replies', 'text.bubble'),
        openRow('send-preview', '离线发送验收', 'paperplane'),
        openRow('send-queue', 'Queue 验收', 'list.bullet'),
        openRow('message-share-preview', 'Message sharing', 'photo'),
        openRow('session-share-preview', 'Conversation sharing', 'link'),
        openRow('steer-preview', '连续引导验收', 'arrow.triangle.branch'),
        openRow('send-guide', '引导发送验收', 'arrow.uturn.forward'),
        openRow('outbox-preview', '后台发件箱验收', 'tray.and.arrow.up'),
        openRow('send-interrupt', 'Queue 中断验收', 'stop.circle'),
        openRow('send-handoff', '新建发送交接', 'arrow.triangle.swap'),
        openRow('composer-relay', 'Composer 接力 POC', 'rectangle.2.swap'),
        openRow('send-handoff-delayed', '新建发送交接 · 慢速页面', 'clock'),
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
    'reply-haptics-preview': () => void present(ReplyHapticsPreviewScreen, {}),
    'notification-preview': () => {
      void present(NotificationPreviewScreen, {});
    },
    'live-activity-preview': () => void present(LiveActivityPreviewScreen, {}),
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
    'community-notice': () => showCommunityNotice(),
    'project-history-preview': () =>
      void present(ProjectHistoryPreviewScreen, {}),
    'pull-request-preview': () => void present(PullRequestPreviewScreen, {}),
    'project-picker-preview': () => void openProjectPicker(),
    'settings-preview': () => void present(SettingsPreviewScreen, {}),
    'app-icon-failure-preview': () =>
      void present(AppIconFailurePreviewScreen, {}),
    'appearance-preview': () => void present(SettingsScreen, {}),
    'queued-message-behavior-preview': () => void present(SettingsScreen, {}),
    'quick-replies-preview': () => void present(QuickRepliesPreviewScreen),
    'session-tree-preview': () => void present(SessionTreePreviewScreen),
    'inbox-preview': () => void present(InboxPreviewScreen, {}),
    'background-preview': () => void present(BackgroundPreviewScreen, {}),
    'native-shell-poc': () => void present(NativeShellPreviewScreen, {}),
    'native-collection-poc': () =>
      void present(NativeCollectionPreviewScreen, {}),
    'scroll-preview': () => void present(ScrollPreviewScreen, {}),
    'chat-performance': () => void present(ChatPerformanceScreen, {}),
    'chat-stream-performance': () =>
      void present(ChatStreamPerformanceScreen, {}),
    'model-memory': () => void openModelMemory(),
    'mention-chat': () =>
      void present(
        ComposerPreviewScreen,
        { host: 'chat', outcome: 'failure', mentions: true },
        { style: 'push' },
      ),
    'mention-sheet': () =>
      void present(ComposerPreviewScreen, {
        host: 'sheet',
        outcome: 'failure',
        mentions: true,
      }),
    'composer-preview': () =>
      void present(ComposerPreviewScreen, {
        host: 'sheet',
        outcome: 'failure',
      }),
    'scroll-edge-pages': () =>
      void present(ComposerPreviewScreen, {
        host: 'sheet',
        outcome: 'failure',
        paged: true,
      }),
    'scroll-edge-diff': () =>
      void present(DiffScrollEdgePreviewScreen, {}, { style: 'push' }),
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
    'agent-error-preview': () => void present(AgentErrorPreviewScreen, {}),
    'chat-preview': () => void present(ChatPreviewScreen, {}),
    'chat-shine-preview': () => void present(ShinePreviewScreen, {}),
    'banner-preview': () => void present(BannerPreviewScreen, {}),
    'send-preview': () => void openSendPreview(false),
    'send-queue': () => void openSendPreview(false, true),
    'message-share-preview': () => void present(MessageSharePreviewScreen, {}),
    'session-share-preview': () => void present(SessionSharePreviewScreen),
    'steer-preview': () => void present(SteerPreviewScreen, {}),
    'send-guide': () => void openSendPreview(false, true, true, 'guide'),
    'outbox-preview': () => void openOutboxPreview(),
    'send-interrupt': () => void openSendPreview(false, true, false),
    'send-handoff': () => void openSendPreview(true),
    'composer-relay': () => void present(ComposerHandoffPreviewScreen, {}),
    'send-handoff-delayed': () => void openSendPreview('delayed'),
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

function openProjectPicker() {
  const projects = [
    {
      id: 'ui:local:alpha',
      name: 'Alpha',
      machineId: 'ui',
      rootPath: '/tmp/alpha',
    },
    {
      id: 'ui:local:beta',
      name: 'Beta',
      machineId: 'ui',
      rootPath: '/tmp/beta',
    },
  ];
  void present(
    ProjectPickerScreen,
    {
      workspaceId: 'ui-project-picker',
      projects,
      selectedId: 'ui:local:alpha',
    },
    { style: 'pageSheet', headerVariant: 'transparent' },
  );
}

async function openModelMemory() {
  const select = (
    id: string,
    name: string,
    values: string[],
    category = id,
  ) => ({
    id,
    name,
    category,
    type: 'select' as const,
    currentValue: values[0],
    options: values.map((id) => ({ id, name: id })),
  });
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
    loadOptions: async (): Promise<CreationOptions> => ({
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
        ...['grok', 'claude', 'deepseek'].map((agentType) => ({
          id: agentType,
          name: agentType,
          machineId: 'ui',
          machineName: 'Fixture Mac',
          cliType: 'builtin',
          agentType,
        })),
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
          configOptions: [
            {
              id: 'fast-mode',
              name: 'Fast mode',
              category: 'model_config',
              type: 'boolean',
              currentValue: false,
              options: [],
            },
            select('collaboration_mode', 'Collaboration mode', [
              'default',
              'plan',
            ]),
          ],
          steer: true,
        },
        {
          machineId: 'ui',
          cliType: 'builtin',
          agentType: 'grok',
          models: [
            { id: 'grok-a', name: 'Grok A' },
            { id: 'grok-b', name: 'Grok B' },
          ],
          modes: [
            { id: 'agent', name: 'Agent' },
            { id: 'plan', name: 'Plan' },
          ],
          reasoningEfforts: {
            'grok-a': ['low', 'high'],
            'grok-b': ['low', 'high'],
          },
          configOptions: [
            select(
              'interaction_mode',
              'Interaction Mode',
              ['agent', 'plan'],
              'mode',
            ),
            select(
              'permission_mode',
              'Permission Mode',
              ['ask', 'auto', 'always-approve'],
              '_permission',
            ),
          ],
          steer: false,
        },
        {
          machineId: 'ui',
          cliType: 'builtin',
          agentType: 'claude',
          models: [{ id: 'claude', name: 'Claude' }],
          modes: [],
          reasoningEfforts: {},
          configOptions: [
            select('model', 'Model', ['claude'], 'model'),
            select('effort', 'Effort', ['low', 'high'], 'thought_level'),
            {
              id: 'fast',
              name: 'Fast mode',
              category: 'model_config',
              type: 'boolean',
              currentValue: false,
              options: [],
            },
          ],
          steer: false,
        },
        {
          machineId: 'ui',
          cliType: 'builtin',
          agentType: 'deepseek',
          models: [],
          modes: [],
          reasoningEfforts: {},
          configOptions: [
            select('agent_preset', 'Agent preset', ['standard', 'coder']),
          ],
          steer: false,
        },
      ],
    }),
  });
}
