import { present } from '@/lib/presentation';
import { AgentErrorScreen } from '@/screens/AgentErrorScreen';
import type { ItemSummary } from '@/models/session';

/** Error details are already in the local projection, including while offline. */
export function openAgentError(item: ItemSummary | undefined): boolean {
  if (
    item?.type !== 'system_notice' ||
    !('name' in item) ||
    item.name !== 'chat_failed'
  )
    return false;
  void present(AgentErrorScreen, item.meta ?? {});
  return true;
}
