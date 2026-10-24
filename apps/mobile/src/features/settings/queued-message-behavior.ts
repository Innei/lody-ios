import { saveQueuedMessageBehavior } from '@lody-ios/kit';
import {
  parseQueuedMessageBehavior,
  type QueuedMessageBehavior,
} from '@/features/sessions/messageSubmitRoute';
import { setPreferences, usePreferences } from '@/lib/preferences';

function setQueuedMessageBehavior(value: QueuedMessageBehavior) {
  setPreferences({ queuedMessageBehavior: value });
  saveQueuedMessageBehavior(value);
}

export function useQueuedMessageBehavior() {
  const { queuedMessageBehavior } = usePreferences();
  return {
    queuedMessageBehavior: parseQueuedMessageBehavior(queuedMessageBehavior),
    setQueuedMessageBehavior,
  };
}
