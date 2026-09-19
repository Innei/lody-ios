import { useState } from 'react';
import { Stack } from 'expo-router';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { openMessageShare } from '@/screens/MessageShareScreen';

const prose = `## A quieter way to share

Good ideas deserve room to breathe. This reply becomes a warm paper page, with **clear type** and generous margins.

- Keep the useful words.
- Leave the interface behind.

> A little space makes a long answer easier to read.`;
const rich = `## Notes from the workshop

This image contains the **complete reply**, including content beyond the screen.

${Array.from({ length: 5 }, (_, i) => `### ${i + 1}. Leave room for the idea\n\nA calm page lets the words do the work. The texture stays quiet, the margins stay generous, and the message keeps its natural length.`).join('\n\n')}

\`\`\`swift
let message = "A long line that should wrap inside the printed page without dropping any of the final words: CODE-END"
print(message)
\`\`\`

| Material | Appearance | Result |
| --- | --- | --- |
| Warm paper | A soft, subtle texture | All columns visible |

Inline math: $e^{i\\pi} + 1 = 0$.

**PAPER-END** — the last sentence is part of the image.`;
function View() {
  const [fixture, setFixture] = useState('short');
  let text = prose;
  if (fixture === 'long') text = rich;
  if (fixture === 'large') text = 'A very long reply.\n\n'.repeat(8000);
  if (fixture === 'error')
    text = 'An unavailable image: ![missing](unsupported://missing)';
  const entries = [
    {
      id: 'paper-reply',
      role: 'assistant',
      status: 'completed',
      finished: fixture !== 'streaming',
      modelInfo: fixture === 'no-meta' ? undefined : { name: 'GPT-6 Astra' },
      items: [
        { itemId: 'thought', type: 'thought', text: 'PRIVATE-PROCESS' },
        { itemId: 'answer', type: 'text', text },
        ...(fixture === 'image'
          ? [
              {
                itemId: 'photo',
                type: 'image',
                image: {
                  id: 'ui-verify-image-share',
                  fileName: 'Sample image',
                  width: 640,
                  height: 480,
                },
              },
            ]
          : []),
      ],
    },
  ];
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Menu
          icon="slider.horizontal.3"
          accessibilityLabel="Paper fixtures"
        >
          {[
            'short',
            'long',
            'no-meta',
            'image',
            'large',
            'error',
            'streaming',
          ].map((value) => (
            <Stack.Toolbar.MenuAction
              key={value}
              onPress={() => setFixture(value)}
            >
              {value}
            </Stack.Toolbar.MenuAction>
          ))}
        </Stack.Toolbar.Menu>
      </Stack.Toolbar>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={JSON.stringify(entries)}
        imageSharingEnabled
        onShareImage={({ nativeEvent }) =>
          openMessageShare(nativeEvent.contentJSON)
        }
        composerJSON={'{"editable":false,"canSend":false}'}
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={() => {}}
      />
    </>
  );
}
export const MessageSharePreviewScreen = definePage({
  id: 'message-share-preview',
  title: 'Message sharing',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
