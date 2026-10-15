import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  NativeChat,
  NativeComposer,
  type AttachmentUploadProgress,
} from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { usePendingSends } from '@/cloud/send/pendingSends';
import { useSessionSend } from '@/features/sessions/useSessionSend';
import { useSessionControl } from '@/features/sessions/useSessionControl';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import type { Snapshot } from '@/features/sessions/useSessionRuntime';
import { Button } from '@/ui/Button';
import { ComposerSheet } from '@/ui/ComposerSheet';
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
const fixtureControl = { minWidth: 44 };
const attachment = {
  id: 'fixture-file',
  name: 'fixture.txt',
  uri: 'file:///tmp/lody-ui-fixture.txt',
  kind: 'file' as const,
};
const scrollContext: Snapshot['entries'] = [
  [
    'Help me redesign the project browser. Start with the navigation and explain the tradeoffs.',
    'The project browser should keep the current workspace visible while the project list changes. A project row opens its session list with the native back gesture, so returning restores the same scroll position. Search belongs above the list and should keep its query when a session is opened.\n\nEach project needs a readable name, a short repository path, and a clear connection state. The row should remain useful when the computer is offline: cached sessions can still open, while actions that require the computer explain what is missing. Avoid replacing the entire page with a connection error.\n\nFor the first pass, keep the hierarchy shallow. Workspace selection changes the catalog; opening a project changes only the native stack. This makes the ownership of selection and navigation easier to follow.',
  ],
  [
    'What should happen when the catalog refreshes while I am reading the middle of the list?',
    'Keep the visible project anchored by identity rather than by its numeric index. New projects may appear before it, but they should not move the text the user is reading. A refresh indicator can appear in the navigation area without inserting a large row above the content.\n\nSelection should survive a snapshot update. If the selected project is removed, finish the current navigation transition before changing the selection. An interactive back gesture that is cancelled must restore the row highlight, because the destination still owns the screen.\n\nA failed refresh should leave the cached rows in place and offer an explicit retry. Show when those rows were last updated. An empty response is different from a failed request: only a confirmed successful response should replace the list with the empty state.',
  ],
  [
    'Now cover message drafts, attachments, and what the user sees during a failed send.',
    'Treat the draft text and its attachments as one unit. The local message should appear immediately with a stable identity, and the authoritative history should take over that same message after delivery. Clearing the input must not delete the only copy of a draft that is still being prepared.\n\nBefore a durable write, a definite failure can offer an explicit retry with the original text and files. After an uncertain acknowledgement, keep the message visible and explain that delivery is unconfirmed. Do not replay the write automatically, because the computer may already have accepted it.\n\nThe conversation should remain readable through each transition. An ordinary new turn can reserve room for its reply. Guidance added to the reply already in progress should stay beside that context, without opening a new empty viewport beneath it.',
  ],
].flatMap(([user, reply], index) => [
  {
    id: `send-context-${index}-user`,
    rev: 0,
    role: 'user',
    status: 'handled',
    finished: true,
    items: [{ itemId: 'text', rev: 0, type: 'text', text: user }],
  },
  {
    id: `send-context-${index}-reply`,
    rev: 0,
    role: 'assistant',
    status: 'completed',
    finished: true,
    items: [{ itemId: 'text', rev: 0, type: 'text', text: reply }],
  },
]);
const scrollReply =
  'I am checking the message list against the project-browser plan. The earlier decisions still apply: preserve the reading position, retain the local message identity, and make delivery failures visible without discarding the draft.\n\nThe first check is an ordinary new turn. Its message moves to the top of the transcript, leaving room for the answer. With several screens of history above it, that movement should be easy to distinguish from simply appending a row at the bottom.\n\nThe second check is guidance during this reply. The existing paragraphs should remain directly above the new message. The list may advance enough to reveal the message, but it should not push that message to the top or reserve another screen of empty space.\n\nCurrent checkpoint: keep this paragraph visible immediately above the next message. I am still reviewing the remaining interaction details.';

