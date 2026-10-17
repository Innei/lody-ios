import { z } from 'zod';
import { publishedSharesRaw } from '@lody-ios/kit';
import type {
  PublishedSharePage,
  PublishedSharesRequest,
} from '@lody/cloud-runtime/models/session-sharing';

const count = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const page = z.object({
  workspaceId: z.string().min(1),
  userId: z.string().min(1),
  page: z
    .array(
      z.object({
        shareId: z.string().regex(/^[a-zA-Z0-9_-]{1,128}$/),
        rootSessionId: z.string().min(1),
        publisherUserId: z.string().min(1),
        status: z.enum(['active', 'revoked']),
        title: z.string().max(4096),
        revision: count,
        credentialVersion: count.min(1),
        createdAt: count,
        updatedAt: count,
        totalBytes: count.optional(),
        conversationCount: count.optional(),
        canManage: z.boolean(),
        canRevoke: z.boolean(),
        hasLocalLink: z.boolean(),
      }),
    )
    .max(20),
  isDone: z.boolean(),
  continueCursor: z.string().max(4096),
});
export type PublishedSharesService = (
  request: PublishedSharesRequest,
) => Promise<PublishedSharePage>;
export const requestPublishedShares: PublishedSharesService = async (
  request,
) => {
  const result = JSON.parse(await publishedSharesRaw(JSON.stringify(request)));
  const known = [
    'shares_forbidden',
    'shares_conflict',
    'shares_unavailable',
    'shares_write_unknown',
    'shares_link_unavailable',
    'shares_link_failed',
  ];
  if (known.includes(result?.error)) throw new Error(result.error);
  const parsed = page.parse(result);
  if (
    parsed.workspaceId !== request.workspaceId ||
    (request.action !== 'list' &&
      (parsed.page.length !== 1 || parsed.page[0]?.shareId !== request.shareId))
  )
    throw new Error('shares_scope_changed');
  return parsed;
};
