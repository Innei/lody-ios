import { Stack } from 'expo-router';
import { useState } from 'react';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';

function View() {
  const [run, setRun] = useState(0);
  const [entriesJSON] = useState(() =>
    JSON.stringify(
      Array.from({ length: 10_000 }, (_, index) => ({
        id: `perf-${index}`,
        role: index % 2 ? 'assistant' : 'user',
        status: 'completed',
        finished: true,
        modelInfo: index % 2 ? { name: 'Benchmark model' } : undefined,
        items: [
          {
            itemId: 'text',
            type: 'text',
            text:
              index % 2
                ? `## Message ${index + 1}\n\n${'这是混合长度的 **Markdown** 回答，包含行内代码 \`value\`。\n\n'.repeat(1 + (index % 5))}- 检查原生消息复用\n- 快速滚动与内存采样\n\n\`\`\`swift\nlet message = ${index + 1}\nprint(message)\n\`\`\``
                : `Message ${index + 1}：请检查聊天列表。${'这是一段较长的用户消息。'.repeat(index % 7)}`,
          },
        ],
      })),
    ),
  );
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          accessibilityLabel="Run Chat Benchmark"
          icon="play"
          onPress={() => setRun((value) => value + 1)}
        />
      </Stack.Toolbar>
      <NativeChat
        style={{ flex: 1 }}
        navigationTitle="10,000 Messages"
        entriesJSON={entriesJSON}
        debugBenchmarkRun={run}
        composerJSON='{"editable":false,"canSend":false}'
        clearDraftToken={0}
        emptyText="Loading 10,000 messages…"
        onSend={() => {}}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </>
  );
}

export const ChatPerformanceScreen = definePage({
  id: 'chat-performance',
  title: '10,000 Messages',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
