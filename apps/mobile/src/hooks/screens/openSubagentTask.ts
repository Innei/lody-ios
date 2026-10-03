import { present } from '@/lib/presentation';
import {
  SubagentTaskScreen,
  type SubagentTask,
  type SubagentTaskParams,
} from '@/screens/SubagentTaskScreen';
import type { ItemSummary } from '@/models/session';

export function openSubagentTask(
  item: ItemSummary | undefined,
  live?: Pick<SubagentTaskParams, 'entryId' | 'source' | 'onStop'>,
): boolean {
  if (item?.type !== 'subagent_task') return false;
  void present(SubagentTaskScreen, { ...(item as SubagentTask), ...live });
  return true;
}
