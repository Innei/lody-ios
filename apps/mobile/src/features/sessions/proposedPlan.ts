import type { EntrySummary } from '../../models/session.ts';
import type { Capability, ModelChoice } from '../../models/send.ts';

export type ProposedPlan = { entryId: string; itemId: string; turnId: string };
export function latestProposedPlan(
  entries: EntrySummary[],
): ProposedPlan | undefined {
  for (const entry of [...entries].reverse()) {
    // A subsequent user turn consumes the previous decision even after remount.
    if (entry.role === 'user') return;
    for (const item of [...entry.items].reverse()) {
      if (item.type !== 'proposed_plan' || !('markdown' in item)) continue;
      if (
        item.status !== 'completed' ||
        !item.isLatest ||
        !item.markdown.trim()
      )
        return;
      return { entryId: entry.id, itemId: item.itemId, turnId: item.turnId };
    }
  }
}

// OSS execution-turn-config: change this turn's planning choice, preserving permissions/model.
export function planExecutionChoice(
  choice: ModelChoice,
  capability?: Capability,
): ModelChoice {
  const modes = capability?.legacyModes ?? capability?.modes ?? [];
  const modeId =
    choice.modeId === 'plan'
      ? (modes.find((mode) => mode.id !== 'plan')?.id ?? choice.modeId)
      : choice.modeId;
  const values = { ...choice.configOptionValues };
  const core = capability?.configOptions?.find(
    (option) => option.id === 'plan_mode' && option.type === 'boolean',
  );
  const coreValue = values.plan_mode ?? core?.currentValue;
  if (typeof coreValue === 'boolean') {
    values.plan_mode = false;
  } else {
    const selector = capability?.configOptions?.find(
      (option) =>
        option.type === 'select' &&
        (option.id === 'collaboration_mode' ||
          option.category === 'collaboration_mode'),
    );
    const id = selector?.id ?? 'collaboration_mode';
    const value = values[id] ?? selector?.currentValue;
    if (
      value === 'plan' &&
      (!selector || selector.options.some((option) => option.id === 'default'))
    )
      values[id] = 'default';
  }
  return { ...choice, modeId, configOptionValues: values };
}

export type PlanAttempt = ProposedPlan & {
  sendId?: string;
  phase: 'pending' | 'accepted' | 'failed' | 'unknown' | 'dismissed';
};
export function createPlanDecision(
  context: () => { target?: ProposedPlan; enabled: boolean },
  request: (id: string) => Promise<string>,
) {
  let attempt: PlanAttempt | undefined;
  const listeners = new Set<() => void>();
  const update = (value: PlanAttempt) => {
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
    async decide(entryId: string, itemId: string, action: string, id: string) {
      const { target, enabled } = context();
      if (
        !target ||
        !enabled ||
        target.entryId !== entryId ||
        target.itemId !== itemId ||
        attempt?.phase === 'pending'
      )
        return;
      const same =
        attempt?.entryId === entryId && attempt.turnId === target.turnId;
      if (same && attempt?.phase !== 'failed') return;
      if (action === 'discuss') {
        update({ ...target, phase: 'dismissed' });
        return;
      }
      if (action !== 'execute' || !id) return;
      update({ ...target, sendId: id, phase: 'pending' });
      try {
        const result = JSON.parse(await request(id));
        let phase: PlanAttempt['phase'] = 'unknown';
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
