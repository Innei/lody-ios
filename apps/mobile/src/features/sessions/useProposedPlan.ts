import { useMemo, useRef, useSyncExternalStore } from 'react';
import { sendSessionTurn } from '@lody-ios/kit';
import type { EntrySummary } from '@/models/session';
import { createPlanDecision, latestProposedPlan } from './proposedPlan';
import { t } from '@/lib/i18n';

export function useProposedPlan({
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
  const target = latestProposedPlan(entries);
  const current = useRef({ target, enabled, payload, request });
  current.current = { target, enabled, payload, request };
  const controller = useMemo(
    () =>
      createPlanDecision(
        () => current.current,
        (id) =>
          current.current.request(
            JSON.stringify({
              ...current.current.payload,
              id,
              sessionId,
              text: t('native.chat.proposedPlan.executePrompt'),
              attachments: [],
              queue: false,
              guide: false,
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
  const sentIndex = attempt?.sendId
    ? entries.findIndex((entry) => entry.id === attempt.sendId)
    : -1;
  const replied =
    sentIndex >= 0 &&
    entries.slice(sentIndex + 1).some((entry) => entry.role === 'assistant');
  let selected = target;
  if (pending || (!target && attempt?.phase === 'unknown' && !replied))
    selected = attempt;
  const same =
    selected &&
    attempt?.entryId === selected.entryId &&
    attempt.turnId === selected.turnId;
  const blocked = same && attempt.phase !== 'failed';
  const visible =
    selected && !(same && ['accepted', 'dismissed'].includes(attempt.phase));
  let message = '';
  if (same && attempt.phase === 'failed')
    message = t('native.chat.proposedPlan.failed');
  if (same && attempt.phase === 'unknown')
    message = t('native.chat.proposedPlan.unknown');
  return {
    pending,
    decide: controller.decide,
    stateJSON: JSON.stringify(
      visible && (enabled || same)
        ? {
            ...selected,
            enabled: enabled && !blocked && !pending,
            pending,
            message,
          }
        : {},
    ),
  };
}
