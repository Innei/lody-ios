import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { NativeChat, NativeComposer } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { useSessionSend } from '@/features/sessions/useSessionSend';
import { useSessionControl } from '@/features/sessions/useSessionControl';
import type { Session } from '@/models/catalog';
import type { Snapshot } from '@/features/sessions/useSessionRuntime';
import { Button } from '@/ui/Button';
import { usePalette } from '@/lib/theme/palette';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';

const session: Session = {
  id: 'offline-send-preview',
  machineId: 'fixture',
  projectId: 'fixture:local:project',
  title: '发送交接验收',
  status: 'idle',
  archived: false,
  pinned: false,
  createdAt: '2026-09-07T00:00:00Z',
  cliType: 'builtin',
  agentType: 'fixture',
};
const attachment = {
  id: 'fixture-file',
  name: 'fixture.txt',
  uri: 'file:///tmp/lody-ui-fixture.txt',
  kind: 'file' as const,
};

function advanceQueue(old: Snapshot, messageId?: string): Snapshot {
  const next = old.entries.find(
    (entry) =>
      entry.status === 'queued' && (!messageId || entry.id === messageId),
  );
  const history = old.entries
    .filter((entry) => entry.status !== 'queued')
    .map((entry) => ({ ...entry, finished: true }));
  if (next)
    history.push(
      { ...next, status: 'processing', finished: true },
      {
        id: next.id + ':reply',
        role: 'assistant',
        status: 'processing',
        finished: false,
        rev: 0,
        items: [
          {
            itemId: 'text',
            type: 'text',
            text: 'Working on: ' + next.id,
            rev: 0,
          },
        ],
      },
    );
  return {
    ...old,
    revision: old.revision + 1,
    entries: [
      ...history,
      ...old.entries.filter(
        (entry) => entry.status === 'queued' && entry.id !== next?.id,
      ),
    ],
  };
}

function SendSource() {
  const { finish } = usePageRuntime<undefined, void>();
  const outbox = usePendingSends('ui-send-preview', 'fixture');
  const colors = usePalette();
  return (
    <View
      style={{
        flex: 1,
        justifyContent: 'flex-end',
        backgroundColor: colors.background,
      }}
    >
      <NativeComposer
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          sending: false,
          notice: '',
          reconnect: false,
          placeholder: '交接首条消息',
        })}
        onSend={({ nativeEvent }) => {
          void outbox.put({
            session,
            send: {
              ...nativeEvent,
              phase: 'waiting',
              choice: {},
              creation: '{}',
            },
          });
          finish();
        }}
      />
    </View>
  );
}

