import { z } from 'zod/v4';

const target = {
  sessionId: z.string().min(1),
  userId: z.string().min(1),
};
const item = { ...target, id: z.string().min(1), revision: z.string().min(1) };

export const SessionQueueParams = z
  .discriminatedUnion('action', [
    z.object({ ...target, action: z.literal('list') }),
    z.object({
      ...item,
      action: z.literal('begin'),
      editToken: z.string().min(1),
    }),
    z.object({
      ...item,
      action: z.literal('cancel'),
      editToken: z.string().min(1),
    }),
    z.object({
      ...item,
      action: z.literal('save'),
      editToken: z.string().min(1),
      text: z.string().max(200_000),
    }),
    z.object({ ...item, action: z.literal('remove') }),
    z.object({ ...item, action: z.literal('move'), overId: z.string().min(1) }),
  ])
  .meta({ id: 'SessionQueueParams' });

export const SessionQueueItem = z
  .object({
    id: z.string(),
    revision: z.string(),
    messageId: z.string().optional(),
    text: z.string(),
    attachments: z.array(z.string()),
    editing: z.boolean(),
    editToken: z.string().optional(),
  })
  .meta({ id: 'SessionQueueItem' });

export const SessionQueueResult = z
  .object({
    state: z.enum(['ready', 'stale', 'unknown']),
    items: z.array(SessionQueueItem),
  })
  .meta({ id: 'SessionQueueResult' });

export type SessionQueueRequest = z.infer<typeof SessionQueueParams>;
