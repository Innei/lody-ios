import { present } from '@/lib/presentation';
import {
  SubagentTaskScreen,
  type SubagentTask,
} from '@/screens/SubagentTaskScreen';
import type { ItemSummary } from '@/models/session';

export function openSubagentTask(item: ItemSummary | undefined): boolean {
  if (item?.type !== 'subagent_task') return false;
  void present(SubagentTaskScreen, item as SubagentTask);
  return true;
}
