import type {
  EntrySummary,
  ItemSummary,
} from '@lody/cloud-runtime/models/session';
import type {
  SubagentHistoryFragment,
  SubagentState,
} from '@lody/cloud-runtime/models/subagent-history';

export function subagentTranscript(
  taskId: string,
  fragments: SubagentHistoryFragment[],
  state: SubagentState,
): EntrySummary[] {
  const entries = new Map<string, EntrySummary>();
  const items = new Map<
    number,
    { fragment: SubagentHistoryFragment; item: ItemSummary }
  >();
  for (const fragment of fragments) {
    const previous = items.get(fragment.index)?.item;
    const item = fragment.item;
    if (
      (item.type === 'text' || item.type === 'thought') &&
      previous?.type === item.type
    ) {
      const before = previous as Extract<
        ItemSummary,
        { type: 'text' | 'thought' }
      >;
      const after = item as Extract<ItemSummary, { type: 'text' | 'thought' }>;
      items.set(fragment.index, {
        fragment,
        item: { ...after, text: before.text + after.text },
      });
    } else {
      items.set(fragment.index, { fragment, item });
    }
  }
  for (const { fragment, item } of items.values()) {
    const turn = fragment.nativeTurnId ?? fragment.messageId ?? 'retained';
    const id = `subagent:${taskId}:${turn}`;
    let entry = entries.get(id);
    if (!entry) {
      entry = {
        id,
        rev: 0,
        role: 'assistant',
        status: state,
        finished: state !== 'running' && state !== 'pending',
        items: [],
      };
      entries.set(id, entry);
    }
    entry.items.push(item);
    entry.rev += item.rev;
  }
  return [...entries.values()];
}
