import { parseQueuedMessageBehavior } from '@/features/sessions/messageSubmitRoute';
import { usePreferences } from '@/lib/preferences';

export function useQueuedMessageBehavior() {
  const { queuedMessageBehavior } = usePreferences();
  return {
    queuedMessageBehavior: parseQueuedMessageBehavior(queuedMessageBehavior),
  };
}
