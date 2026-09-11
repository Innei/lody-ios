import { uiVerify } from './uiVerify';
import { Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert } from 'react-native';
import { NativeChat, copyText } from '@lody-ios/kit';
import { sessionDebugText } from '@/features/sessions/sessionDebug';
import { t } from '@/lib/i18n/index.ts';
import { definePage, present } from '@/lib/presentation';
import { FileDiffScreen } from '@/screens/FileDiffScreen';
import { ItemDetailScreen } from '@/screens/ItemDetailScreen';
import { basename } from '@/features/sessions/path';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import {
  PermissionScreen,
  type PermissionService,
} from '@/screens/PermissionScreen';
import type {
  PermissionTarget,
  PermissionTargetSource,
} from '@/features/sessions/permissionTarget';

const answer = `## 原生聊天布局\n\n列表使用 **UICollectionView**，正文直接由 UIKit 渲染。\n\n- 输入区始终可见，跟随键盘移动\n- 执行过程在 Sheet 中平铺\n- 完成后保持回答和过程入口\n\n### 代码示例\n\n\`\`\`swift\nlet layout = UICollectionViewFlowLayout()\nlet list = UICollectionView(\n  frame: .zero,\n  collectionViewLayout: layout\n)\n\`\`\`\n\n这是一条用于检查换行、**粗体**和 \`inline code\` 的较长段落。切换浅色和深色外观，正文和输入框都应清晰可读。\n\n> 引用块用于确认左侧竖条与次级文字颜色。\n\n1. 有序列表\n   - 嵌套的无序项\n   - [x] 已完成的任务\n   - [ ] 未完成的任务\n2. 第二项，见 [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/)\n\n| table-bleed-start | table-bleed-mid | table-bleed-end |\n| --- | --- | --- |\n| AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA | BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB | CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC |\n\n---\n\n分割线之后的收尾段落。`;
const history = Array.from({ length: 80 }, (_, index) => ({
  id: `history-${index}`,
  role: index % 2 ? 'assistant' : 'user',
  status: 'completed',
  finished: true,
  items: [
    {
      itemId: 'text',
      type: 'text',
      text:
        index % 2
          ? `第 ${index} 条历史回答。\n\n${answer}`
          : '请继续检查聊天页面的原生布局。',
    },
  ],
}));

const totalLength = answer.length + 240;
const previewDebugBody = sessionDebugText({
  session: {
    id: 'preview',
    machineId: 'studio',
    title: '原生聊天预览',
    status: 'idle',
    archived: false,
    pinned: false,
    projectId: 'lody-ios',
    createdAt: '2026-01-01T00:00:00.000Z',
    cliType: 'claude',
    agentType: 'coder',
    branchName: 'main',
  },
  project: {
    id: 'lody-ios',
    name: 'lody-ios',
    rootPath: '/Users/innei/git/innei-repo/lody-ios',
  },
  machineName: 'Studio',
  workspace: { id: 'preview-workspace', name: 'preview', slug: 'preview' },
  userId: 'preview-user',
  connection: { state: 'live', machines: 1 },
  transcript: { status: 'live', revision: 1, overflow: false },
  choice: { modelId: 'gpt-5.6-sol', effort: 'high' },
});

function editStatus(mode: 'normal' | 'attention', length: number) {
  if (mode === 'attention') return 'failed';
  if (length < 240) return 'in_progress';
  return 'completed';
}

const permissionTarget: PermissionTarget = {
  entryId: 'preview',
  itemId: 'edit',
  requestId: 'ui-verify-request',
  options: [
    { optionId: 'allow', name: 'Allow once', kind: 'allow_once' },
    { optionId: 'always', name: 'Always allow', kind: 'allow_always' },
    { optionId: 'reject', name: 'Reject', kind: 'reject_once' },
    { optionId: 'custom', name: 'Custom choice' },
  ],
  kind: 'execute',
  title: '在 lody-ios 中执行命令',
  path: undefined,
};