function advanceQueue(old: Snapshot, messageId?: string): Snapshot {
  const next = old.entries.find((entry) =>
    messageId ? entry.id === messageId : entry.status === 'queued',
  );
  const history = old.entries
    .filter((entry) => entry.status !== 'queued' && entry.id !== next?.id)
    .map((entry) => ({ ...entry, finished: true }));
  if (next)
    history.push(
      { ...next, status: 'processing', delivery: 'accepted', finished: true },
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
  const { params, finish } = usePageRuntime<{ prepare: () => void }, void>();
  const outbox = usePendingSends('ui-send-preview', 'fixture');
  return (
    <ComposerSheet
      onRowPress={() => {}}
      sections={[
        {
          id: 'machine',
          rows: [
            {
              id: 'machine',
              title: 'Offline machine',
              image: 'desktopcomputer',
            },
          ],
        },
        {
          id: 'agent',
          rows: [{ id: 'agent', title: 'Offline agent', image: 'sparkles' }],
        },
      ]}
    >
      <NativeComposer
        composerRelay
        onRelayReady={() => finish()}
        scrollEdge
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
          params.prepare();
        }}
      />
    </ComposerSheet>
  );
}

function SendPreview() {
  const { params } = usePageRuntime<
    | {
        queue?: boolean;
        steer?: boolean;
        queuedMessageBehavior?: 'queue' | 'guide';
        longContext?: boolean;
      }
    | undefined,
    void
  >();
  const queue = params?.queue === true;
  const longContext = params?.longContext === true;
  const replyText = longContext
    ? scrollReply
    : 'The current reply is still running';
  const previewSession = {
    ...session,
    status: queue ? 'running' : session.status,
  };
  const colors = usePalette();
  const insets = useSafeAreaInsets();
  const outbox = usePendingSends('ui-send-preview', 'fixture');
  const record = outbox.records.find(
    (entry) => entry.session.id === session.id,
  );
  const [initialAttachmentsJSON] = useState(() =>
    record || queue || longContext ? undefined : JSON.stringify([attachment]),
  );
  const [connected, setConnected] = useState(false);
  const [calls, setCalls] = useState(0);
  const [snapshot, setSnapshot] = useState<Snapshot>(() => ({
    status: 'offline',
    revision: 0,
    entries: [
      ...(longContext ? scrollContext : []),
      ...(longContext
        ? [
            {
              id: 'send-context-current-user',
              rev: 0,
              role: 'user',
              status: 'handled',
              finished: true,
              items: [
                {
                  itemId: 'text',
                  type: 'text',
                  text: 'Review the remaining send interactions before we implement the plan.',
                  rev: 0,
                },
              ],
            },
          ]
        : []),
      ...(queue || longContext
        ? [
            {
              id: 'running-reply',
              role: 'assistant',
              status: 'processing',
              finished: !queue,
              rev: 0,
              items: [
                {
                  itemId: 'text',
                  type: 'text',
                  text: replyText,
                  rev: 0,
                },
              ],
            },
          ]
        : []),
    ],
  }));
  const completion = useRef<((result: string) => void) | null>(null);
  const submitted = useRef<{ id: string; guide?: boolean } | null>(null);
  const guideReceipts = useRef<string[]>([]);
  const uploadListener = useRef<
    ((event: AttachmentUploadProgress) => void) | null
  >(null);
  const uploadStep = useRef(0);
  const controlPending = useRef<{
    args: { action: string; turnId: string; messageId?: string };
    resolve: (result: string) => void;
  } | null>(null);
  const [controlRequest, setControlRequest] = useState('');
  const [contextChip, setContextChip] = useState(false);
  const control = useSessionControl(
    session,
    snapshot,
    false,
    params?.steer !== false,
    (payload) => {
      setControlRequest(payload);
      const args = JSON.parse(payload);
      if (args.action === 'steer')
        setSnapshot((old) => ({
          ...old,
          revision: old.revision + 1,
          entries: old.entries.map((entry) =>
            entry.id === args.messageId
              ? { ...entry, status: 'pending_apply', delivery: 'confirming' }
              : entry,
          ),
        }));
      return new Promise((resolve) => {
        controlPending.current = { args, resolve };
      });
    },
  );
  const services = useRef({
    ensureSession: async () => {},
    addAttachmentUploadProgressListener: (
      listener: (event: AttachmentUploadProgress) => void,
    ) => {
      uploadListener.current = listener;
      uploadStep.current = 0;
      return {
        remove: () => {
          if (uploadListener.current === listener)
            uploadListener.current = null;
        },
      };
    },
    createSession: () =>
      new Promise<string>((resolve) => {
        setCalls((n) => n + 1);
        completion.current = resolve;
      }),
    sendSessionTurn: (payload: string) =>
      new Promise<string>((resolve) => {
        submitted.current = JSON.parse(payload);
        setCalls((n) => n + 1);
        completion.current = resolve;
      }),
  }).current;
  const send = useSessionSend({
    outbox,
    session: previewSession,
    record,
    snapshot,
    connected,
    serverCreated: false,
    userId: 'ui-send-preview',
    overflow: false,
    queuedMessageBehavior: params?.queuedMessageBehavior ?? 'queue',
    steerable: params?.steer !== false,
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
      if (!failure) controlPending.current = null;
      if (failure && args.action === 'steer')
        setSnapshot((old) => ({
          ...old,
          revision: old.revision + 1,
          entries: old.entries.map((entry) =>
            entry.id === args.messageId
              ? { ...entry, delivery: 'unknown' }
              : entry,
          ),
        }));
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
    // Durable writes and per-message RPC receipts settle independently.
    if (!completion.current && guideReceipts.current.length) {
      const id = guideReceipts.current.shift()!;
      setSnapshot((old) => ({
        ...old,
        revision: old.revision + 1,
        entries: old.entries.map((entry) =>
          entry.id === id
            ? {
                ...entry,
                status: failure ? 'pending_apply' : 'processing',
                delivery: failure ? 'unknown' : 'accepted',
              }
            : entry,
        ),
      }));
      return;
    }
    const resolve = completion.current;
    if (!resolve) return;
    if (submitted.current?.guide && record) {
      const target = snapshot.entries.findLast(
        (entry) => entry.role === 'assistant' && !entry.finished,
      );
      completion.current = null;
      if (!failure && target) {
        const id = record.send.id;
        guideReceipts.current.push(id);
        setControlRequest(
          JSON.stringify({ action: 'steer', turnId: target.id, messageId: id }),
        );
        setSnapshot((old) => ({
          ...old,
          revision: old.revision + 1,
          entries: [
            ...old.entries,
            {
              id,
              role: 'user',
              status: 'pending_apply',
              delivery: 'confirming',
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
          ],
        }));
        resolve(JSON.stringify({ state: 'uploaded', awaitingGuide: true }));
        return;
      }
      if (!failure) {
        setControlRequest(
          JSON.stringify({ action: 'dispatch', messageId: record.send.id }),
        );
        setSnapshot((old) => ({
          ...old,
          revision: old.revision + 1,
          entries: [
            ...old.entries,
            {
              id: record.send.id,
              role: 'user',
              status: 'pending',
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
          ],
        }));
      }
      resolve(
        JSON.stringify({
          state: failure ? 'not_sent' : 'accepted',
          reason: failure ? 'free_session_turn_limit_reached' : undefined,
        }),
      );
      return;
    }
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
    resolve(
      JSON.stringify({
        state,
        session,
        reason: failure ? 'free_session_turn_limit_reached' : undefined,
      }),
    );
  };
  const reply = (finished: boolean) => {
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
            ...record.send.attachments.map((attachment, index) => ({
              itemId: `attachment-${index}`,
              type: attachment.kind,
              rev: 0,
              [attachment.kind]: {
                id: `server-${attachment.id}`,
                fileName: attachment.name,
                width: 800,
                height: 600,
              },
            })),
          ],
        },
        {
          id: `${record.send.id}:reply`,
          role: 'assistant',
          userTurnId: record.send.id,
          status: '',
          finished,
          startedAt: Date.now(),
          rev: 0,
          items: [],
        },
      ].filter(
        (entry) =>
          record.send.phase !== 'unknown' || entry.id !== record.send.id,
      ),
    }));
  };
  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <View
        style={{
          // The transparent navigation bar's hit region extends past its title.
          // Keep these controls clear of it so a physical tap reaches the button.
          paddingTop: Math.max(insets.top + 72, 140),
          paddingHorizontal: 16,
          flexDirection: 'row',
          gap: 6,
        }}
      >
        <Button
          testID="send-connect"
          style={fixtureControl}
          onPress={() => {
            setConnected(true);
            setSnapshot((old) => ({ ...old, status: 'live' }));
          }}
        >
          连接
        </Button>
        <Button
          testID="send-complete"
          style={fixtureControl}
          onPress={() => complete(false)}
        >
          确认
        </Button>
        <Button
          testID="send-fail"
          style={fixtureControl}
          onPress={() => complete(true)}
        >
          失败
        </Button>
        <Button
          testID="send-start-reply"
          style={fixtureControl}
          onPress={() => reply(false)}
        >
          开始回复
        </Button>
        <Button
          testID="send-reply"
          style={fixtureControl}
          onPress={() => reply(true)}
        >
          回复
        </Button>
        {queue && (
          <Button
            testID="send-toggle-context"
            style={fixtureControl}
            onPress={() => setContextChip((value) => !value)}
          >
            上下文
          </Button>
        )}
        {!queue && (
          <Button
            testID="send-toggle-pending"
            style={fixtureControl}
            onPress={() =>
              record
                ? void outbox.remove(session.id)
                : void outbox.put({
                    session,
                    send: {
                      id: 'stale-pending',
                      text: '已完成的残留消息',
                      startedAt: Date.now(),
                      attachments: [],
                      choice: {},
                      phase: 'unknown',
                    },
                  })
            }
          >
            残留
          </Button>
        )}
        <Button
          testID="send-upload-progress"
          style={fixtureControl}
          onPress={() => {
            if (record?.send.phase !== 'sending') return;
            const step = uploadStep.current++ % 4;
            const phase = ['uploading', 'uploading', 'verifying', 'complete'][
              step
            ] as AttachmentUploadProgress['phase'];
            record.send.attachments.forEach((attachment, index) => {
              const percent = step < 2 ? 25 + step * 40 + index : 100;
              uploadListener.current?.({
                sessionId: session.id,
                sendId: record.send.id,
                attachmentId: attachment.id,
                phase: step === 2 && index === 0 ? 'complete' : phase,
                percent,
              });
            });
          }}
        >
          上传
        </Button>
      </View>
      {params?.queuedMessageBehavior === 'guide' && (
        <Button
          testID="send-reset-guide"
          onPress={async () => {
            await outbox.remove(session.id);
            setControlRequest('');
            setSnapshot((old) => ({
              ...old,
              revision: old.revision + 1,
              entries: old.entries
                .filter((entry) => entry.id === 'running-reply')
                .map((entry) => ({ ...entry, finished: false })),
            }));
          }}
        >
          重置引导场景
        </Button>
      )}
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
          preview: contextChip
            ? {
                label: 'localhost:5173',
                accessibilityLabel: 'localhost:5173',
                symbol: 'safari',
                state: 'ready',
              }
            : undefined,
          editable: true,
          canSend: send.canSend,
          sending: send.sending,
          running: control.running || send.awaitingReply,
          canStop: control.canStop,
          stopping: control.stopping,
          controlling: control.controlling,
          steerID: control.steerID,
          steerInterrupts: control.steerInterrupts,
          queuedMessageBehavior: params?.queuedMessageBehavior ?? 'queue',
          notice: '',
          reconnect: false,
          placeholder: '断网也可以发送',
        })}
        initialAttachmentsJSON={initialAttachmentsJSON}
        clearDraftToken={send.clearDraftToken}
        restoreDraftToken={send.restoreDraftToken}
        emptyText="离线发送验收"
        onActivityPress={() => {}}
        onStop={control.stop}
        onSteer={({ nativeEvent }) => control.steer(nativeEvent.id)}
        onRetrySend={send.retry}
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

