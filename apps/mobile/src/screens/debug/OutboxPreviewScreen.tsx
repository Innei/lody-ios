import { useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { NativeComposer, NativeGroupedList } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { usePageRuntime } from '@/hooks/screens/usePageRuntime';
import {
  getPendingSendStore,
  usePendingSends,
} from '@/cloud/send/pendingSends';
import { useOutboxDispatcher } from '@/cloud/send/outboxDispatcher';
import { pendingSendStatus } from '@/features/sessions/useSessionSend';
import type { PendingSend } from '@/models/send';
import type { Session } from '@/models/catalog';
import { ComposerSheet } from '@/ui/ComposerSheet';
import { Button } from '@/ui/Button';
import { usePalette } from '@/lib/theme/palette';

const user = 'ui-outbox-preview';
const workspace = 'fixture';
const session: Session = {
  id: '',
  title: '后台发送',
  machineId: 'fixture',
  projectId: 'fixture',
  status: 'idle',
  archived: false,
  pinned: false,
  createdAt: '2026-09-15T00:00:00Z',
  cliType: 'builtin',
  agentType: 'fixture',
};

function Composer() {
  const { finish } = usePageRuntime<undefined, PendingSend>();
  return (
    <ComposerSheet sections={[]} onRowPress={() => {}}>
      <NativeComposer
        sendHandoff={false}
        composerJSON={JSON.stringify({
          editable: true,
          canSend: true,
          sending: false,
          notice: '',
          reconnect: false,
          placeholder: '离开输入页后继续发送',
        })}
        onSend={({ nativeEvent }) =>
          finish({ ...nativeEvent, choice: {}, phase: 'waiting' })
        }
      />
    </ComposerSheet>
  );
}
const composer = definePage<undefined, PendingSend>({
  id: 'outbox-composer-preview',
  title: '新建消息',
  Component: Composer,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [0.6],
  },
});

function ViewContent() {
  const colors = usePalette();
  const outbox = usePendingSends(user, workspace);
  const sequence = useRef(0);
  const failNext = useRef(false);
  const reserves = useRef(new Set<string>());
  const requests = useRef(new Map<string, (result: string) => void>());
  const [calls, setCalls] = useState(0);
  const [, refresh] = useState(0);
  const services = useRef({
    async createSession(payload: string) {
      return JSON.stringify({ state: 'created', session: JSON.parse(payload) });
    },
    async ensureSession(id: string) {
      reserves.current.add(id);
      refresh((n) => n + 1);
      if (failNext.current) {
        failNext.current = false;
        throw new Error('runtime_replaced');
      }
    },
    async releaseReserve(id: string) {
      reserves.current.delete(id);
      refresh((n) => n + 1);
    },
    sendSessionTurn(payload: string) {
      const args = JSON.parse(payload);
      setCalls((n) => n + 1);
      return new Promise<string>((resolve) =>
        requests.current.set(args.sessionId, resolve),
      );
    },
  }).current;
  useOutboxDispatcher({
    outbox,
    userId: user,
    connected: true,
    serverSessions: [],
    foregroundSessionId: '',
    services,
  });

  async function add(send: PendingSend, create = false) {
    const n = ++sequence.current;
    const target = { ...session, id: `outbox-${n}`, title: `消息 ${n}` };
    await outbox.put({
      session: target,
      send: { ...send, creation: create ? JSON.stringify(target) : undefined },
    });
  }
  function confirm(all: boolean) {
    for (const [id, resolve] of requests.current) {
      requests.current.delete(id);
      resolve(JSON.stringify({ state: 'accepted' }));
      if (!all) break;
    }
  }
  return (
    <View
      style={{ flex: 1, paddingTop: 110, backgroundColor: colors.background }}
    >
      <View
        style={{
          flexDirection: 'row',
          flexWrap: 'wrap',
          gap: 8,
          paddingHorizontal: 16,
        }}
      >
        <Button
          testID="outbox-compose"
          onPress={async () => {
            const result = await present(composer, undefined);
            if (result.status === 'completed') await add(result.value, true);
          }}
        >
          新建消息
        </Button>
        <Button
          testID="outbox-fail-next"
          onPress={() => {
            failNext.current = true;
          }}
        >
          下次同步失败
        </Button>
        <Button testID="outbox-confirm" onPress={() => confirm(false)}>
          确认一条
        </Button>
        <Button testID="outbox-confirm-all" onPress={() => confirm(true)}>
          确认全部
        </Button>
        <Button
          testID="outbox-nine"
          onPress={async () => {
            for (let n = 0; n < 9; n++)
              await add({
                id: `00000000-0000-4000-8000-${String(sequence.current + 1).padStart(12, '0')}`,
                text: `后台消息 ${n + 1}`,
                startedAt: Date.now(),
                attachments: [],
                choice: {},
                phase: 'waiting',
              });
          }}
        >
          添加九条
        </Button>
      </View>
      <Text testID="outbox-state" style={{ color: colors.label, padding: 16 }}>
        {JSON.stringify({
          calls,
          reserves: reserves.current.size,
          waiting: outbox.records.filter(
            (record) => record.send.phase === 'waiting',
          ).length,
          sending: outbox.records.filter(
            (record) => record.send.phase === 'sending',
          ).length,
          failed: outbox.records.filter(
            (record) => record.send.phase === 'failed',
          ).length,
          accepted: outbox.records.filter(
            (record) => record.send.phase === 'accepted',
          ).length,
        })}
      </Text>
      <NativeGroupedList
        style={{ flex: 1 }}
        accent={colors.accent}
        placeholder=""
        sections={[
          {
            id: 'outbox',
            rows: outbox.records.map((record) => ({
              id: record.session.id,
              title: record.send.text,
              value: pendingSendStatus(record.send, true),
              action: record.send.phase === 'failed',
            })),
          },
        ]}
        onRowPress={({ nativeEvent }) => {
          const record = outbox.records.find(
            (item) => item.session.id === nativeEvent.id,
          );
          if (record?.send.phase === 'failed')
            void outbox.put({
              ...record,
              send: { ...record.send, phase: 'waiting' },
            });
        }}
      />
    </View>
  );
}

const page = definePage({
  id: 'outbox-preview',
  title: '后台发件箱验收',
  Component: ViewContent,
  presentation: {
    style: 'formSheet',
    headerVariant: 'transparent',
    sheetAllowedDetents: [1],
  },
});
export async function openOutboxPreview() {
  const store = getPendingSendStore(user, workspace);
  if (!store.getSnapshot().ready)
    await new Promise<void>((resolve) => {
      const unsubscribe = store.subscribe(() => {
        if (!store.getSnapshot().ready) return;
        unsubscribe();
        resolve();
      });
    });
  for (const record of store.getSnapshot().records)
    await store.remove(record.session.id);
  await present(page, undefined);
}