// Resolves late so the sheet opens before the target is known, then clears the
// request the way a desktop answer would, so the sheet must close on its own.
const permissionSource: PermissionTargetSource = (onState) => {
  onState({ ready: false });
  if (uiVerify) {
    // Let the driver observe each state before advancing the fixture.
    const update = (available: boolean) =>
      onState({
        ready: true,
        target: available ? permissionTarget : undefined,
      });
    globalThis.__lodyUiVerifyPermissionTarget = update;
    return () => {
      if (globalThis.__lodyUiVerifyPermissionTarget === update)
        globalThis.__lodyUiVerifyPermissionTarget = undefined;
    };
  }
  const resolve = setTimeout(
    () => onState({ ready: true, target: permissionTarget }),
    2000,
  );
  const answered = setTimeout(() => onState({ ready: true }), 10_000);
  return () => {
    clearTimeout(resolve);
    clearTimeout(answered);
  };
};

const permissionService: PermissionService = {
  // Empty detail options prove the sheet renders the synced request's actions.
  detail: async () => ({
    options: [],
    command: {
      type: 'terminal_command',
      command: 'pnpm',
      args: ['verify:ui'],
      cwd: '/Users/lody/lody-ios',
    },
  }),
  respond: async () => 'accepted',
};

const questionTarget: PermissionTarget = {
  ...permissionTarget,
  requestId: 'ui-verify-questions',
  kind: 'ask_user_question',
  title: 'Project preferences',
  questionMeta: {
    source: 'lody',
    version: 1,
    allowCustomAnswer: true,
    questions: [
      {
        id: 'language',
        header: 'Language',
        question: 'Which language should we use?',
        multiSelect: false,
        options: [
          { label: 'Swift', description: 'Native iOS implementation' },
          { label: 'TypeScript', description: 'Shared app logic' },
        ],
      },
      {
        id: 'checks',
        header: 'Checks',
        question: 'Which checks should run?',
        multiSelect: true,
        options: [{ label: 'Unit tests' }, { label: 'UI tests' }],
      },
      {
        id: 'notes',
        header: 'Notes',
        question: 'Anything else we should know?',
        multiSelect: false,
        allowCustomAnswer: true,
        options: [],
      },
    ],
  },
};

function openQuestionFixture() {
  let attempts = 0;
  const source: PermissionTargetSource = (onState) => {
    onState({ ready: true, target: questionTarget });
    const probe = { remoteAnswer: () => onState({ ready: true }), attempts: 0 };
    if (uiVerify) globalThis.__lodyUiVerifyQuestion = probe;
    return () => {
      if (globalThis.__lodyUiVerifyQuestion === probe)
        globalThis.__lodyUiVerifyQuestion = undefined;
    };
  };
  void present(
    PermissionScreen,
    {
      sessionId: 'ui-verify-question',
      generation: 0,
      target: questionTarget,
      source,
      service: {
        detail: async () => ({ options: [] }),
        respond: async (_session, _target, _option, answers) => {
          attempts += 1;
          if (uiVerify && globalThis.__lodyUiVerifyQuestion) {
            globalThis.__lodyUiVerifyQuestion.answers = answers;
            globalThis.__lodyUiVerifyQuestion.attempts = attempts;
          }
          if (attempts === 1) throw new Error('upload_failed');
          return 'accepted';
        },
      },
    },
    { title: t('question.title') },
  );
}

