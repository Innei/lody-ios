import { useMemo, useRef, useSyncExternalStore } from 'react';
import { sendSessionTurn } from '@lody-ios/kit';
import { t } from '@/lib/i18n';
import type { EntrySummary } from '@/models/session';
import {
  capacityContinuation,
  createAgentErrorRetry,
  errorContinuation,
  latestRetryableError,
} from './agentErrorRetry';

export function useAgentErrorRetry({
  sessionId,
  entries,
  enabled,
  payload,
  request = sendSessionTurn,
}: {
  sessionId: string;
  entries: EntrySummary[];
  enabled: boolean;
  payload: Record<string, unknown>;
  request?: (payload: string) => Promise<string>;
}) {
  const target = latestRetryableError(entries);
  const current = useRef({ target, enabled, payload, request });
  current.current = { target, enabled, payload, request };
  const controller = useMemo(
    () =>
      createAgentErrorRetry(
        () => current.current,
        (target, id) =>
          current.current.request(
            JSON.stringify({
              ...current.current.payload,
              id,
              sessionId,
              attachments: [],
              queue: false,
              guide: false,
              text:
                target.reason === 'acp_provider_overloaded'
                  ? capacityContinuation
                  : errorContinuation,
            }),
          ),
      ),
    [sessionId],
  );
  const attempt = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
  );
  const pending = attempt?.phase === 'pending';
  const sentIndex = attempt
    ? entries.findIndex((entry) => entry.id === attempt.sendId)
    : -1;
  const replyObserved =
    sentIndex >= 0 &&
    entries.slice(sentIndex + 1).some((entry) => entry.role === 'assistant');
  let selected = target;
  if (pending || (!target && attempt?.phase === 'unknown' && !replyObserved))
    selected = attempt;
  const same =
    selected &&
    attempt?.entryId === selected.entryId &&
    attempt.itemId === selected.itemId;
  const blocked =
    same && (attempt.phase === 'unknown' || attempt.phase === 'accepted');
  let message = '';
  if (same && attempt.phase === 'unknown')
    message = t('native.chat.error.retryUnknown');
  if (same && attempt.phase === 'failed')
    message = t('native.chat.error.retryFailed');
  return {
    pending,
    retry: controller.retry,
    stateJSON: JSON.stringify(
      selected
        ? {
            entryId: selected.entryId,
            itemId: selected.itemId,
            enabled: enabled && !pending && !blocked,
            pending,
            visible: !(same && attempt.phase === 'accepted'),
            message,
          }
        : {},
    ),
  };
}
