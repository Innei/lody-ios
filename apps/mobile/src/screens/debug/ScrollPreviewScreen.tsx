import { useEffect, useState } from 'react';
import { NativeChat, NativeNavigationHeader } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

const cached = Array.from({ length: 12 }, (_, index) => ({
  id: `scroll-cache-${index}`,
  role: index % 2 ? 'assistant' : 'user',
  status: index === 11 ? 'running' : 'completed',
  finished: index !== 11,
  items: [
    ...(index === 11
      ? [
          {
            itemId: 'intro',
            type: 'text',
            text: '缓存里的回答仍在进行。\n\n这一段会在同步完成后折叠。\n\n同时还有更新的多轮消息到达。',
          },
        ]
      : []),
    {
      itemId: 'text',
      type: 'text',
      text: `缓存消息 ${index}\n\n保留阅读位置，等待最新历史。\n\n这段内容已经显示在本地。`,
    },
  ],
}));
const latest = [
  ...cached.map((entry, index) => {
    if (index === 11) return { ...entry, status: 'completed', finished: true };
    if (index === 8)
      return {
        ...entry,
        items: [
          {
            itemId: 'text',
            type: 'text',
            text: `${entry.items[0].text}\n\n同步补全了上方的内容。\n\n可见消息的位置应保持不变。`,
          },
        ],
      };
    return entry;
  }),
  ...Array.from({ length: 6 }, (_, index) => ({
    id: `scroll-new-${index}`,
    role: index % 2 ? 'assistant' : 'user',
    status: 'completed',
    finished: true,
    items: [
      {
        itemId: 'text',
        type: 'text',
        text: `新消息 ${index}\n\n从旧缓存平滑滚动到这里。\n\n末尾标记 ${index}。`,
      },
    ],
  })),
];
const lines = Array.from(
  { length: 18 },
  (_, index) => `第 ${index + 1} 行：正文持续增长，后面的行应连续移动。`,
).join('\n\n');
const code = `\n\n\`\`\`swift\n${Array.from({ length: 12 }, (_, index) => `let value${index} = ${index}`).join('\n')}\n\`\`\`\n\n流式输出结束。`;
const text = lines + code;

function View() {
  const { cancel } = usePageRuntime();
  const [mode, setMode] = useState<'cache' | 'live' | 'stream' | 'anchor'>(
    'cache',
  );
  const [length, setLength] = useState(0);
  const [run, setRun] = useState(0);
  useEffect(() => {
    if (mode !== 'stream' && mode !== 'anchor') return;
    const timer = setInterval(
      () => setLength((old) => Math.min(text.length, old + 80)),
      450,
    );
    return () => clearInterval(timer);
  }, [mode, run]);
  let entries = cached;
  if (mode === 'live') entries = latest;
  if (mode === 'stream')
    entries = [
      ...cached,
      {
        id: 'scroll-stream',
        role: 'assistant',
        status: 'running',
        finished: false,
        items: [
          {
            itemId: 'body',
            type: 'text',
            text: text.slice(0, Math.max(1, length)),
          },
          {
            itemId: 'tail',
            type: 'text',
            text: '尾部标记：跟随上一行的高度变化。',
          },
        ],
      },
    ];
  if (mode === 'anchor')
    entries = [
      {
        id: 'scroll-anchor-user',
        role: 'user',
        status: 'completed',
        finished: true,
        items: [
          {
            itemId: 'text',
            type: 'text',
            text: '保持这条消息和工作计时的位置。',
          },
        ],
      },
      {
        id: 'scroll-anchor-reply',
        role: 'assistant',
        status: 'running',
        finished: false,
        items: [
          {
            itemId: 'body',
            type: 'text',
            text: lines.slice(0, Math.min(length, 160)),
          },
        ],
      },
    ];
  const entriesJSON = JSON.stringify(entries);
  const { openProcess } = useProcessSheet(entriesJSON, () => {});
  return (
    <>
      <NativeNavigationHeader
        leftItems={[
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'arrow.counterclockwise' },
            accessibilityLabel: 'Cached History',
            onPress: () => {
              setMode('cache');
              setRun((old) => old + 1);
            },
          },
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'arrow.down.circle' },
            accessibilityLabel: 'Sync History',
            onPress: () => setMode('live'),
          },
        ]}
        items={[
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'pin' },
            accessibilityLabel: 'Stream Anchored Turn',
            onPress: () => {
              setLength(0);
              setMode('anchor');
              setRun((old) => old + 1);
            },
          },
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'play' },
            accessibilityLabel: 'Stream Lines',
            onPress: () => {
              setLength(0);
              setMode('stream');
              setRun((old) => old + 1);
            },
          },
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'list.bullet' },
            accessibilityLabel: 'Stream Process',
            onPress: () => {
              setLength(0);
              setMode('stream');
              void openProcess('scroll-stream');
            },
          },
          {
            type: 'button',
            icon: { type: 'sfSymbol', name: 'checkmark' },
            accessibilityLabel: 'Finish Trace',
            onPress: cancel,
          },
        ]}
      />
      <NativeChat
        key={run}
        style={{ flex: 1 }}
        navigationTitle="滚动连续性验收"
        entriesJSON={entriesJSON}
        pendingSendJSON={
          mode === 'anchor'
            ? JSON.stringify({
                id: 'scroll-anchor-user',
                text: '保持这条消息和工作计时的位置。',
                attachments: [],
                status: '',
              })
            : undefined
        }
        composerJSON='{"editable":true,"canSend":false}'
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </>
  );
}

export const ScrollPreviewScreen = definePage({
  id: 'scroll-preview',
  title: '滚动连续性验收',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
