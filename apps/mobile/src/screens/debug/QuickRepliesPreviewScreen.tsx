import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { NativeChat } from '@lody-ios/kit';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { useSessionSend } from '@/features/sessions/useSessionSend';
import {
  defaultQuickReplies,
  useQuickReplies,
} from '@/features/settings/quick-replies';
import { definePage } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import { usePalette } from '@/lib/theme/palette';
import type { Session } from '@/models/catalog';
import type { Snapshot } from '@/models/session';
import { Button } from '@/ui/Button';
import { SettingsScreen } from '../SettingsScreen';

const session: Session = {
  id: 'quick-reply-preview',
  machineId: 'fixture',
  projectId: 'fixture',
  title: 'Quick Replies',
  status: 'idle',
  archived: false,
  pinned: false,
  createdAt: '2026-09-18T00:00:00Z',
  cliType: 'builtin',
  agentType: 'fixture',
};
const history: Snapshot = {
  status: 'live',
  revision: 1,
  entries: [
    {
      id: 'completed-reply',
      role: 'assistant',
      status: 'completed',
      finished: true,
      rev: 0,
      items: [
        {
          itemId: 'text',
          type: 'text',
          text: 'The changes are ready. What would you like to do next?',
          rev: 0,
        },
      ],
    },
  ],
};

function ViewContent() {
  const colors = usePalette();
  const { present } = usePageRuntime();
  const { quickReplies, setQuickReplies } = useQuickReplies();
  const outbox = usePendingSends('quick-reply-preview', 'fixture');
  const record = outbox.records.find((item) => item.session.id === session.id);
  const [snapshot, setSnapshot] = useState(history);
  const [running, setRunning] = useState(false);
  const [revision, setRevision] = useState(0);
  const [calls, setCalls] = useState(0);
  const completion = useRef<((value: string) => void) | null>(null);
  const services = useRef({
    ensureSession: async () => {},
    createSession: async () => JSON.stringify({ state: 'rejected' }),
    sendSessionTurn: () =>
      new Promise<string>((resolve) => {
        setCalls((value) => value + 1);
        completion.current = resolve;
      }),
  }).current;
  const send = useSessionSend({
    outbox,
    session,
    record,
    snapshot,
    connected: true,
    serverCreated: true,
    userId: 'quick-reply-preview',
    overflow: false,
    services,
  });
  useEffect(
    () => () => completion.current?.(JSON.stringify({ state: 'unknown' })),
    [],
  );
  function acknowledge(failed: boolean) {
    completion.current?.(
      JSON.stringify({
        state: failed ? 'not_sent' : 'accepted',
        reason: 'Offline fixture rejected the send.',
      }),
    );
    completion.current = null;
  }
  function finishReply() {
    setRunning(false);
    setSnapshot((current) => ({
      ...current,
      revision: current.revision + 1,
      entries: record
        ? [
            ...current.entries,
            {
              id: record.send.id,
              role: 'user',
              status: 'completed',
              finished: true,
              rev: 0,
              items: [
                {
                  itemId: 'text',
                  type: 'text',
                  text: record.send.text,
                  rev: 0,
                },
              ],
            },
            {
              id: `${record.send.id}:reply`,
              role: 'assistant',
              status: 'completed',
              finished: true,
              rev: 0,
              items: [{ itemId: 'text', type: 'text', text: 'Done.', rev: 0 }],
            },
          ]
        : current.entries,
    }));
  }
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View
        style={{
          paddingTop: 100,
          paddingHorizontal: 16,
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: 6,
        }}
      >
        <Button
          testID="quick-settings"
          onPress={() => void present(SettingsScreen)}
        >
          Settings
        </Button>
        <Button testID="quick-running" onPress={() => setRunning(true)}>
          Work
        </Button>
        <Button testID="quick-ack" onPress={() => acknowledge(false)}>
          Acknowledge
        </Button>
        <Button testID="quick-fail" onPress={() => acknowledge(true)}>
          Reject
        </Button>
        <Button testID="quick-finish" onPress={finishReply}>
          Finish
        </Button>
        <Button
          testID="quick-empty"
          onPress={() => setSnapshot({ ...history, entries: [] })}
        >
          Empty
        </Button>
        <Button
          testID="quick-reset"
          onPress={async () => {
            completion.current?.(JSON.stringify({ state: 'unknown' }));
            completion.current = null;
            await outbox.remove(session.id);
            setQuickReplies(defaultQuickReplies());
            setSnapshot(history);
            setRunning(false);
            setCalls(0);
            setRevision((value) => value + 1);
          }}
        >
          Reset Fixture
        </Button>
      </View>
      <Text
        testID="quick-send-status"
        style={{ color: colors.label, padding: 12 }}
      >{`Calls: ${calls} · ${record?.send.phase ?? 'idle'}`}</Text>
      <NativeChat
        key={revision}
        style={{ flex: 1 }}
        entriesJSON={JSON.stringify(snapshot.entries)}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: send.canSend,
          sending: send.sending,
          running: running || send.awaitingReply,
          notice: '',
          reconnect: false,
          placeholder: 'Message',
          quickReplies: snapshot.entries.length ? quickReplies : [],
        })}
        clearDraftToken={send.clearDraftToken}
        restoreDraftToken={send.restoreDraftToken}
        pendingSendJSON={send.pendingSendJSON}
        emptyText="No conversation yet"
        onSend={({ nativeEvent }) =>
          send.submit({ ...nativeEvent, choice: {}, phase: 'waiting' })
        }
        onRetrySend={send.retry}
        onActivityPress={() => {}}
        onReconnect={() => {}}
      />
    </View>
  );
}

export const QuickRepliesPreviewScreen = definePage({
  id: 'quick-replies-preview',
  title: 'Quick Replies',
  Component: ViewContent,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
