import { uiVerify } from './uiVerify';
import { Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert } from 'react-native';
import { NativeChat } from '@lody-ios/kit';
import { definePage, present } from '@/presentation';
import { fileDiffPage } from '@/features/sessions/changes/fileDiffPage';
import { basename } from '@/features/sessions/changes/turnChangesPage';
import { useProcessSheet } from '@/features/sessions/detail/processPage';
import {
  permissionPage,
  type PermissionService,
} from '@/features/sessions/detail/permissionPage';
import type {
  PermissionTarget,
  PermissionTargetSource,
} from '@/features/sessions/detail/permissionTarget';

const answer = `## 原生聊天布局\n\n列表使用 **UICollectionView**，正文直接由 UIKit 渲染。\n\n- 输入区始终可见，跟随键盘移动\n- 执行过程在 Sheet 中平铺\n- 完成后保持回答和过程入口\n\n### 代码示例\n\n\`\`\`swift\nlet layout = UICollectionViewFlowLayout()\nlet list = UICollectionView(\n  frame: .zero,\n  collectionViewLayout: layout\n)\n\`\`\`\n\n这是一条用于检查换行、**粗体**和 \`inline code\` 的较长段落。切换浅色和深色外观，正文和输入框都应清晰可读。\n\n> 引用块用于确认左侧竖条与次级文字颜色。\n\n1. 有序列表\n   - 嵌套的无序项\n   - [x] 已完成的任务\n   - [ ] 未完成的任务\n2. 第二项，见 [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/)\n\n| 节点 | 状态 |\n| --- | --- |\n| 表格 | 原生 GridView |\n| 公式 | $E = mc^2$ |\n\n---\n\n分割线之后的收尾段落。`;
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

function editStatus(mode: 'normal' | 'attention', length: number) {
  if (mode === 'attention') return 'failed';
  if (length < 240) return 'in_progress';
  return 'completed';
}

const permissionTarget: PermissionTarget = {
  entryId: 'preview',
  itemId: 'edit',
  requestId: 'ui-verify-request',
  kind: 'execute',
  title: '在 lody-ios 中执行命令',
  path: undefined,
};

/** Resolves late on purpose: the sheet must open before the target is known. */
const permissionSource: PermissionTargetSource = (onState) => {
  onState({ ready: false });
  const timer = setTimeout(
    () => onState({ ready: true, target: permissionTarget }),
    2000,
  );
  return () => clearTimeout(timer);
};

const permissionService: PermissionService = {
  detail: async () => ({
    options: [
      { optionId: 'allow', name: 'Allow once', kind: 'allow_once' },
      { optionId: 'always', name: 'Always allow', kind: 'allow_always' },
      { optionId: 'reject', name: 'Reject', kind: 'reject_once' },
    ],
    command: {
      type: 'terminal_command',
      command: 'pnpm',
      args: ['verify:ui'],
      cwd: '/Users/lody/lody-ios',
    },
  }),
  respond: async () => 'accepted',
};

function ChatPreview() {
  const [showImage, setShowImage] = useState(false);
  const [showChanges, setShowChanges] = useState(false);
  const [length, setLength] = useState(totalLength);
  const [step, setStep] = useState(48);
  const [mode, setMode] = useState<'normal' | 'attention'>('normal');
  const [composerOptions, setComposerOptions] = useState({
    modelId: 'gpt-5.6-sol',
    effort: 'medium',
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
  const displayedEntriesJSON = showChanges
    ? JSON.stringify([
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
      ])
    : showImage
      ? JSON.stringify(JSON.parse(entriesJSON).slice(0, 1))
      : entriesJSON;
  const openProcess = useProcessSheet(displayedEntriesJSON, () =>
    setMode('attention'),
  );
  return (
    <>
      <Stack.Toolbar placement="right">
        {uiVerify && (
          <Stack.Toolbar.Button
            accessibilityLabel="Diff Fixture"
            icon="doc.text"
            onPress={() => {
              setShowImage(false);
              setShowChanges(true);
            }}
          />
        )}
        {uiVerify && (
          <Stack.Toolbar.Button
            accessibilityLabel="Image Fixture"
            icon="photo"
            onPress={() => {
              setShowChanges(false);
              setShowImage(true);
            }}
          />
        )}
        {uiVerify && (
          <Stack.Toolbar.Button
            accessibilityLabel="Permission Fixture"
            icon="lock.open"
            onPress={() =>
              void present(permissionPage, {
                sessionId: 'ui-verify-permission',
                generation: 0,
                source: permissionSource,
                service: permissionService,
              })
            }
          />
        )}
        <Stack.Toolbar.Button
          accessibilityLabel="Fast Replay"
          icon="forward.end"
          onPress={() => {
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
            setShowImage(false);
            setShowChanges(false);
            setStep(48);
            setMode('normal');
            setLength(0);
          }}
        ></Stack.Toolbar.Button>
      </Stack.Toolbar>
      <NativeChat
        navigationTitle="原生聊天预览"
        navigationSubtitle="lody-ios"
        onTitlePress={() => Alert.alert('会话详情', '原生 titleView 点击正常')}
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
              fileDiffPage,
              {
                sessionId: 'ui-verify-diff',
                entryId: nativeEvent.entryId,
                path: nativeEvent.path,
              },
              { title: basename(nativeEvent.path) },
            );
        }}
        onComposerOptionChange={({ nativeEvent }) =>
          setComposerOptions(nativeEvent)
        }
      />
    </>
  );
}
export const chatPreviewPage = definePage({
  id: 'chat-preview',
  title: '原生聊天预览',
  Component: ChatPreview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
