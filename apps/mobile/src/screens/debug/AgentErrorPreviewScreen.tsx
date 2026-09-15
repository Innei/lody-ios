import { useRef, useState } from 'react';
import { PlatformColor, Text } from 'react-native';
import { useAgentErrorRetry } from '@/features/sessions/useAgentErrorRetry';
import { NativeChat } from '@lody-ios/kit';
import { definePage } from '@/lib/presentation';
import { openAgentError } from '@/hooks/screens/openAgentError';
import type { EntrySummary } from '@/models/session';

const entriesJSON = JSON.stringify([
  {
    id: 'error-system',
    status: 'completed',
    role: 'system',
    finished: true,
    items: [
      {
        itemId: 'failure',
        type: 'system_notice',
        name: 'chat_failed',
        meta: {
          reason: 'acp_provider_overloaded',
          message:
            'Upstream request failed: 429\nProvider capacity exhausted.\nRequest ID: fixture-429',
        },
      },
    ],
  },
  {
    id: 'error-assistant',
    status: 'completed',
    role: 'assistant',
    finished: true,
    items: [
      {
        itemId: 'text',
        type: 'text',
        text: 'Completed answer remains visible.',
      },
      {
        itemId: 'failure',
        type: 'system_notice',
        name: 'chat_failed',
        meta: {
          reason: 'future_reason',
          code: 'future_code',
          message: 'Unrecognized provider error preserved.',
        },
      },
    ],
  },
  {
    id: 'error-missing',
    status: 'completed',
    role: 'system',
    finished: true,
    items: [{ itemId: 'failure', type: 'system_notice', name: 'chat_failed' }],
  },
]);
const original = JSON.parse(entriesJSON) as EntrySummary[];
const entries = [original[1], original[2], original[0]];
const displayJSON = JSON.stringify(entries);

function View() {
  const attempts = useRef(0);
  const [count, setCount] = useState(0);
  const [payload, setPayload] = useState('');
  const retry = useAgentErrorRetry({
    sessionId: 'error-preview',
    entries,
    enabled: true,
    payload: {},
    request: async (payload) => {
      setPayload(payload);
      attempts.current += 1;
      setCount(attempts.current);
      await new Promise((resolve) => setTimeout(resolve, 12000));
      return JSON.stringify({
        state: attempts.current === 1 ? 'not_sent' : 'accepted',
      });
    },
  });
  return (
    <>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={displayJSON}
        errorRetryJSON={retry.stateJSON}
        onErrorRetry={({ nativeEvent }) =>
          void retry.retry(
            nativeEvent.entryId,
            nativeEvent.itemId,
            nativeEvent.id,
          )
        }
        initialDraft="Keep this draft"
        composerJSON={JSON.stringify({
          editable: true,
          canSend: !retry.pending,
        })}
        clearDraftToken={0}
        emptyText=""
        onSend={() => {}}
        onActivityPress={({ nativeEvent }) => {
          openAgentError(
            entries
              .find((entry) => entry.id === nativeEvent.entryId)
              ?.items.find((item) => item.itemId === nativeEvent.itemId),
          );
        }}
        onReconnect={() => {}}
      />
      <Text
        testID="error-retry-payload"
        accessibilityLabel={payload}
        numberOfLines={1}
        style={{
          height: 14,
          fontSize: 10,
          paddingHorizontal: 16,
          color: PlatformColor('secondaryLabel'),
        }}
      >
        Last retry request
      </Text>
      <Text
        testID="error-retry-count"
        accessibilityLabel={String(count)}
        numberOfLines={1}
        style={{
          height: 14,
          fontSize: 10,
          paddingHorizontal: 16,
          color: PlatformColor('secondaryLabel'),
        }}
      >
        Retry attempts: {count}
      </Text>
    </>
  );
}

export const AgentErrorPreviewScreen = definePage({
  id: 'agent-error-preview',
  title: 'Agent 错误预览',
  Component: View,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
