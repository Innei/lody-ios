import { useEffect } from 'react';
import {
  NativeChat,
  NativeNavigationHeader,
  dismissSessionBanner,
  showSessionBanner,
} from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';

const title = 'Fix login token refresh';
const entriesJSON = JSON.stringify([
  {
    id: 'user',
    role: 'user',
    status: 'completed',
    finished: true,
    items: [{ itemId: 'text', type: 'text', text: '把登录刷新逻辑拆出来' }],
  },
  {
    id: 'reply',
    role: 'assistant',
    status: 'completed',
    finished: true,
    items: [
      {
        itemId: 'text',
        type: 'text',
        text: '正在改 token 刷新，先看现有的拦截器。\n\n下面还有一段比较长的正文，用来衬出玻璃后面的聊天内容。切换浅色和深色时，横幅应仍然可读。',
      },
    ],
  },
  {
    id: 'user-2',
    role: 'user',
    status: 'completed',
    finished: true,
    items: [
      { itemId: 'text', type: 'text', text: '继续检查聊天页上的横幅位置。' },
    ],
  },
  {
    id: 'reply-2',
    role: 'assistant',
    status: 'running',
    finished: false,
    items: [
      {
        itemId: 'read',
        type: 'tool_call',
        kind: 'read',
        title: '读取 SessionScreen.tsx',
        status: 'in_progress',
        hasDetail: true,
      },
    ],
  },
]);

function View() {
  useEffect(() => () => dismissSessionBanner(), []);
  return (
    <>
      <NativeNavigationHeader
        items={[
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'checkmark' },
            accessibilityLabel: 'Completed banner',
            onPress: () => showSessionBanner(title, 'completed'),
          },
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'exclamationmark.circle' },
            accessibilityLabel: 'Approval banner',
            onPress: () => showSessionBanner(title, 'attention'),
          },
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'xmark' },
            accessibilityLabel: 'Dismiss banner',
            onPress: () => dismissSessionBanner(),
          },
        ]}
      />
      <NativeChat
        style={{ flex: 1 }}
        navigationTitle="会话横幅"
        entriesJSON={entriesJSON}
        composerJSON={JSON.stringify({
          editable: false,
          canSend: false,
          sending: false,
          notice: '',
          reconnect: false,
          placeholder: '',
        })}
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </>
  );
}

export const BannerPreviewScreen = definePage({
  id: 'banner-preview',
  title: '会话横幅',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
