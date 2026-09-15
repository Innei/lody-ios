import type { EntrySummary } from '../../models/session.ts';

const recoverable = new Set([
  'acp_provider_overloaded',
  'acp_upstream_api_error',
  'acp_internal_error',
  'acp_unknown_error',
  'agent_disconnected',
  'agent_no_output',
  'acp_not_ready',
]);
export type ErrorTarget = { entryId: string; itemId: string; reason: string };
export function latestRetryableError(
  entries: EntrySummary[],
): ErrorTarget | undefined {
  for (let index = entries.length - 1; index >= 0; index--) {
    const entry = entries[index];
    if (entry.role === 'user') return;
    for (const item of [...entry.items].reverse()) {
      if (
        item.type !== 'system_notice' ||
        !('name' in item) ||
        item.name !== 'chat_failed'
      )
        continue;
      const reason = item.meta?.reason ?? '';
      if (
        !recoverable.has(reason) ||
        item.meta?.code === 'git_executable_not_found'
      )
        return;
      return { entryId: entry.id, itemId: item.itemId, reason };
    }
  }
}
export const capacityContinuation =
  'Continue working from where you left off. The previous turn stopped because the selected model was at capacity.';
export const errorContinuation =
  'Continue working from where you left off. The previous turn stopped because of an agent error.';
export type RetryAttempt = ErrorTarget & {
  sendId: string;
  phase: 'pending' | 'accepted' | 'failed' | 'unknown';
};

/** One explicit new turn; never replay a previous write or infer completion from its ACK. */
export function createAgentErrorRetry(
  context: () => { target?: ErrorTarget; enabled: boolean },
  request: (target: ErrorTarget, id: string) => Promise<string>,
) {
  let attempt: RetryAttempt | undefined;
  const listeners = new Set<() => void>();
  const update = (value: RetryAttempt) => {
    attempt = value;
    listeners.forEach((notify) => notify());
  };
  return {
    getSnapshot: () => attempt,
    subscribe: (notify: () => void) => {
      listeners.add(notify);
      return () => {
        listeners.delete(notify);
      };
    },
    async retry(entryId: string, itemId: string, id: string) {
      const { target, enabled } = context();
      if (
        !id ||
        !enabled ||
        !target ||
        target.entryId !== entryId ||
        target.itemId !== itemId ||
        attempt?.phase === 'pending'
      )
        return;
      if (
        attempt?.entryId === entryId &&
        attempt.itemId === itemId &&
        attempt.phase !== 'failed'
      )
        return;
      update({ ...target, sendId: id, phase: 'pending' });
      try {
        const result = JSON.parse(await request(target, id));
        let phase: RetryAttempt['phase'] = 'unknown';
        if (result.state === 'not_sent') phase = 'failed';
        else if (['accepted', 'uploaded', 'queued'].includes(result.state))
          phase = 'accepted';
        update({ ...target, sendId: id, phase });
      } catch {
        update({ ...target, sendId: id, phase: 'unknown' });
      }
    },
  };
}
