import { Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';

// A deterministic synthetic token is four UTF-16 units (not a model tokenizer).
// 300 tokens/s = 1,200 units/s, delivered in 50ms chunks for twelve seconds.
const seconds = 12;
const unitsPerSecond = 1_200;
const size = seconds * unitsPerSecond;
const samples = {
  offscreen:
    'OFFSCREEN SCROLL\n\n' +
    'Stable paragraph with **Markdown** and `code`. Read earlier content while the answer continues.\n\n'.repeat(
      200,
    ),
  paragraphs: Array.from(
    { length: 240 },
    (_, index) =>
      `### 第 ${index + 1} 段\n\n持续输出 **Markdown**，保留已经完成的段落和原生排版。新增内容应及时出现，滚动跟随不能越落越远。\n\n- 稳定内容复用\n- 新内容渐显\n\n`,
  ).join(''),
  text: '长段落持续追加文字，**保留粗体**与 `inline code`。Swift UIKit streaming text. '.repeat(
    400,
  ),
  code: `\`\`\`swift\n${Array.from({ length: 600 }, (_, index) => `let value${index} = "streaming code ${index}"`).join('\n')}`,
};
type Sample = keyof typeof samples;
const sampleIcons = {
  offscreen: 'arrow.up.arrow.down',
  paragraphs: 'text.alignleft',
  text: 'text.justify',
  code: 'chevron.left.forwardslash.chevron.right',
} as const;
const syntax = [
  'Read **bold',
  'Read **bold** and `code',
  'Read **bold** and `code`.\n\nVisit [Apple](https://exam',
  'Read **bold** and `code`.\n\nVisit [Apple](https://example.com)',
  'Read **bold** and `code`.\n\nVisit [Apple](https://example.com)\n\nStopped **literal',
];

function View() {
  const [sample, setSample] = useState<Sample>('paragraphs');
  const [run, setRun] = useState(0);
  const [length, setLength] = useState(0);
  const [startedAt, setStartedAt] = useState(0);
  const [syntaxStep, setSyntaxStep] = useState<number | null>(null);
  useEffect(() => {
    if (!run || syntaxStep !== null) return;
    const timer = setInterval(() => {
      const elapsed = Math.max(0, Date.now() - startedAt);
      setLength(Math.min(size, Math.floor((elapsed * unitsPerSecond) / 1000)));
      if (elapsed >= seconds * 1000) clearInterval(timer);
    }, 50);
    return () => clearInterval(timer);
  }, [run, startedAt, syntaxStep]);
  let finished = length === size;
  let text = samples[sample].slice(0, length);
  if (syntaxStep !== null) {
    text = syntax[Math.min(syntaxStep, syntax.length - 1)];
    finished = syntaxStep === syntax.length;
  } else if (finished) {
    if (sample === 'code') text += '\n```';
    text += '\n\nSTREAM COMPLETE';
  }
  const entriesJSON = JSON.stringify([
    ...Array.from({ length: syntaxStep === null ? 40 : 0 }, (_, index) => ({
      id: `stream-perf-history-${index}`,
      role: index % 2 ? 'assistant' : 'user',
      status: 'completed',
      finished: true,
      items: [
        {
          itemId: 'text',
          type: 'text',
          text: `History ${index}\n\n这段历史在流式输出时保持不变。`,
        },
      ],
    })),
    {
      id: 'stream-perf-answer',
      role: 'assistant',
      status: finished ? 'completed' : 'running',
      finished,
      startedAt,
      items: [{ itemId: 'text', type: 'text', text }],
    },
  ]);
  return (
    <>
      <Stack.Toolbar placement="right">
        <Stack.Toolbar.Button
          accessibilityLabel="Next syntax"
          icon="textformat"
          onPress={() => {
            setSyntaxStep((value) => ((value ?? -1) + 1) % (syntax.length + 1));
          }}
        >
          Syntax
        </Stack.Toolbar.Button>
        {(['paragraphs', 'text', 'code', 'offscreen'] as const).map((name) => (
          <Stack.Toolbar.Button
            key={name}
            accessibilityLabel={`Stream ${name}`}
            icon={sampleIcons[name]}
            onPress={() => {
              setSyntaxStep(null);
              setSample(name);
              setLength(0);
              setStartedAt(Date.now() + 1_000);
              setRun((value) => value + 1);
            }}
          >
            {name}
          </Stack.Toolbar.Button>
        ))}
      </Stack.Toolbar>
      <NativeChat
        key={run}
        style={{ flex: 1 }}
        navigationTitle={
          syntaxStep === null
            ? `300 TPS · ${sample}`
            : `Syntax ${syntaxStep + 1}`
        }
        debugStreamBenchmarkRun={syntaxStep === null ? run : 0}
        entriesJSON={entriesJSON}
        composerJSON='{"editable":false,"canSend":false}'
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </>
  );
}

export const ChatStreamPerformanceScreen = definePage({
  id: 'chat-stream-performance',
  title: '300 TPS',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
