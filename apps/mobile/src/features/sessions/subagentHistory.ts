import type {
  EntrySummary,
  ItemSummary,
} from '@lody/cloud-runtime/models/session';

export type SubagentTask = Extract<ItemSummary, { type: 'subagent_task' }>;

export function findSessionItem(
  entries: EntrySummary[],
  entryId: string,
  itemId: string,
) {
  const items = entries.find((entry) => entry.id === entryId)?.items ?? [];
  for (const item of items) {
    if (item.itemId === itemId) return item;
    if (item.type !== 'subagent_task') continue;
    const child = (item as SubagentTask).run?.items.find(
      (child) => child.itemId === itemId,
    );
    if (child) return child;
  }
}

export function subagentEntries(
  entryId: string,
  task: SubagentTask,
): EntrySummary[] {
  if (!task.run) return [];
  const items = [...task.run.items];
  const result = (task.status === 'failed' ? task.error : task.summary)?.trim();
  if (
    result &&
    !items.some(
      (item) =>
        item.type === 'text' && 'text' in item && item.text.trim() === result,
    )
  ) {
    items.push({
      itemId: `${task.itemId}:result`,
      rev: task.rev,
      type: 'text',
      text: result,
    });
  }
  const finished = !['pending', 'running', 'in_progress'].includes(
    task.run.state,
  );
  return [
    {
      id: entryId,
      rev: task.rev,
      role: 'assistant',
      status: task.run.state,
      finished,
      items,
    },
  ];
}
