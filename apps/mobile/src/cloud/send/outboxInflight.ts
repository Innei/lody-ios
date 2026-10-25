import { outboxInflight as inflight, setOutboxInflight } from '@lody-ios/kit';

export const outboxInflight = {
  has: (sessionId: string) => inflight(sessionId),
  add: (sessionId: string) => setOutboxInflight(sessionId, true),
  delete: (sessionId: string) => setOutboxInflight(sessionId, false),
};