const sourcePage = definePage<{ prepare: () => void }, void>({
  id: 'send-source',
  title: '新建会话交接',
  Component: SendSource,
  parseRouteParams: () => {
    throw new Error('Open from Debug');
  },
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.62, 1],
  },
});
const targetPage = definePage<
  | {
      queue?: boolean;
      steer?: boolean;
      queuedMessageBehavior?: 'queue' | 'guide';
      longContext?: boolean;
    }
  | undefined,
  void
>({
  id: 'send-preview',
  parseRouteParams: () => undefined,
  title: '发送交接验收',
  Component: SendPreview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export async function openSendPreview(
  source: boolean | 'delayed',
  queue = false,
  steer = true,
  queuedMessageBehavior: 'queue' | 'guide' = 'queue',
  longContext = false,
) {
  const { getPendingSendStore } = await import('@/cloud/send/pendingSends');
  await getPendingSendStore('ui-send-preview', 'fixture').remove(session.id);
  if (source) {
    let destination: Promise<unknown> | undefined;
    const result = await present(sourcePage, {
      prepare: () => {
        destination = (async () => {
          if (source === 'delayed')
            await new Promise((resolve) => setTimeout(resolve, 1200));
          return present(
            targetPage,
            { queue, steer, queuedMessageBehavior, longContext },
            { animationType: 'none' },
          );
        })();
      },
    });
    if (result.status !== 'completed') return;
    await destination;
    return;
  }
  await present(targetPage, {
    queue,
    steer,
    queuedMessageBehavior,
    longContext,
  });
}
