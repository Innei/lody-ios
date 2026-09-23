import { useEffect, useRef } from 'react';
import { Alert } from 'react-native';
import {
  createSession,
  sendSessionTurn,
  ensureSession,
  releaseReserve,
} from '@lody-ios/kit';
import type { PendingSession, usePendingSends } from './pendingSends';
import type { Session } from '../../models/catalog';
import { sessionState } from '../../features/sessions/status';
import { t } from '../../lib/i18n/index.ts';
import { outboxInflight } from './outboxInflight';
import { quotaError } from './quotaError';

export const MAX_SESSION_RESERVES = 8;
export { outboxInflight };

const occupying = new Set(['creating', 'sending', 'unknown', 'uploaded']);

const network = {
  createSession,
  sendSessionTurn,
  ensureSession,
  releaseReserve,
};

export function useOutboxDispatcher({
  outbox,
  userId,
  connected,
  serverSessions,
  foregroundSessionId,
  services = network,
}: {
  outbox: ReturnType<typeof usePendingSends>;
  userId: string;
  connected: boolean;
  serverSessions: Session[];
  foregroundSessionId: string;
  services?: {
    createSession: typeof createSession;
    sendSessionTurn: typeof sendSessionTurn;
    ensureSession: typeof ensureSession;
    releaseReserve: typeof releaseReserve;
  };
}) {
  const released = useRef(new Map<string, string>());

  useEffect(() => {
    if (!outbox.ready || !userId) return;
    let slots = 0;
    for (const record of outbox.records) {
      if (record.session.id === foregroundSessionId) continue;
      if (occupying.has(record.send.phase)) slots += 1;
    }
    for (const record of outbox.records) void consider(record);

    async function consider(record: PendingSession) {
      const { session, send } = record;
      if (['accepted', 'queued', 'failed'].includes(send.phase)) {
        const key = `${session.id}:${send.id}:${send.phase}`;
        if (released.current.get(session.id) === key) return;
        released.current.set(session.id, key);
        await services.releaseReserve(session.id).catch(() => {});
        return;
      }
      released.current.delete(session.id);
      const catalog = serverSessions.find((item) => item.id === session.id);
      if (
        (send.phase === 'unknown' || send.phase === 'uploaded') &&
        catalog?.latestUserMsgId === send.id
      ) {
        await outbox.remove(session.id).catch(() => {});
        await services.releaseReserve(session.id).catch(() => {});
        return;
      }
      if (send.creation && catalog && send.phase === 'unknown') {
        await outbox
          .put({
            ...record,
            send: { ...send, creation: undefined, phase: 'waiting' },
          })
          .catch(() => {});
        return;
      }
      if (session.id === foregroundSessionId) return;
      if (send.phase !== 'waiting' || outboxInflight.has(session.id)) return;
      if (!connected) return;
      if (slots >= MAX_SESSION_RESERVES) return;
      slots += 1;
      outboxInflight.add(session.id);
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
        if (send.creation) {
          started = true;
          const result = JSON.parse(
            await services.createSession(send.creation),
          );
          if (result.state === 'created') {
            outboxInflight.delete(session.id);
            await outbox.put({
              session: result.session,
              send: { ...send, creation: undefined, phase: 'waiting' },
            });
          } else if (result.state === 'rejected') {
            await fail(
              quotaError(result.reason, t('send.error.sessionNotCreated')),
            );
          } else {
            await outbox.put({
              ...record,
              send: { ...send, phase: 'unknown' },
            });
          }
          return;
        }
        try {
          await services.ensureSession(session.id);
        } catch {
          await fail(t('native.runtime.sessionNotSyncedRetry'));
          return;
        }
        started = true;
        const result = JSON.parse(
          await services.sendSessionTurn(
            JSON.stringify({
              id: send.id,
              sessionId: session.id,
              machineId: session.machineId,
              userId,
              guide: send.guide === true,
              queue:
                !send.guide &&
                (send.queue === true ||
                  ['live', 'attention'].includes(sessionState(session.status))),
              text: send.text,
              attachments: send.attachments,
              cliType: session.cliType,
              agentType: session.agentType,
              resume: session.resume,
              modelId: send.choice.modelId,
              modeId: send.choice.modeId,
              reasoningEffort: send.choice.effort,
              reasoningEffortConfigId: send.choice.reasoningEffortConfigId,
              configOptionValues: send.choice.configOptionValues,
            }),
          ),
        );
        if (result.state === 'not_sent') {
          if (result.reason === 'session_not_ready') {
            await outbox.put({
              ...record,
              send: { ...send, phase: 'waiting' },
            });
            return;
          }
          await fail(quotaError(result.reason, t('send.error.notSent')));
          return;
        }
        const phase = ['accepted', 'uploaded', 'queued'].includes(result.state)
          ? result.state
          : 'unknown';
        await outbox.put({ ...record, send: { ...send, phase } });
      } catch {
        if (started) {
          await outbox
            .put({ ...record, send: { ...send, phase: 'unknown' } })
            .catch(() => {});
        } else {
          await fail(t('send.error.draftSaveFailed'));
        }
      } finally {
        outboxInflight.delete(session.id);
      }
      async function fail(reason: string) {
        if (reason === 'mention_expansion_failed')
          reason = t('send.error.mentions');
        await outbox
          .put({
            session,
            send: { ...send, phase: 'failed', reason },
          })
          .catch(() => {});
        Alert.alert(t('send.alert.title'), reason);
      }
    }
  }, [
    outbox.records,
    connected,
    serverSessions,
    userId,
    foregroundSessionId,
    outbox.ready,
  ]);
}
