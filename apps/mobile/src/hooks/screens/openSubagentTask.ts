import { present } from '@/lib/presentation';
import {
  SubagentTaskScreen,
  type SubagentTask,
} from '@/screens/SubagentTaskScreen';
import type { ItemSummary } from '@lody/cloud-runtime/models/session';
import type { SubagentIdentity } from '@lody/cloud-runtime/models/subagent-history';
import type { SubagentHistoryScope } from '@/cloud/subagent-history';

export function openSubagentTask(
  item: ItemSummary | undefined,
  context?: Pick<SubagentIdentity, 'sessionId' | 'entryId' | 'parentTurnId'> &
    SubagentHistoryScope,
): boolean {
  if (item?.type !== 'subagent_task') return false;
  const task = item as SubagentTask;
  const identity = context
    ? {
        sessionId: context.sessionId,
        entryId: context.entryId,
        parentTurnId: context.parentTurnId,
        itemId: task.itemId,
        taskId: task.taskId,
        runSessionId: task.run?.sessionId,
      }
    : undefined;
  const scope = context
    ? { workspaceId: context.workspaceId, userId: context.userId }
    : undefined;
  void present(SubagentTaskScreen, { task, identity, scope });
  return true;
}
