import { useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { NativeChat } from '@lody-ios/kit';
import type {
  EntrySummary,
  Snapshot,
} from '@lody/cloud-runtime/models/session';
import type {
  QueueRequest,
  QueueResult,
} from '@lody/cloud-runtime/models/queue';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import { definePage, present } from '@/lib/presentation';
import { usePalette } from '@/lib/theme/palette';
import { useSessionQueue } from '@/features/sessions/useSessionQueue';
import { useSessionSend } from '@/features/sessions/useSessionSend';
import {
  getPendingSendStore,
  usePendingSends,
} from '@/cloud/send/pendingSends';
import { writeLocal } from '@/cloud/kv';
import { Button } from '@/ui/Button';

const userId = 'ui-queue-tools';
const workspaceId = 'fixture';
const session: Session = {
  id: 'queue-tools-preview',
  machineId: 'fixture',
  projectId: 'fixture:local:project',
  title: 'Queue tools',
  status: 'running',
  archived: false,
  pinned: false,
  createdAt: '2026-10-12T00:00:00Z',
  cliType: 'builtin',
  agentType: 'fixture',
};
const initialEntries: EntrySummary[] = [
  {
    id: 'running',
    role: 'assistant',
    status: 'processing',
    finished: false,
    rev: 0,
    items: [
      {
        itemId: 'text',
        type: 'text',
        text: 'Current reply continues while queued messages change.',
        rev: 0,
      },
    ],
  },
  {
    id: 'queue-alpha',
    role: 'user',
    status: 'queued',
    finished: false,
    rev: 0,
    items: [
      { itemId: 'text', type: 'text', text: 'Alpha message', rev: 0 },
      {
        itemId: 'file',
        type: 'file',
        file: { id: 'file', fileName: 'notes.txt', sizeBytes: 12 },
        rev: 0,
      },
    ],
  },
  {
    id: 'queue-beta',
    role: 'user',
    status: 'queued',
    finished: false,
    rev: 0,
    items: [{ itemId: 'text', type: 'text', text: 'Beta message', rev: 0 }],
  },
];

function SendQueueToolsPreviewScreen() {
  const colors = usePalette();
  const insets = useSafeAreaInsets();
  const [snapshot, setSnapshot] = useState<Snapshot>({
    status: 'live',
    revision: 1,
    entries: initialEntries,
  });
  const snapshotRef = useRef(snapshot);
  snapshotRef.current = snapshot;
  const outbox = usePendingSends(userId, workspaceId);
  const record = outbox.records.find((item) => item.session.id === session.id);
  const [calls, setCalls] = useState(0);
  const [checks, setChecks] = useState(0);
  const [steers, setSteers] = useState(0);
  const [failure, setFailure] = useState(false);
  const failNext = useRef(false);
  const holdNext = useRef(false);
  const confirmation = useRef(false);
  const attempt = useRef(0);
  const pending = useRef<{
    args: QueueRequest;
    resolve: (result: string) => void;
  } | null>(null);
  const pendingSend = useRef<((result: string) => void) | null>(null);
  const [requestLabel, setRequestLabel] = useState('');
  function apply(args: QueueRequest): QueueResult {
    const current = snapshotRef.current;
    const found = current.entries.find((entry) => entry.id === args.id);
    if (args.action === 'check') {
      if (found && found.status !== 'queued')
        return { state: 'rejected', reason: 'queue_item_started' };
      return {
        state: 'unknown',
        receipt: args.receipt,
        reason: 'queue_execution_unconfirmed',
      };
    }
    if (!found || found.status !== 'queued')
      return { state: 'rejected', reason: 'queue_item_started' };
    if (failNext.current && args.action === 'save-edit') {
      failNext.current = false;
      setFailure(false);
      return { state: 'rejected', reason: 'queue_write_failed' };
    }
    const revision = (current.revision ?? 0) + 1;
    if (args.action === 'begin-edit') {
      const lease = Date.now();
      setSnapshot({
        ...current,
        revision,
        entries: current.entries.map((entry) =>
          entry.id === args.id
            ? { ...entry, queueEditing: true, queueEditingStartedAt: lease }
            : entry,
        ),
      });
      return {
        state: 'applied',
        editingStartedAt: lease,
        text: found.items
          .flatMap((item) =>
            item.type === 'text' && 'text' in item ? [String(item.text)] : [],
          )
          .join('\n'),
      };
    }
    if (args.action === 'save-edit' || args.action === 'cancel-edit') {
      setSnapshot({
        ...current,
        revision,
        entries: current.entries.map((entry) => {
          if (entry.id !== args.id) return entry;
          const items =
            args.action === 'save-edit'
              ? [
                  {
                    itemId: 'text',
                    type: 'text',
                    text: args.text ?? '',
                    rev: revision,
                  },
                  ...entry.items.filter((item) => item.type !== 'text'),
                ]
              : entry.items;
          return {
            ...entry,
            items,
            queueEditing: false,
            queueEditingStartedAt: undefined,
          };
        }),
      });
      return { state: 'applied' };
    }
    if (args.action === 'delete') {
      setSnapshot({
        ...current,
        revision,
        entries: current.entries.filter((entry) => entry.id !== args.id),
      });
      return {
        state: 'unknown',
        receipt: { id: args.id, action: 'delete' },
        reason: 'queue_execution_unconfirmed',
      };
    }
    const entries = [...current.entries];
    const index = entries.findIndex((entry) => entry.id === args.id);
    const target = index + (args.action === 'move-up' ? -1 : 1);
    if (
      target >= 0 &&
      target < entries.length &&
      entries[target]?.status === 'queued'
    )
      [entries[index], entries[target]] = [entries[target]!, entries[index]!];
    setSnapshot({ ...current, revision, entries });
    return { state: 'applied' };
  }
  const queueRequest = useRef((payload: string) => {
    const args = JSON.parse(payload) as QueueRequest;
    setRequestLabel(`${args.action}:${args.id}`);
    if (holdNext.current) {
      holdNext.current = false;
      return new Promise<string>((resolve) => {
        pending.current = { args, resolve };
      });
    }
    return Promise.resolve(JSON.stringify(apply(args)));
  }).current;
  const services = useRef({
    ensureSession: async () => {},
    createSession: async () => JSON.stringify({ state: 'rejected' }),
    sendSessionTurn: () =>
      new Promise<string>((resolve) => {
        setCalls((count) => count + 1);
        pendingSend.current = resolve;
      }),
    checkSessionSend: async () => {
      setChecks((count) => count + 1);
      return JSON.stringify({
        state: confirmation.current ? 'accepted' : 'unknown',
      });
    },
    cancelSessionSend: async () => {
      const resolve = pendingSend.current;
      if (!resolve) return JSON.stringify({ state: 'unknown' });
      pendingSend.current = null;
      resolve(JSON.stringify({ state: 'not_sent', reason: 'send_cancelled' }));
      return JSON.stringify({ state: 'cancelled' });
    },
  }).current;
  const send = useSessionSend({
    outbox,
    session,
    record,
    snapshot,
    connected: true,
    serverCreated: true,
    userId,
    overflow: false,
    services,
  });
  const queue = useSessionQueue({
    snapshot,
    sessionId: session.id,
    workspaceId,
    userId,
    editable: true,
    request: queueRequest,
  });
  const seedSend = (uncertain: boolean) => {
    confirmation.current = false;
    void outbox.put({
      session,
      send: {
        id: `11111111-1111-4111-8111-${String(++attempt.current).padStart(12, '0')}`,
        text: uncertain ? 'Uncertain message' : 'Uploading message',
        startedAt: Date.now(),
        attachments: [],
        choice: {},
        phase: uncertain ? 'unknown' : 'waiting',
      },
    });
  };
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View
        style={{
          paddingTop: insets.top + 64,
          paddingHorizontal: 12,
          flexDirection: 'row',
          gap: 4,
          display: queue.queueState.editingId ? 'none' : 'flex',
        }}
      >
        <Button
          testID="queue-tools-fail"
          onPress={() => {
            failNext.current = true;
            setFailure(true);
          }}
        >
          Fail
        </Button>
        <Button
          testID="queue-tools-hold"
          onPress={() => {
            holdNext.current = true;
          }}
        >
          Hold
        </Button>
        <Button
          testID="queue-tools-complete"
          onPress={() => {
            const item = pending.current;
            if (!item) return;
            pending.current = null;
            item.resolve(JSON.stringify(apply(item.args)));
          }}
        >
          Complete
        </Button>
        <Button
          testID="queue-tools-claim"
          onPress={() => {
            if (record?.send.phase === 'unknown') {
              confirmation.current = true;
              return;
            }
            const id = 'queue-beta';
            setSnapshot((old) => ({
              ...old,
              revision: (old.revision ?? 0) + 1,
              entries: [
                ...old.entries.filter((entry) => entry.id !== id),
                {
                  ...initialEntries[2]!,
                  id,
                  status: 'processing',
                  finished: true,
                },
              ],
            }));
          }}
        >
          Claim
        </Button>
        <Button testID="queue-tools-unknown" onPress={() => seedSend(true)}>
          Unknown
        </Button>
        <Button testID="queue-tools-prepare" onPress={() => seedSend(false)}>
          Prepare
        </Button>
      </View>
      <Text
        testID="queue-tools-status"
        numberOfLines={1}
        style={{
          color: colors.label,
          paddingHorizontal: 12,
          paddingTop: queue.queueState.editingId ? insets.top + 64 : 0,
          fontSize: 12,
        }}
      >{`Calls: ${calls} · Checks: ${checks} · Steers: ${steers} · Send: ${record?.send.phase ?? 'idle'} · Fail: ${failure} · Last: ${requestLabel}`}</Text>
      <Text
        testID="queue-tools-order"
        style={{
          color: colors.label,
          paddingHorizontal: 12,
          height: queue.queueState.editingId ? 0 : undefined,
        }}
      >
        {snapshot.entries
          .filter((entry) => entry.status === 'queued')
          .map((entry) => entry.id)
          .join(',')}
      </Text>
      <Text
        testID="queue-tools-request"
        style={{
          color: colors.secondaryLabel,
          paddingHorizontal: 12,
          height: queue.queueState.editingId ? 0 : undefined,
        }}
      >
        {requestLabel}
      </Text>
      <NativeChat
        style={{ flex: 1 }}
        emptyText="Queue tools"
        onActivityPress={() => {}}
        onReconnect={() => {}}
        entriesJSON={JSON.stringify(queue.entries)}
        pendingSendJSON={send.pendingSendJSON}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: send.canSend,
          sending: send.sending,
          running: true,
          canStop: true,
          queueState: queue.queueState,
          sendRecovery: send.sendRecovery,
          recovering: send.recovering,
          notice: '',
          reconnect: false,
          placeholder: 'Independent draft',
        })}
        clearDraftToken={send.clearDraftToken}
        restoreDraftToken={send.restoreDraftToken}
        onQueueAction={({ nativeEvent }) => void queue.act(nativeEvent)}
        onRecoverSend={({ nativeEvent }) =>
          void send.recover(nativeEvent.action)
        }
        onSteer={({ nativeEvent }) => {
          setSteers((count) => count + 1);
          setSnapshot((old) => ({
            ...old,
            revision: (old.revision ?? 0) + 1,
            entries: old.entries.map((entry) =>
              entry.id === nativeEvent.id
                ? { ...entry, status: 'processing', finished: true }
                : entry,
            ),
          }));
        }}
        onSend={({ nativeEvent }) =>
          send.submit({ ...nativeEvent, choice: {}, phase: 'waiting' })
        }
      />
    </View>
  );
}

const page = definePage<void, void>({
  id: 'send-queue-tools',
  title: 'Queue tools',
  Component: SendQueueToolsPreviewScreen,
  parseRouteParams: () => undefined,
  presentation: { style: 'push', headerVariant: 'transparent' },
});
export async function openSendQueueToolsPreview() {
  await getPendingSendStore(userId, workspaceId).remove(session.id);
  await writeLocal(`queue-controls:${userId}:${workspaceId}:${session.id}`, []);
  await present(page, undefined);
}
