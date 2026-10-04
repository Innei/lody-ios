import { useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { NativeChat } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { EditMessageScreen } from '../EditMessageScreen';
import type { SessionEditSource } from '@/cloud/send/sessionEdit';

const original = [
  {
    id: 'earlier',
    role: 'user',
    finished: true,
    items: [{ type: 'text', text: 'Earlier message stays read-only.' }],
  },
  {
    id: 'prior-reply',
    role: 'assistant',
    finished: true,
    items: [{ type: 'text', text: 'Previous answer.' }],
  },
  {
    id: 'editable',
    role: 'user',
    finished: true,
    items: [{ type: 'text', text: 'Original prompt' }],
  },
  {
    id: 'old-reply',
    role: 'assistant',
    finished: true,
    items: [{ type: 'text', text: 'This reply will be replaced.' }],
  },
].map((entry) => ({
  ...entry,
  status: 'completed',
  rev: 1,
  items: entry.items.map((item) => ({ ...item, itemId: 'text', rev: 1 })),
}));

function Preview() {
  const [entries, setEntries] = useState(original);
  const [payload, setPayload] = useState('');
  const attempts = useRef(0);
  const [edited, setEdited] = useState('');
  const source: SessionEditSource = {
    read: async () => ({ state: 'ready' }),
    prepare: async () => ({
      state: 'ready',
      text: 'Original prompt',
      attachments: [
        {
          id: 'original:0',
          name: 'original.txt',
          uri: 'file:///tmp/edit-original.txt',
          kind: 'file',
        },
        {
          id: 'original:1',
          name: 'keep.txt',
          uri: 'file:///tmp/edit-keep.txt',
          kind: 'file',
        },
      ],
    }),
    send: async (payload) => {
      setPayload(payload);
      attempts.current += 1;
      await new Promise((resolve) => setTimeout(resolve, 1500));
      if (attempts.current === 1) return { state: 'not_sent' };
      const value = JSON.parse(payload);
      setEntries([
        ...original.slice(0, 2),
        {
          id: value.id,
          role: 'user',
          finished: true,
          status: 'completed',
          rev: 1,
          items: [{ type: 'text', text: value.text, itemId: 'text', rev: 1 }],
        },
      ]);
      return { state: 'accepted' };
    },
  };
  return (
    <View style={{ flex: 1 }}>
      <Text testID="edit-fixture-count">{String(attempts.current)}</Text>
      <Text testID="edit-fixture-payload" style={{ height: 1, fontSize: 1 }}>
        {payload}
      </Text>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={JSON.stringify(entries)}
        editableMessageId={edited ? '' : 'editable'}
        editedMessageId={edited}
        initialDraft="Keep this chat draft"
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
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
        onEditMessage={async ({ nativeEvent }) => {
          const result = await present(EditMessageScreen, {
            sessionId: 'edit-preview',
            entryId: nativeEvent.entryId,
            source,
          });
          if (result.status === 'completed') setEdited(result.value);
        }}
      />
    </View>
  );
}

export const EditMessagePreviewScreen = definePage({
  id: 'edit-message-preview',
  title: 'Message editing',
  Component: Preview,
});