function View() {
  const [showImage, setShowImage] = useState(false);
  const [showChanges, setShowChanges] = useState(false);
  const [durationFixture, setDurationFixture] = useState<{
    startedAt: number;
    finished: boolean;
    permissionWaitMs?: number;
  } | null>(null);
  const [length, setLength] = useState(totalLength);
  const [navigationTitle, setNavigationTitle] = useState('原生聊天预览');
  const [sessionActionsReady, setSessionActionsReady] = useState(false);
  const [step, setStep] = useState(48);
  const [mode, setMode] = useState<'normal' | 'attention'>('normal');
  const [composerOptions, setComposerOptions] = useState({
    modelId: 'gpt-5.6-sol',
    effort: 'medium',
    fast: false,
  });
  const [clearDraftToken, setClearDraftToken] = useState(0);
  const [sent, setSent] = useState<{
    text: string;
    id: number;
    messageID: string;
  } | null>(null);
  useEffect(() => {
    if (length >= totalLength) return;
    const timer = setInterval(
      () => setLength((old) => Math.min(totalLength, old + step)),
      700,
    );
    return () => clearInterval(timer);
  }, [length < totalLength, step]);
  const entriesJSON = JSON.stringify([
    ...(showImage
      ? [
          {
            id: 'preview-image',
            role: 'user',
            status: 'completed',
            finished: true,
            items: [
              {
                itemId: 'photo',
                type: 'image',
                image: {
                  id: 'ui-verify-image',
                  fileName: 'fixture.png',
                  width: 600,
                  height: 400,
                },
              },
              { itemId: 'caption', type: 'text', text: '离线图片验收' },
            ],
          },
        ]
      : history),
    ...(sent
      ? [
          {
            id: sent.messageID,
            role: 'user',
            status: 'completed',
            finished: true,
            items: [{ itemId: 'text', type: 'text', text: sent.text }],
          },
        ]
      : []),
    {
      id: sent ? `preview-${sent.id}` : 'preview',
      role: 'assistant',
      status: length < totalLength ? 'running' : 'completed',
      finished: length >= totalLength,
      modelInfo: {
        modelId: 'gpt-5.6-sol',
        name: 'GPT-5.6 Sol',
        thoughtLevel: 'High',
      },
      items: [
        {
          itemId: 'intro',
          type: 'text',
          text: '先检查消息列表和导航栏的连接。'.slice(0, Math.max(1, length)),
        },
        ...(length >= 24
          ? [
              {
                itemId: 'thought',
                type: 'thought',
                text: '先核对原生标题与滚动列表所属的控制器。'.slice(
                  0,
                  length - 23,
                ),
              },
            ]
          : []),
        ...(length >= 48
          ? [
              {
                itemId: 'read',
                type: 'tool_call',
                kind: 'read',
                title: '读取 SessionScreen.tsx',
                status: length < 96 ? 'in_progress' : 'completed',
                hasDetail: true,
              },
            ]
          : []),
        ...(length >= 96
          ? [
              {
                itemId: 'middle',
                type: 'text',
                text: '标题已经接入原生，接下来检查正文布局。',
              },
            ]
          : []),
        ...(length >= 144
          ? [
              {
                itemId: 'thought-two',
                type: 'thought',
                text: '接下来核对段落高度，确认完成后只保留结论。'.slice(
                  0,
                  length - 143,
                ),
              },
            ]
          : []),
        ...(length >= 192
          ? [
              {
                itemId: 'edit',
                type: 'tool_call',
                kind: 'edit',
                title: '修改 ChatView.swift',
                status: editStatus(mode, length),
                hasDetail: true,
              },
            ]
          : []),
        ...(length >= 240
          ? [
              {
                itemId: 'answer',
                type: 'text',
                text: answer.slice(0, length - 240),
              },
            ]
          : []),
      ],
    },
  ]);
  let displayedEntriesJSON = entriesJSON;
  if (durationFixture) {
    displayedEntriesJSON = JSON.stringify([
      {
        id: 'duration-preview',
        role: 'assistant',
        status: durationFixture.finished ? 'completed' : 'running',
        finished: durationFixture.finished,
        modelInfo: {
          modelId: 'gpt-5.6-sol',
          name: 'GPT-5.6 Sol',
          thoughtLevel: 'High',
        },
        timestamp: new Date(durationFixture.startedAt).toISOString(),
        startedAt: durationFixture.startedAt,
        endedAt: durationFixture.finished
          ? durationFixture.startedAt + 65_000
          : undefined,
        permissionWaitMs: durationFixture.permissionWaitMs,
        items: [
          {
            itemId: 'work',
            type: 'tool_call',
            kind: 'read',
            title: '读取计时数据',
            status: durationFixture.finished ? 'completed' : 'in_progress',
            hasDetail: false,
          },
          ...(durationFixture.finished
            ? [
                {
                  itemId: 'answer',
                  type: 'text',
                  text: '计时完成。',
                },
              ]
            : []),
        ],
      },
    ]);
  } else if (showChanges) {
    displayedEntriesJSON = JSON.stringify([
      {
        id: 'diff-user',
        role: 'user',
        status: 'handled',
        finished: true,
        items: [
          {
            itemId: 'text',
            type: 'text',
            text: '修改文件，然后回复 done。',
          },
        ],
      },
      {
        id: 'diff-preview',
        role: 'assistant',
        status: 'pending',
        finished: true,
        items: [
          {
            itemId: 'edit',
            type: 'tool_call',
            kind: 'edit',
            title: 'Editing files',
            status: 'completed',
          },
          { itemId: 'answer', type: 'text', text: 'done' },
        ],
        fileDiffs: [
          { path: 'docs/superpowers/.diff-check.md', add: 1, del: 1 },
          {
            path: 'src/very-long-directory-name/nested/components/another-long-file-name.ts',
            add: 1,
            del: 1,
          },
        ],
      },
      {
        id: 'diff-warning',
        role: 'system',
        status: 'pending',
        finished: false,
        items: [
          {
            itemId: 'notice',
            type: 'system_notice',
            name: 'agent_warning',
          },
        ],
      },
      {
        id: 'diff-cached-warning',
        role: 'system',
        status: 'pending',
        finished: false,
        items: [{ itemId: 'notice', type: 'system_notice' }],
      },
    ]);
  } else if (showImage) {
    displayedEntriesJSON = JSON.stringify(JSON.parse(entriesJSON).slice(0, 1));
  }
  const openProcess = useProcessSheet(displayedEntriesJSON, () =>
    setMode('attention'),
  );
  return (
    <>
      <Stack.Screen options={{ title: navigationTitle }} />
      <Stack.Toolbar placement="right">
        {uiVerify && (
          <Stack.Toolbar.Menu icon="wrench" accessibilityLabel="Fixtures">
            <Stack.Toolbar.MenuAction
              children="Session Created"
              icon="checkmark"
              onPress={() => setSessionActionsReady(true)}
            />
            <Stack.Toolbar.MenuAction
              children="Rename Session"
              icon="pencil"
              onPress={() => setNavigationTitle('Updated session title')}
            />
            <Stack.Toolbar.MenuAction
              children="Diff Fixture"
              icon="doc.text"
              onPress={() => {
                setDurationFixture(null);
                setShowImage(false);
                setShowChanges(true);
              }}
            />
            <Stack.Toolbar.MenuAction
              children="Image Fixture"
              icon="photo"
              onPress={() => {
                setDurationFixture(null);
                setShowChanges(false);
                setShowImage(true);
              }}
            />
            <Stack.Toolbar.MenuAction
              children="Duration Fixture"
              icon="timer"
              onPress={() => {
                setShowImage(false);
                setShowChanges(false);
                setDurationFixture({
                  startedAt: Date.now(),
                  finished: false,
                });
              }}
            />
            <Stack.Toolbar.MenuAction
              children="Inline Diff Fixture"
              icon="plusminus"
              onPress={() =>
                void present(ItemDetailScreen, {
                  sessionId: 'ui-verify-diff',
                  entryId: 'diff-preview',
                  itemIds: ['edit'],
                  generation: 0,
                })
              }
            />
            <Stack.Toolbar.MenuAction
              children="Permission Fixture"
              icon="lock.open"
              onPress={() =>
                void present(PermissionScreen, {
                  sessionId: 'ui-verify-permission',
                  generation: 0,
                  source: permissionSource,
                  service: permissionService,
                })
              }
            />
            <Stack.Toolbar.MenuAction
              children="Question Fixture"
              icon="questionmark.bubble"
              onPress={openQuestionFixture}
            />
          </Stack.Toolbar.Menu>
        )}
        {durationFixture && !durationFixture.finished && (
          <Stack.Toolbar.Button
            accessibilityLabel="Finish Duration Fixture"
            icon="stop.circle"
            onPress={() =>
              setDurationFixture((current) =>
                current ? { ...current, finished: true } : current,
              )
            }
          />
        )}
        {durationFixture?.finished && !durationFixture.permissionWaitMs && (
          <Stack.Toolbar.Button
            accessibilityLabel="Wait Duration Fixture"
            icon="hourglass"
            onPress={() =>
              setDurationFixture((current) =>
                current ? { ...current, permissionWaitMs: 5_000 } : current,
              )
            }
          />
        )}
        <Stack.Toolbar.Button
          accessibilityLabel="Fast Replay"
          icon="forward.end"
          onPress={() => {
            setDurationFixture(null);
            setShowImage(false);
            setShowChanges(false);
            setStep(240);
            setMode('normal');
            setLength(0);
          }}
        />
        <Stack.Toolbar.Button
          accessibilityLabel="Retry"
          icon="arrow.trianglehead.clockwise.rotate.90"
          onPress={() => {
            setDurationFixture(null);
            setShowImage(false);
            setShowChanges(false);
            setStep(48);
            setMode('normal');
            setLength(0);
          }}
        ></Stack.Toolbar.Button>
        <Stack.Toolbar.Menu
          icon="ellipsis"
          accessibilityLabel={t('common.more')}
        >
          <Stack.Toolbar.MenuAction icon="square.and.pencil" onPress={() => {}}>
            {t('session.action.newSession')}
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.MenuAction
            icon="pin"
            disabled={uiVerify && !sessionActionsReady}
            onPress={() => {}}
          >
            {t('session.action.pin')}
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.MenuAction
            icon="archivebox"
            disabled={uiVerify && !sessionActionsReady}
            onPress={() => {}}
          >
            {t('session.action.archive')}
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.Menu inline>
            <Stack.Toolbar.MenuAction icon="folder" onPress={() => {}}>
              {t('session.action.projectFiles')}
            </Stack.Toolbar.MenuAction>
          </Stack.Toolbar.Menu>
        </Stack.Toolbar.Menu>
      </Stack.Toolbar>
      <NativeChat
        navigationTitle={navigationTitle}
        navigationSubtitle="lody-ios"
        navigationMachine="Studio"
        onTitlePress={() =>
          Alert.alert(t('session.debug.title'), previewDebugBody, [
            {
              text: t('common.copy'),
              onPress: () => copyText(previewDebugBody),
            },
            { text: t('common.ok'), style: 'cancel' },
          ])
        }
        style={{ flex: 1 }}
        entriesJSON={displayedEntriesJSON}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          sending: false,
          notice: '',
          reconnect: false,
          placeholder: '输入文字，检查键盘布局…',
        })}
        composerOptionsJSON={JSON.stringify({
          ...composerOptions,
          models: [
            { id: 'gpt-5.6-sol', title: 'GPT-5.6 Sol' },
            { id: 'gpt-6-astra', title: 'GPT-6 Astra' },
          ],
          efforts: [
            { id: 'low', title: 'Low' },
            { id: 'medium', title: 'Medium' },
            { id: 'high', title: 'High' },
            { id: 'xhigh', title: 'Extra High' },
            { id: 'ultra', title: 'Ultra' },
          ],
        })}
        clearDraftToken={clearDraftToken}
        emptyText=""
        onSend={({ nativeEvent }) => {
          setStep(48);
          setSent((old) => ({
            text: nativeEvent.text,
            messageID: nativeEvent.id,
            id: (old?.id ?? 0) + 1,
          }));
          setClearDraftToken((old) => old + 1);
          setMode('normal');
          setLength(0);
        }}
        onActivityPress={({ nativeEvent }) =>
          openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
        onReconnect={() => {}}
        onTurnChangesPress={({ nativeEvent }) => {
          if (showChanges)
            void present(
              FileDiffScreen,
              {
                sessionId: 'ui-verify-diff',
                entryId: nativeEvent.entryId,
                path: nativeEvent.path,
              },
              { title: basename(nativeEvent.path) },
            );
        }}
        onComposerOptionChange={({ nativeEvent }) =>
          setComposerOptions((current) => ({ ...current, ...nativeEvent }))
        }
      />
    </>
  );
}
export const ChatPreviewScreen = definePage({
  id: 'chat-preview',
  title: '原生聊天预览',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
