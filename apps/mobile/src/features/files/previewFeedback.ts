import type { Session } from '@lody/cloud-runtime/models/catalog';
import type { PendingSession } from '../../models/send.ts';

export type PreviewFeedbackResult = 'sent' | 'queued' | 'unknown';
type Store = {
  getSnapshot: () => { ready: boolean; records: readonly PendingSession[] };
  put: (record: PendingSession) => Promise<unknown>;
  subscribe: (listener: () => void) => () => void;
};

export async function sendPreviewFeedback({
  store,
  session,
  text,
  id,
  connected,
  timeoutMs = 15000,
}: {
  store: Store;
  session: Session;
  text: string;
  id: string;
  connected: boolean;
  timeoutMs?: number;
}): Promise<PreviewFeedbackResult> {
  const snapshot = store.getSnapshot();
  if (!snapshot.ready || session.archived) throw new Error('unavailable');
  if (snapshot.records.some((item) => item.session.id === session.id))
    throw new Error('pending_send');
  await store.put({
    session,
    send: {
      id,
      text,
      startedAt: Date.now(),
      attachments: [],
      choice: {},
      preserveDraft: true,
      phase: 'waiting',
    },
  });
  if (!connected) return 'queued';
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => finish('unknown'), timeoutMs);
    let unsubscribe = () => {};
    function finish(result: PreviewFeedbackResult, reason?: string) {
      clearTimeout(timer);
      unsubscribe();
      if (reason) reject(new Error(reason));
      else resolve(result);
    }
    function check() {
      const record = store
        .getSnapshot()
        .records.find((item) => item.send.id === id);
      if (!record) {
        finish('unknown');
        return;
      }
      const { phase, reason } = record.send;
      if (phase === 'accepted') finish('sent');
      if (phase === 'queued') finish('queued');
      if (phase === 'unknown') finish('unknown');
      if (phase === 'failed') finish('unknown', reason ?? 'send_failed');
    }
    unsubscribe = store.subscribe(check);
    check();
  });
}
