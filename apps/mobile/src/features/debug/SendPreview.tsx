import { useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { NativeChat, NativeComposer } from '@lody-ios/kit';
import { definePage, present, usePageRuntime } from '@/presentation';
import { usePendingSends } from '@/cloud/pendingSends';
import { useSessionSend } from '@/features/sessions/useSessionSend';
import type { Session } from '@/cloud/model';
import type { Snapshot } from '@/features/sessions/useSessionRuntime';
import { Button } from '@/ui/Button';
import { usePalette } from '@/theme/palette';

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
    entries: [],
  });
  const completion = useRef<((result: string) => void) | null>(null);
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
    },
    [],
  );
  const complete = (failure: boolean) => {
    const resolve = completion.current;
    if (!resolve) return;
    completion.current = null;
    let state = failure ? 'not_sent' : 'accepted';
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
            if (!record) return;
            setSnapshot({
              status: 'live',
              revision: 1,
              entries: [
                {
                  id: record.send.id,
                  role: 'user',
                  status: '',
                  finished: true,
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
                  id: 'fixture-reply',
                  role: 'assistant',
                  status: '',
                  finished: false,
                  rev: 0,
                  items: [
                    {
                      itemId: 'thought',
                      type: 'thought',
                      rev: 0,
                      text: '正在核对内容',
                    },
                  ],
                },
              ],
            });
          }}
        >
          回复
        </Button>
      </View>
      <Text
        testID="send-status"
        style={{ color: colors.label, padding: 12 }}
      >{`Calls: ${calls} · ${record?.send.phase ?? 'idle'}`}</Text>
      <NativeChat
        style={{ flex: 1 }}
        entriesJSON={JSON.stringify(snapshot.entries)}
        pendingSendJSON={send.pendingSendJSON}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: send.canSend,
          sending: send.sending,
          notice: '',
          reconnect: false,
          placeholder: '断网也可以发送',
        })}
        initialAttachmentsJSON={
          record ? undefined : JSON.stringify([attachment])
        }
        clearDraftToken={send.clearDraftToken}
        restoreDraftToken={send.restoreDraftToken}
        emptyText="离线发送验收"
        onActivityPress={() => {}}
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
const targetPage = definePage({
  id: 'send-preview',
  title: '发送交接验收',
  Component: SendPreview,
  presentation: { style: 'push', headerVariant: 'transparent' },
});

export async function openSendPreview(source: boolean) {
  const { getPendingSendStore } = await import('@/cloud/pendingSends');
  await getPendingSendStore('ui-send-preview', 'fixture').remove(session.id);
  if (source) {
    const result = await present(sourcePage);
    if (result.status !== 'completed') return;
  }
  await present(targetPage);
}
