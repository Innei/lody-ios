import { Stack } from 'expo-router';
import { Alert } from 'react-native';
import { t } from '@/lib/i18n';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { PullRequestScreen } from '../PullRequestScreen';
import type { PullRequestPreviewData } from '@/models/pull-request';
import { createPullRequestSource } from '@/features/pull-request/source';
import { useState } from 'react';

function previewAction() {
  Alert.alert(t('pr.preview'), t('pr.previewAction'));
}
const actions = {
  openGitHub: previewAction,
  share: previewAction,
  investigate: previewAction,
  comment: async () => {
    previewAction();
    return false;
  },
};

const data: PullRequestPreviewData = {
  state: 'open',
  author: 'Innei',
  comments: [],
  repository: 'Innei/lody-ios',
  number: 31,
  title: 'fix: automatically reconnect session stream reads',
  body: '会话同步在临时断线后自动重连。\n\n保留已有消息和读取位置，使用指数退避重试。离开会话时取消等待，恢复连接后继续同步。\n\n仅重试读取，不会重新发送消息或重复执行机器命令。',
  headRef: 'fix/session-auto-reconnect',
  baseRef: 'main',
  headSha: 'ed40e8079',
  additions: 229,
  deletions: 16,
  changedFiles: 4,
  commits: 1,
  checks: [
    {
      id: 1,
      name: 'Checks',
      status: 'completed',
      conclusion: 'failure',
      appName: 'GitHub Actions',
      htmlUrl: null,
    },
    {
      id: 2,
      name: 'Native behavior',
      status: 'completed',
      conclusion: 'success',
      appName: 'GitHub Actions',
      htmlUrl: null,
    },
    {
      id: 3,
      name: 'Build iOS Simulator',
      status: 'completed',
      conclusion: 'success',
      appName: 'GitHub Actions',
      htmlUrl: null,
    },
    {
      id: 4,
      name: 'Offline iOS UI · Pages',
      status: 'in_progress',
      conclusion: null,
      appName: 'GitHub Actions',
      htmlUrl: null,
    },
    {
      id: 5,
      name: 'Offline iOS UI · Chat',
      status: 'queued',
      conclusion: null,
      appName: 'GitHub Actions',
      htmlUrl: null,
    },
  ],
};
const entries = [
  {
    id: 'pr-user',
    role: 'user',
    status: 'completed',
    finished: true,
    items: [
      {
        itemId: 'text',
        type: 'text',
        text: '断线之后让会话自动重连，完成后创建 PR。',
      },
    ],
  },
  {
    id: 'pr-answer',
    role: 'assistant',
    status: 'completed',
    finished: true,
    items: [
      {
        itemId: 'text',
        type: 'text',
        text: '已完成自动重连，并创建 **PR #31**。\n\n读取失败后会保留当前消息和位置，等待连接恢复。发送操作不会自动重放。\n\nCI 有一项检查失败，可以从右上角的 PR 入口查看详情。',
      },
    ],
  },
];
function View() {
  const { push } = usePageRuntime();
  const [appendDraftJSON, setAppendDraftJSON] = useState('');
  async function openPreview(mode = 'preview') {
    let current = data;
    if (mode === 'empty') current = { ...data, checks: [] };
    let reads = 0;
    let writes = 0;
    const source = createPullRequestSource(
      async () => {
        reads++;
        if (mode === 'authorization' && reads === 1)
          throw new Error('authorization_required');
        return current;
      },
      async (body) => {
        writes++;
        if (mode === 'comment' && writes === 1) throw new Error('forbidden');
        current = {
          ...current,
          comments: [{ id: 1, body, author: 'Preview', url: '' }],
        };
      },
    );
    try {
      await push(
        PullRequestScreen,
        {
          source,
          actions: {
            ...actions,
            investigate: () => {
              setAppendDraftJSON(
                JSON.stringify({
                  id: String(Date.now()),
                  text: 'Investigate PR #31',
                }),
              );
              Alert.alert(t('pr.investigate'), t('pr.draftAdded'));
            },
            comment: async (body) => {
              if (mode === 'preview') {
                previewAction();
                return false;
              }
              await source.postComment(body);
              return true;
            },
          },
        },
        { title: 'PR #31' },
      );
    } finally {
      source.dispose();
    }
  }
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          accessibilityLabel="PR #31，1 项检查失败"
          onPress={() => void openPreview()}
        >
          PR #31
          <Stack.Toolbar.Badge>!</Stack.Toolbar.Badge>
        </Stack.Toolbar.Button>
        <Stack.Toolbar.Menu icon="ellipsis" accessibilityLabel="更多">
          <Stack.Toolbar.MenuAction onPress={() => void openPreview('empty')}>
            空检查预览
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.MenuAction
            onPress={() => void openPreview('authorization')}
          >
            授权失败预览
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.MenuAction onPress={() => void openPreview('comment')}>
            评论发送预览
          </Stack.Toolbar.MenuAction>
          <Stack.Toolbar.MenuAction onPress={previewAction}>
            关于此预览
          </Stack.Toolbar.MenuAction>
        </Stack.Toolbar.Menu>
      </Stack.Toolbar>
      <NativeChat
        appendDraftJSON={appendDraftJSON}
        style={{ flex: 1 }}
        navigationTitle="会话自动重连"
        navigationSubtitle="lody-ios"
        entriesJSON={JSON.stringify(entries)}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          sending: false,
          notice: '',
          reconnect: false,
          placeholder: '继续讨论这个 PR…',
        })}
        clearDraftToken={0}
        emptyText=""
        onSend={previewAction}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </>
  );
}
export const PullRequestPreviewScreen = definePage({
  id: 'pull-request-preview',
  title: '会话自动重连',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
