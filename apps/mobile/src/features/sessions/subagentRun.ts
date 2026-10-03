import type { ItemSummary } from '../../models/session.ts';
import { t, tp } from '../../lib/i18n/index.ts';

export type SubagentTask = Extract<ItemSummary, { type: 'subagent_task' }>;

const terminal = new Set(['completed', 'failed', 'cancelled']);

export function runEntries(task: SubagentTask) {
  const run = task.run;
  if (!run) return [];
  const finished = terminal.has(run.state);
  return [
    {
      id: `run:${task.itemId}`,
      rev: task.rev,
      role: 'assistant',
      status: finished ? 'completed' : 'running',
      finished,
      items: run.items,
    },
  ];
}

const tokens = (value: number) =>
  value >= 1000 ? `${(value / 1000).toFixed(1)}k` : String(value);

export function runMeta(task: SubagentTask) {
  const run = task.run;
  if (!run) return '';
  return [
    run.modelId,
    run.totalTokens === undefined
      ? ''
      : t('subagent.run.tokens', { value: tokens(run.totalTokens) }),
    run.toolCallCount === undefined
      ? ''
      : tp('subagent.run.tools', run.toolCallCount, {
          count: run.toolCallCount,
        }),
    run.contextUsagePercent === undefined
      ? ''
      : t('subagent.run.context', { value: run.contextUsagePercent }),
  ]
    .filter(Boolean)
    .join(' · ');
}

export function liveTask(
  task: SubagentTask,
  entryId: string,
  entriesJSON: string,
): SubagentTask {
  const entries = JSON.parse(entriesJSON) as {
    id: string;
    items?: ItemSummary[];
  }[];
  const found = entries
    .find((entry) => entry.id === entryId)
    ?.items?.find((item) => item.itemId === task.itemId);
  return found?.type === 'subagent_task' ? (found as SubagentTask) : task;
}
