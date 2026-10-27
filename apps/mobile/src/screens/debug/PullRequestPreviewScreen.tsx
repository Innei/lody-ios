import { Alert } from 'react-native';
import { t } from '@/lib/i18n';
import { NativeChat, NativeNavigationHeader } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { PullRequestNativePreviewScreen } from './PullRequestNativePreviewScreen';
import type { PullRequestPreviewData } from '@lody/cloud-runtime/models/pull-request';
import { useState } from 'react';

function previewAction() {
  Alert.alert(t('pr.preview'), t('pr.previewAction'));
}
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
  async function openPreview(
    mode = 'preview',
    state: PullRequestPreviewData['state'] = 'open',
  ) {
    await push(
      PullRequestNativePreviewScreen,
      {
        mode,
        state,
        onInvestigate: () => {
          setAppendDraftJSON(
            JSON.stringify({
              id: String(Date.now()),
              text: 'Investigate PR #31',
            }),
          );
        },
      },
      { title: 'PR #31' },
    );
  }

  return (
    <>
      <NativeNavigationHeader
        items={[
          {
            type: 'button',
            title: 'PR #31',
            accessibilityLabel: 'PR #31，1 项检查失败',
            badge: { value: '!' },
            onPress: () => void openPreview(),
          },
          {
            type: 'menu',
            icon: { type: 'sfSymbol', name: 'ellipsis' },
            accessibilityLabel: '更多',
            menu: {
              items: [
                ...(['merged', 'closed', 'draft'] as const).map((state) => ({
                  type: 'action' as const,
                  title: t(`pr.state.${state}`),
                  onPress: () => void openPreview('preview', state),
                })),
                {
                  type: 'action',
                  title: '空检查预览',
                  onPress: () => void openPreview('empty'),
                },
                {
                  type: 'action',
                  title: '授权失败预览',
                  onPress: () => void openPreview('authorization'),
                },
                {
                  type: 'action',
                  title: '评论发送预览',
                  onPress: () => void openPreview('comment'),
                },
                { type: 'action', title: '关于此预览', onPress: previewAction },
              ],
            },
          },
        ]}
      />
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
