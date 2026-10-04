export const QUEUED_MESSAGE_BEHAVIORS = ['queue', 'guide'] as const;
export type QueuedMessageBehavior = (typeof QUEUED_MESSAGE_BEHAVIORS)[number];

export type SessionMessageSubmitRoute =
  | { type: 'direct_dispatch' }
  | { type: 'guide' }
  | {
      type: 'queue';
      reason: 'forced' | 'prompt_busy' | 'unfinished_assistant_turn';
    };

export type SessionMessageSubmitRouteInput = {
  forceDirect: boolean;
  forceQueue: boolean;
  isPromptBusy: boolean;
  hasUnfinishedAssistantTurn: boolean;
  queuedMessageBehavior: string;
};

export function parseQueuedMessageBehavior(
  value: unknown,
): QueuedMessageBehavior {
  return value === 'guide' ? 'guide' : 'queue';
}

export function resolveSessionMessageSubmitRoute({
  forceDirect,
  forceQueue,
  isPromptBusy,
  hasUnfinishedAssistantTurn,
  queuedMessageBehavior,
}: SessionMessageSubmitRouteInput): SessionMessageSubmitRoute {
  if (forceDirect) return { type: 'direct_dispatch' };
  if (
    !forceQueue &&
    isPromptBusy &&
    parseQueuedMessageBehavior(queuedMessageBehavior) === 'guide' &&
    hasUnfinishedAssistantTurn
  ) {
    return { type: 'guide' };
  }
  if (forceQueue) return { type: 'queue', reason: 'forced' };
  if (isPromptBusy) return { type: 'queue', reason: 'prompt_busy' };
  if (hasUnfinishedAssistantTurn)
    return { type: 'queue', reason: 'unfinished_assistant_turn' };
  return { type: 'direct_dispatch' };
}
