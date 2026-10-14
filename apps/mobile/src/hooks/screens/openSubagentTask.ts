import { present } from '@/lib/presentation';
import {
  SubagentTaskScreen,
  type SubagentTask,
  type SubagentTaskParams,
} from '@/screens/SubagentTaskScreen';
import type { ItemSummary } from '@lody/cloud-runtime/models/session';

export function openSubagentTask(
  item: ItemSummary | undefined,
  context: Omit<SubagentTaskParams, 'task'>,
): boolean {
  if (item?.type !== 'subagent_task') return false;
  void present(SubagentTaskScreen, { ...context, task: item as SubagentTask });
  return true;
}
