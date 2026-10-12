import { useEffect, useRef, useState } from 'react';
import { Alert } from 'react-native';
import {
  createSession,
  sendSessionTurn,
  ensureSession,
  checkSessionSend,
  cancelSessionSend,
  addAttachmentUploadProgressListener,
  type AttachmentUploadProgress,
} from '@lody-ios/kit';
import type {
  PendingSend,
  PendingSession,
  usePendingSends,
} from '@/cloud/send/pendingSends';
import type { Session } from '@lody/cloud-runtime/models/catalog';
import type { Snapshot } from './useSessionRuntime';
import { sessionState } from './status';
import { resolveSessionMessageSubmitRoute } from './messageSubmitRoute';
import {
  outboxInflight,
  waitForSendReceipt,
} from '../../cloud/send/outboxInflight';
import { quotaError } from '../../cloud/send/quotaError';
import { t } from '../../lib/i18n/index.ts';
import { showToast } from '../../ui/toast.ts';

export function pendingSendStatus(send: PendingSend, live: boolean) {
  if (send.phase === 'failed') return t('native.chat.message.retry');
  if (send.phase === 'queued') return t('native.chat.row.queued');
  if (send.phase === 'unknown') return t('send.status.unknown');
  if (send.phase === 'creating') return t('send.status.creating');
  if (send.phase === 'sending')
    return t(
      send.attachments.length ? 'send.status.uploading' : 'send.status.sending',
    );
  if (send.guide && send.phase === 'uploaded')
    return t('native.chat.message.guide.confirming');
  if (send.phase === 'accepted' || send.phase === 'uploaded')
    return t('send.status.waiting');
  return t(live ? 'send.status.preparing' : 'send.status.awaitingConnection');
}

