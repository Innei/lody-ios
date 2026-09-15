import { useState } from 'react';
import { Button, View as Container } from 'react-native';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { useProcessSheet } from '@/hooks/screens/useProcessSheet';
import { executionProjection } from '../../../modules/lody-kit/data-runtime/execution';

function View() {
  const [count, setCount] = useState(0);
  const [finished, setFinished] = useState(false);
  const raw = Array.from({ length: count + 1 }, (_, index) => [
    {
      id: `steer-user-${index}`,
      role: 'user',
      status: finished || index < count ? 'handled' : 'processing',
      finished: true,
      inputConfig: index ? { _lodyDeliveryKind: 'steer' } : {},
      items: [
        {
          itemId: 'text',
          type: 'text',
          text: index ? `Guidance ${index}` : 'Original task',
        },
      ],
    },
    {
      id: `steer-ai-${index}`,
      role: 'assistant',
      status: 'processing',
      finished: finished || index < count,
      userTurnId: `steer-user-${index}`,
      acpTurnId: 'offline-provider-turn',
      items: [
        { itemId: 'partial', type: 'text', text: `Stage ${index} analysis` },
        {
          itemId: 'tool',
          type: 'tool_call',
          title: `Inspect stage ${index}`,
          status: 'completed',
        },
        ...(finished && index === count
          ? [
              { itemId: 'answer', type: 'text', text: 'Final result' },
              {
                itemId: 'answer-next',
                type: 'text',
                text: 'All guidance incorporated.',
              },
            ]
          : []),
      ],
    },
  ]).flat();
  const projection = executionProjection(raw, true);
  const entriesJSON = JSON.stringify(
    raw.map((entry) => ({ ...entry, ...projection.get(entry.id) })),
  );
  const openProcess = useProcessSheet(entriesJSON, () => {});
  return (
    <Container style={{ flex: 1 }}>
      <Container style={{ flexDirection: 'row', paddingTop: 110 }}>
        <Button
          testID="steer-next"
          title="Add guidance"
          disabled={finished || count === 3}
          onPress={() => setCount((value) => value + 1)}
        />
        <Button
          testID="steer-finish"
          title="Finish"
          disabled={count !== 3 || finished}
          onPress={() => setFinished(true)}
        />
      </Container>
      <NativeChat
        style={{ flex: 1 }}
        navigationTitle="Steer"
        entriesJSON={entriesJSON}
        composerJSON={'{"editable":false,"canSend":false}'}
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onReconnect={() => {}}
        onActivityPress={({ nativeEvent }) =>
          openProcess(nativeEvent.entryId, nativeEvent.processStartId)
        }
      />
    </Container>
  );
}

export const SteerPreviewScreen = definePage({
  id: 'steer-preview',
  title: 'Steer',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