function SendPreview() {
  const { params } = usePageRuntime<
    { queue?: boolean; steer?: boolean } | undefined,
    void
  >();
  const queue = params?.queue === true;
  const colors = usePalette();
  const outbox = usePendingSends('ui-send-preview', 'fixture');
  const record = outbox.records.find(
    (entry) => entry.session.id === session.id,
  );
  const [connected, setConnected] = useState(false);
  const [calls, setCalls] = useState(0);
  const [snapshot, setSnapshot] = useState<Snapshot>({
    status: 'offline',
    revision: 0,
    entries: queue
      ? [
          {
            id: 'running-reply',
            role: 'assistant',
            status: 'processing',
            finished: false,
            rev: 0,
            items: [
              {
                itemId: 'text',
                type: 'text',
                text: 'The current reply is still running',
                rev: 0,
              },
            ],
          },
        ]
      : [],
  });
  const completion = useRef<((result: string) => void) | null>(null);
  const controlPending = useRef<{
    args: { action: string; turnId: string; messageId?: string };
    resolve: (result: string) => void;
  } | null>(null);
  const [controlRequest, setControlRequest] = useState('');
  const control = useSessionControl(
    session,
    snapshot,
    false,
    params?.steer !== false,
    (payload) => {
      setControlRequest(payload);
      return new Promise((resolve) => {
        controlPending.current = { args: JSON.parse(payload), resolve };
      });
    },
  );
  const services = useRef({
    createSession: () =>
      new Promise<string>((resolve) => {
        setCalls((n) => n + 1);
        completion.current = resolve;
      }),
    sendSessionTurn: () =>
      new Promise<string>((resolve) => {
        setCalls((n) => n + 1);
        completion.current = resolve;
      }),
  }).current;
  const send = useSessionSend({
    outbox,
    session,
    record,
    snapshot,
    connected,
    serverCreated: false,
    userId: 'ui-send-preview',
    overflow: false,
    services,
  });
  useEffect(
    () => () => {
      completion.current?.(JSON.stringify({ state: 'unknown' }));
      controlPending.current?.resolve(JSON.stringify({ state: 'not_applied' }));
    },
    [],
  );
  const complete = (failure: boolean) => {
    if (controlPending.current) {
      const { args, resolve } = controlPending.current;
      controlPending.current = null;
      if (!failure) setSnapshot((old) => advanceQueue(old, args.messageId));
      resolve(
        JSON.stringify({
          state: failure
            ? 'not_applied'
            : { stop: 'stopped', steer: 'applied' }[args.action],
        }),
      );
      return;
    }
    const resolve = completion.current;
    if (!resolve) return;
    completion.current = null;
    let state = failure ? 'not_sent' : 'accepted';
    if (record?.send.queue && !failure) {
      state = 'queued';
      setSnapshot((old) => ({
        ...old,
        revision: old.revision + 1,
        entries: [
          ...old.entries,
          {
            id: record.send.id,
            role: 'user',
            status: 'queued',
            finished: false,
            rev: 0,
            items: [
              { itemId: 'text', type: 'text', text: record.send.text, rev: 0 },
            ],
          },
        ],
      }));
    }
    if (record?.send.creation) state = failure ? 'rejected' : 'created';
    resolve(JSON.stringify({ state, session, reason: '验收：明确未发送' }));
  };
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View
        style={{
          paddingTop: 108,
          paddingHorizontal: 16,
          flexDirection: 'row',
          gap: 8,
        }}
      >
        <Button
          testID="send-connect"
          onPress={() => {
            setConnected(true);
            setSnapshot((old) => ({ ...old, status: 'live' }));
          }}
        >
          连接
        </Button>
        <Button testID="send-complete" onPress={() => complete(false)}>
          确认
        </Button>
        <Button testID="send-fail" onPress={() => complete(true)}>
          失败
        </Button>
        <Button
          testID="send-reply"
          onPress={() => {
            if (queue) {
              setSnapshot((old) => advanceQueue(old));
              return;
            }
            if (!record) return;
            setSnapshot((old) => ({
              status: 'live',
              revision: old.revision + 1,
              entries: [
                ...old.entries,
                {
                  id: record.send.id,
                  role: 'user',
                  status: '',
                  finished: true,
                  startedAt: record.send.startedAt,
                  rev: 0,
                  items: [
                    {
                      itemId: 'text',
                      type: 'text',
                      rev: 0,
                      text: record.send.text,
                    },
                  ],
                },
                {
                  id: `${record.send.id}:reply`,
                  role: 'assistant',
                  status: '',
                  finished: true,
                  startedAt: Date.now(),
                  rev: 0,
                  items: [],
                },
              ],
            }));
          }}
        >
          回复
        </Button>
      </View>
      <Text
        testID="send-status"
        style={{ color: colors.label, padding: 12 }}
      >{`Calls: ${calls} · ${record?.send.phase ?? 'idle'}`}</Text>
      {queue && (
        <Text
          testID="queue-count"
          style={{ color: colors.label }}
        >{`Queue: ${snapshot.entries.filter((entry) => entry.status === 'queued').length}`}</Text>
      )}
      {queue && (
        <Text
          testID="control-request"
          style={{ color: colors.label }}
          numberOfLines={1}
        >
          {controlRequest}
        </Text>
      )}
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={JSON.stringify(snapshot.entries)}
        pendingSendJSON={send.pendingSendJSON}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: send.canSend,
          sending: send.sending,
          running: control.running || send.awaitingReply,
          canStop: control.canStop,
          stopping: control.stopping,
          controlling: control.controlling,
          steerID: control.steerID,
          steerInterrupts: control.steerInterrupts,
          notice: '',
          reconnect: false,
          placeholder: '断网也可以发送',
        })}
        initialAttachmentsJSON={
          record || queue ? undefined : JSON.stringify([attachment])
        }
        clearDraftToken={send.clearDraftToken}
        restoreDraftToken={send.restoreDraftToken}
        emptyText="离线发送验收"
        onActivityPress={() => {}}
        onStop={control.stop}
        onSteer={({ nativeEvent }) => control.steer(nativeEvent.id)}
        onReconnect={() => {
          setConnected(true);
          setSnapshot((old) => ({ ...old, status: 'live' }));
        }}
        onSend={({ nativeEvent }) =>
          send.submit({ ...nativeEvent, choice: {}, phase: 'waiting' })
        }
      />
    </View>
  );
}

const sourcePage = definePage<undefined, void>({
  id: 'send-source',
  title: '新建会话交接',
  Component: SendSource,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.62, 1],
  },
});
const targetPage = definePage<
  { queue?: boolean; steer?: boolean } | undefined,
  void
>({
  id: 'send-preview',
  parseRouteParams: () => undefined,
  title: '发送交接验收',
  Component: SendPreview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export async function openSendPreview(
  source: boolean,
  queue = false,
  steer = true,
) {
  const { getPendingSendStore } = await import('@/cloud/send/pendingSends');
  await getPendingSendStore('ui-send-preview', 'fixture').remove(session.id);
  if (source) {
    const result = await present(sourcePage);
    if (result.status !== 'completed') return;
  }
  await present(targetPage, { queue, steer });
}