const network = {
  createSession,
  sendSessionTurn,
  ensureSession,
  checkSessionSend,
  cancelSessionSend,
  addAttachmentUploadProgressListener,
};

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
  queuedMessageBehavior = 'queue',
  steerable = false,
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
  queuedMessageBehavior?: string;
  steerable?: boolean;
  services?: {
    createSession: typeof createSession;
    sendSessionTurn: typeof sendSessionTurn;
    ensureSession: typeof ensureSession;
    checkSessionSend?: typeof checkSessionSend;
    cancelSessionSend?: typeof cancelSessionSend;
    addAttachmentUploadProgressListener?: typeof addAttachmentUploadProgressListener;
  };
}) {
  const [clearDraftToken, setClearDraftToken] = useState(0);
  const [restoreDraftToken, setRestoreDraftToken] = useState(0);
  const working = useRef(false);
  const [dispatching, setDispatching] = useState(false);
  const cleared = useRef('');
  const checked = useRef('');
  const recoveryWorking = useRef(false);
  const [recovering, setRecovering] = useState(false);
  const behaviorRef = useRef(queuedMessageBehavior);
  behaviorRef.current = queuedMessageBehavior;
  const send = record?.send;
  const live = snapshot.status === 'live';
  const hasPending =
    !!send &&
    !['failed', 'accepted', 'queued'].includes(send.phase) &&
    !(send.guide && send.phase === 'uploaded');
  const [uploadProgress, setUploadProgress] = useState<
    Record<string, AttachmentUploadProgress>
  >({});

  useEffect(() => {
    setUploadProgress({});
    if (send?.phase !== 'sending' || !send.attachments.length) return;
    let active = true;
    const subscription = services.addAttachmentUploadProgressListener?.(
      (event) => {
        if (
          !active ||
          event.sessionId !== session.id ||
          event.sendId !== send.id ||
          !send.attachments.some(
            (attachment) => attachment.id === event.attachmentId,
          )
        )
          return;
        setUploadProgress((old) => {
          const previous = old[event.attachmentId];
          if (
            previous?.phase === event.phase &&
            previous.percent === event.percent
          )
            return old;
          return { ...old, [event.attachmentId]: event };
        });
      },
    );
    return () => {
      active = false;
      subscription?.remove();
    };
  }, [
    send?.id,
    send?.phase,
    session.id,
    services.addAttachmentUploadProgressListener,
  ]);

  useEffect(() => {
    if (
      !send ||
      send.creation ||
      send.guide ||
      !['unknown', 'uploaded'].includes(send.phase) ||
      !live ||
      !connected ||
      working.current ||
      outboxInflight.has(session.id) ||
      !services.checkSessionSend
    )
      return;
    const key = `${send.id}:${send.phase}`;
    if (checked.current === key) return;
    checked.current = key;
    void recover('check', false);
  }, [send?.id, send?.phase, live, connected, dispatching]);

  useEffect(() => {
    if (
      !record ||
      !outbox.ready ||
      working.current ||
      outboxInflight.has(session.id)
    )
      return;
    const send = record.send;
    const userIndex = snapshot.entries.findIndex(
      (entry) => entry.id === send.id,
    );
    let precedingUserId: string | undefined;
    const hasReply = snapshot.entries.some((entry) => {
      if (entry.role === 'user') precedingUserId = entry.id;
      return (
        entry.role === 'assistant' &&
        (entry.userTurnId ?? precedingUserId) === send.id
      );
    });
    // A cached user row can come from a write whose ACK was lost. Only an
    // actual reply or the send receipt confirms delivery; never replay the row.
    if (!send.creation && hasReply) {
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
    if (
      ['accepted', 'queued'].includes(send.phase) &&
      cleared.current !== send.id
    ) {
      cleared.current = send.id;
      setClearDraftToken((token) => token + 1);
    }
    if (send.phase !== 'waiting' || overflow || !userId) return;
    if (userIndex >= 0 && !send.creation) return;
    if (send.creation ? !connected : !live) return;
    working.current = true;
    outboxInflight.add(session.id);
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
        if (send.creation) {
          started = true;
          const result = JSON.parse(
            await waitForSendReceipt(services.createSession(send.creation)),
          );
          if (!current()) return;
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
        const route = resolveSessionMessageSubmitRoute({
          forceDirect: false,
          forceQueue: false,
          isPromptBusy:
            send.queue === true ||
            ['live', 'attention'].includes(sessionState(session.status)),
          hasUnfinishedAssistantTurn: snapshot.entries.some(
            (entry) => entry.role === 'assistant' && !entry.finished,
          ),
          queuedMessageBehavior: behaviorRef.current,
        });
        const guiding = (send.guide ?? route.type === 'guide') && steerable;
        started = true;
        const result = JSON.parse(
          await waitForSendReceipt(
            services.sendSessionTurn(
              JSON.stringify({
                id: send.id,
                sessionId: session.id,
                machineId: session.machineId,
                userId,
                queue: !guiding && route.type !== 'direct_dispatch',
                guide: guiding,
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
                mcpServerIds: send.choice.mcpServerIds,
                agentRoleId: send.choice.agentRoleId,
                agentRoleRevision: send.choice.agentRoleRevision,
                frozenRole: send.choice.frozenRole,
              }),
            ),
          ),
        );
        if (!current()) return;
        if (result.state === 'not_sent') {
          if (result.reason === 'send_cancelled') return;
          await fail(quotaError(result.reason, t('send.error.notSent')));
        } else {
          const phase = ['accepted', 'uploaded', 'queued'].includes(
            result.state,
          )
            ? result.state
            : 'unknown';
          await outbox.put({
            ...record,
            send: { ...send, guide: guiding, phase },
          });
          if (phase !== 'unknown' && cleared.current !== send.id) {
            cleared.current = send.id;
            setClearDraftToken((token) => token + 1);
          }
        }
      } catch {
        if (!current()) return;
        if (started) {
          await outbox
            .put({ ...record, send: { ...send, phase: 'unknown' } })
            .catch(() => {});
        } else {
          await fail(t('send.error.draftSaveFailed'));
        }
      } finally {
        working.current = false;
        outboxInflight.delete(session.id);
        setDispatching(false);
      }
      async function fail(reason: string) {
        if (!current()) return;
        if (reason === 'mention_expansion_failed')
          reason = t('send.error.mentions');
        await outbox
          .put({ session, send: { ...send, phase: 'failed', reason } })
          .catch(() => {});
        Alert.alert(t('send.alert.title'), reason);
      }
      function current() {
        return outbox
          .getSnapshot()
          .records.some(
            (item) =>
              item.session.id === session.id && item.send.id === send.id,
          );
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
    steerable,
  ]);

  async function recover(
    action: 'check' | 'resume' | 'cancel',
    feedback = true,
  ) {
    if (!record || recoveryWorking.current) return;
    const original = outbox
      .getSnapshot()
      .records.find(
        (item) =>
          item.session.id === session.id && item.send.id === record.send.id,
      );
    if (!original) return;
    const current = () =>
      outbox
        .getSnapshot()
        .records.some(
          (item) =>
            item.session.id === session.id && item.send.id === original.send.id,
        );
    if (action === 'resume') {
      if (
        !['unknown', 'uploaded'].includes(original.send.phase) ||
        original.send.creation
      )
        return;
      Alert.alert(
        t('send.recovery.resumeTitle'),
        t('send.recovery.resumeDetail'),
        [
          { text: t('common.cancel'), style: 'cancel' },
          {
            text: t('send.recovery.resume'),
            onPress: () => {
              if (!current()) return;
              void outbox
                .remove(session.id)
                .then(() => {
                  cleared.current = original.send.id;
                  setClearDraftToken((token) => token + 1);
                })
                .catch(() => showToast(t('send.recovery.failed')));
            },
          },
        ],
      );
      return;
    }
    recoveryWorking.current = true;
    setRecovering(true);
    try {
      if (action === 'cancel') {
        if (!['waiting', 'sending'].includes(original.send.phase)) return;
        let cancelled =
          original.send.phase === 'waiting' &&
          !working.current &&
          !outboxInflight.has(session.id);
        if (!cancelled && services.cancelSessionSend) {
          const result = JSON.parse(
            await services.cancelSessionSend(
              JSON.stringify({ sessionId: session.id, id: original.send.id }),
            ),
          );
          cancelled = result.state === 'cancelled';
        }
        if (!current()) return;
        if (!cancelled) {
          showToast(t('send.recovery.cannotCancel'));
          return;
        }
        await outbox.remove(session.id);
        setRestoreDraftToken((token) => token + 1);
        return;
      }
      if (!connected || !live || !services.checkSessionSend) {
        if (feedback) showToast(t('send.recovery.offline'));
        return;
      }
      const result = JSON.parse(
        await services.checkSessionSend(
          JSON.stringify({ sessionId: session.id, id: original.send.id }),
        ),
      );
      if (!current()) return;
      if (result.state === 'accepted' || result.state === 'queued') {
        await outbox.put({
          ...original,
          send: { ...original.send, phase: result.state, reason: undefined },
        });
        if (cleared.current !== original.send.id) {
          cleared.current = original.send.id;
          setClearDraftToken((token) => token + 1);
        }
        if (feedback) showToast(t('send.recovery.confirmed'));
      } else if (feedback) {
        showToast(t('send.recovery.unconfirmed'));
      }
    } catch {
      if (current() && feedback) showToast(t('send.recovery.failed'));
    } finally {
      recoveryWorking.current = false;
      setRecovering(false);
    }
  }

  function submit(next: PendingSend) {
    if (
      !outbox.ready ||
      working.current ||
      hasPending ||
      overflow ||
      session.archived ||
      !userId
    ) {
      setRestoreDraftToken((token) => token + 1);
      return;
    }
    // A failed first turn has no remote history to inherit these choices from.
    const choice = {
      ...next.choice,
      configOptionValues:
        next.choice.configOptionValues ?? send?.choice.configOptionValues,
    };
    void outbox
      .put({
        session,
        send: {
          ...next,
          choice,
          guide: next.guide === true && steerable,
          creation: send?.creation,
          phase: 'waiting',
        },
      })
      .catch(() => {
        void outbox
          .put({
            session,
            send: {
              ...next,
              choice,
              creation: send?.creation,
              phase: 'failed',
              reason: t('send.error.draftSaveShort'),
            },
          })
          .catch(() => {});
      });
  }

  let pendingSendJSON = '';
  if (send) {
    pendingSendJSON = JSON.stringify({
      ...send,
      uploadProgress: send.phase === 'sending' ? uploadProgress : undefined,
      queue:
        send.queue === true &&
        (send.phase === 'queued' ||
          !['accepted', 'uploaded', 'failed'].includes(send.phase)),
      status: pendingSendStatus(send, live),
      reconnect: send.phase === 'waiting' && !live,
      failed: send.phase === 'failed',
    });
  }
  return {
    submit,
    recover,
    recovering,
    sendRecovery: (() => {
      if (!send || send.creation || send.guide) return undefined;
      if (['unknown', 'uploaded'].includes(send.phase)) return 'unknown';
      if (['waiting', 'sending'].includes(send.phase)) return 'preparing';
      return undefined;
    })(),
    retry: () => {
      if (!record || record.send.phase !== 'failed' || working.current) return;
      void outbox
        .put({
          ...record,
          send: { ...record.send, phase: 'waiting', reason: undefined },
        })
        .catch(() => {});
    },
    clearDraftToken,
    restoreDraftToken,
    sending: hasPending,
    awaitingReply:
      !!send && !send.creation && ['accepted', 'uploaded'].includes(send.phase),
    canSend:
      outbox.ready &&
      !dispatching &&
      !hasPending &&
      send?.phase !== 'failed' &&
      !overflow &&
      !session.archived &&
      !!userId,
    pendingSendJSON,
  };
}
