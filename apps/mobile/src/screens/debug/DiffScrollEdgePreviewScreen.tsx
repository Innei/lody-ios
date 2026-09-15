import { useState } from 'react';
import { useColorScheme, View as RNView } from 'react-native';
import { NativeDiffSurface, NativeDiffToolbar } from '@lody-ios/kit';
import { DiffView } from '@/features/diff/DiffView';
import { definePage } from '@/lib/presentation';

const oldText = Array.from(
  { length: 70 },
  (_, index) => `const row${index} = "before";`,
).join('\n');
const newText = oldText.replaceAll('before', 'after');

function View() {
  const [diffStyle, setDiffStyle] = useState<'unified' | 'split'>('unified');
  const [revision, setRevision] = useState(0);
  const theme = useColorScheme() === 'dark' ? 'dark' : 'light';
  return (
    <NativeDiffSurface style={{ flex: 1 }} contentRevision={revision}>
      <DiffView
        path="scroll-edges.ts"
        oldText={oldText}
        newText={newText}
        diffStyle={diffStyle}
        theme={theme}
        dom={{
          shared: true,
          matchContents: false,
          scrollEnabled: true,
          style: { flex: 1 },
          onMessage: (event) => {
            try {
              if (
                JSON.parse(event.nativeEvent.data).type === 'lody:diff-rendered'
              ) {
                setRevision((value) => value + 1);
              }
            } catch {
              /* Non-document bridge messages are not render completions. */
            }
          },
        }}
      />
      <NativeDiffToolbar
        testID="scroll-edge-diff-toolbar"
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          bottom: 16,
          height: 56,
        }}
        add={70}
        del={70}
        diffStyle={diffStyle}
        onStyleChange={({ nativeEvent }) => setDiffStyle(nativeEvent.style)}
      />
      {revision > 0 ? (
        <RNView
          accessible
          testID="scroll-edge-diff-ready"
          accessibilityLabel="Diff document rendered"
          pointerEvents="none"
          style={{ position: 'absolute', width: 44, height: 44 }}
        />
      ) : null}
    </NativeDiffSurface>
  );
}

export const DiffScrollEdgePreviewScreen = definePage({
  id: 'scroll-edge-diff',
  title: 'Diff scroll edges',
  Component: View,
});
