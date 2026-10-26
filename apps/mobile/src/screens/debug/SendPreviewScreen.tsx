import { NativeComposer } from '@lody-ios/kit';
import { definePage, present } from '@/lib/presentation';
import { usePendingSends } from '@/cloud/send/pendingSends';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import { ComposerSheet } from '@/ui/ComposerSheet';
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

const sourcePage = definePage<{ prepare: () => void }, void>({
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
  title: '发送交接验收',
  native: true,
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
