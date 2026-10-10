import { useState } from 'react';
import { NativeChat, NativeNavigationHeader } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useOpenFile } from '@/hooks/screens/useOpenFile';

const fixtures: Record<string, string> = {
  Flowchart:
    'graph TD\n    A[Start] --> B{Ready?}\n    B -->|Yes| C[Done]\n    B -->|No| A',
  Sequence:
    'sequenceDiagram\n    participant App\n    participant Cloud\n    App->>Cloud: Send\n    Cloud-->>App: Reply',
  State:
    'stateDiagram-v2\n    [*] --> Idle\n    Idle --> Running: Send\n    Running --> Idle: Done',
  Class:
    'classDiagram\n    class Session {\n        +String title\n        +send()\n    }',
  ER: 'erDiagram\n    PROJECT ||--o{ SESSION : contains',
  XY: 'xychart-beta\n    x-axis [Mon, Tue, Wed]\n    y-axis "Turns" 0 --> 10\n    bar [2, 5, 8]',
  Chinese: 'graph TD\n    A[开始] --> B[结束]',
  Invalid: 'graph SIDEWAYS\n    A[Start] --> B[Done]',
  Unsupported: 'pie\n    "One" : 1\n    "Two" : 2',
  Oversized: 'graph TD\n' + '%% retained source\n'.repeat(129),
  Streaming:
    'graph TD\n    A[Start] --> B{Ready?}\n    B -->|Yes| C[Done]\n    B -->|No| A',
  Plan: 'graph TD\n    A[Plan] --> B[Build]\n    B --> C[Verify]',
};

function View() {
  const [mode, setMode] = useState('Flowchart');
  const openFile = useOpenFile('ui-verify-files');
  const source = fixtures[mode];
  const streaming = mode === 'Streaming';
  const markdown = `Before the diagram.\n\n\`\`\`mermaid\n${source}${streaming ? '' : '\n```\n\nAfter the diagram.'}`;
  const item =
    mode === 'Plan'
      ? {
          itemId: 'plan',
          type: 'proposed_plan',
          markdown,
          status: 'completed',
          isLatest: true,
        }
      : { itemId: 'text', type: 'text', text: markdown };
  return (
    <>
      <NativeNavigationHeader
        title="Mermaid"
        items={[
          {
            type: 'menu',
            accessibilityLabel: 'Diagram fixtures',
            icon: { type: 'sfSymbol', name: 'square.stack' },
            menu: {
              items: Object.keys(fixtures).map((name) => ({
                type: 'action' as const,
                title: name,
                onPress: () => setMode(name),
              })),
            },
          },
          {
            type: 'button',
            accessibilityLabel: 'Document',
            icon: { type: 'sfSymbol', name: 'doc' },
            onPress: () => void openFile('docs/mermaid.md'),
          },
        ]}
      />
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={JSON.stringify([
          {
            id: 'mermaid-preview',
            role: 'assistant',
            status: streaming ? 'in_progress' : 'completed',
            finished: !streaming,
            items: [item],
          },
        ])}
        composerJSON="{}"
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={() => {}}
      />
    </>
  );
}

export const MermaidPreviewScreen = definePage({
  id: 'mermaid-preview',
  title: 'Mermaid',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
