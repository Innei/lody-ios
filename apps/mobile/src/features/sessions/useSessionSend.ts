import { useEffect, useRef, useState } from 'react';
import { Alert } from 'react-native';
import { createSession, sendSessionTurn } from '@lody-ios/kit';
import type {
  PendingSend,
  PendingSession,
  usePendingSends,
} from '@/cloud/send/pendingSends';
import type { Session } from '@/models/catalog';
import type { Snapshot } from './useSessionRuntime';
import { t } from '../../i18n/index.ts';

export function pendingSendStatus(send: PendingSend, live: boolean) {
  if (send.phase === 'unknown') return t('send.status.unknown');
  if (send.phase === 'creating') return t('send.status.creating');
  if (send.phase === 'sending')
    return t(
      send.attachments.length ? 'send.status.uploading' : 'send.status.sending',
    );
  if (send.phase === 'accepted' || send.phase === 'uploaded')
    return t('send.status.waiting');
  return t(live ? 'send.status.preparing' : 'send.status.awaitingConnection');
}

const network = { createSession, sendSessionTurn };

/** UI publication precedes persistence; dispatch follows persistence and readiness. */
export function useSessionSend({
  outbox,
  session,
  record,
  snapshot,
  connected,
  serverCreated,
  userId,
  overflow,
  services = network,
}: {
  outbox: ReturnType<typeof usePendingSends>;
  session: Session;
  record?: PendingSession;
  snapshot: Snapshot;
  connected: boolean;
  serverCreated: boolean;
  userId: string;
  overflow: boolean;
  services?: typeof network;
}) {
  const [clearDraftToken, setClearDraftToken] = useState(0);
  const [restoreDraftToken, setRestoreDraftToken] = useState(0);
  const working = useRef(false);
  const [dispatching, setDispatching] = useState(false);
  const cleared = useRef('');
  const send = record?.send;
  const live = snapshot.status === 'live';
  const hasPending = !!send && send.phase !== 'failed';

  useEffect(() => {
    if (!record || !outbox.ready || working.current) return;
    const send = record.send;
    const userIndex = snapshot.entries.findIndex(
      (entry) => entry.id === send.id,
    );
    // A cached user row can come from a write whose ACK was lost. Only an
    // actual reply or the send receipt confirms delivery; never replay the row.
    if (
      userIndex >= 0 &&
      !send.creation &&
      snapshot.entries
        .slice(userIndex + 1)
        .some((entry) => entry.role === 'assistant')
    ) {
      if (cleared.current !== send.id) {
        cleared.current = send.id;
        setClearDraftToken((token) => token + 1);
      }
      void outbox.remove(session.id).catch(() => {});
      return;
    }
    if (send.creation && serverCreated && send.phase === 'unknown') {
      void outbox
        .put({
          ...record,
          send: { ...send, creation: undefined, phase: 'waiting' },
        })
        .catch(() => {});
      return;
    }
    if (send.phase !== 'waiting' || overflow || !userId) return;
    if (userIndex >= 0 && !send.creation) return;
    if (send.creation ? !connected : !live) return;
    working.current = true;
    setDispatching(true);
    void (async () => {
      let started = false;
      try {
        await outbox.put({
          ...record,
          send: { ...send, phase: send.creation ? 'creating' : 'sending' },
        });
        const latest = outbox
          .getSnapshot()
          .records.find((item) => item.session.id === session.id)?.send;
        if (
          latest?.id !== send.id ||
          latest.phase !== (send.creation ? 'creating' : 'sending')
        )
          return;
        started = true;
        if (send.creation) {
          const result = JSON.parse(
            await services.createSession(send.creation),
          );
          if (result.state === 'created') {
            await outbox.put({
              session: result.session,
              send: { ...send, creation: undefined, phase: 'waiting' },
            });
          } else if (result.state === 'rejected') {
            await fail(t('send.error.sessionNotCreated'));
          } else {
            await outbox.put({
              ...record,
              send: { ...send, phase: 'unknown' },
            });
          }
          return;
        }
        const result = JSON.parse(
          await services.sendSessionTurn(
            JSON.stringify({
              id: send.id,
              sessionId: session.id,
              machineId: session.machineId,
              userId,
              text: send.text,
              attachments: send.attachments,
              cliType: session.cliType,
              agentType: session.agentType,
              resume: session.resume,
              modelId: send.choice.modelId,
              modeId: send.choice.modeId,
              reasoningEffort: send.choice.effort,
              reasoningEffortConfigId: send.choice.reasoningEffortConfigId,
            }),
          ),
        );
        if (result.state === 'not_sent') {
          await fail(result.reason || t('send.error.notSent'));
        } else {
          const phase = ['accepted', 'uploaded'].includes(result.state)
            ? result.state
            : 'unknown';
          await outbox.put({ ...record, send: { ...send, phase } });
          if (phase !== 'unknown' && cleared.current !== send.id) {
            cleared.current = send.id;
            setClearDraftToken((token) => token + 1);
          }
        }
      } catch {
        if (started) {
          await outbox
            .put({ ...record, send: { ...send, phase: 'unknown' } })
            .catch(() => {});
        } else {
          await fail(t('send.error.draftSaveFailed'));
        }
      } finally {
        working.current = false;
        setDispatching(false);
      }
      async function fail(reason: string) {
        await outbox
          .put({ session, send: { ...send, phase: 'failed', reason } })
          .catch(() => {});
        Alert.alert(t('send.alert.title'), reason);
      }
    })();
  }, [
    record,
    snapshot,
    connected,
    serverCreated,
    overflow,
    userId,
    outbox.ready,
    dispatching,
  ]);

  function submit(next: PendingSend) {
    if (
      !outbox.ready ||
      hasPending ||
      overflow ||
      session.archived ||
      !userId
    ) {
      setRestoreDraftToken((token) => token + 1);
      return;
    }
    void outbox
      .put({
        session,
        send: { ...next, creation: send?.creation, phase: 'waiting' },
      })
      .catch(() => {
        void outbox
          .put({
            session,
            send: {
              ...next,
              creation: send?.creation,
              phase: 'failed',
              reason: t('send.error.draftSaveShort'),
            },
          })
          .catch(() => {});
      });
  }

  return {
    submit,
    clearDraftToken,
    restoreDraftToken,
    sending: hasPending,
    canSend:
      outbox.ready && !hasPending && !overflow && !session.archived && !!userId,
    pendingSendJSON: send
      ? JSON.stringify({
          ...send,
          status: pendingSendStatus(send, live),
          reconnect: send.phase === 'waiting' && !live,
          failed: send.phase === 'failed',
        })
      : '',
  };
}
